extends RefCounted
# One explicit remove gesture owns a fresh receipt read and at most one mutation.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase { Idle, Reading, Applying, Rejected, Stale, Unknown, Unavailable }
var phase:=Phase.Idle
var details
var service
var target: Dictionary={}
var owner: Dictionary={}
var ticket:=0
var generation:=0
var active:=false

func configure(model) -> void:
	dispose();details=model;service=model.service
	details.changed.connect(_details_changed)
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	details=null;service=null

func close() -> void:
	generation+=1
	var previous:=ticket
	ticket=0;active=false;target={};owner={};phase=Phase.Idle
	if service!=null and previous!=0:service.detach(previous)
	changed.emit()

func _key() -> Dictionary:
	return {"generation":details.generation,"identity":details.identity.duplicate(true),"revision":details.snapshot.get("revision",0)}

func _details_changed() -> void:
	if details==null:return
	if owner.is_empty():return
	if _key()!=owner or details.phase not in [details.Phase.Ready,details.Phase.Editing]:close()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func remove(row: Dictionary) -> void:
	if details==null or service==null or active or details.phase!=details.Phase.Ready:return
	if phase!=Phase.Idle and owner==_key():return
	if int(row.get("source",-1))!=1 or int(row.get("histfig_id",-1))<0:return
	var found:=false
	for current in details.snapshot.get("staff",{}).get("rows",[]):
		if current==row:found=true;break
	if not found:return
	for key in ["entity_id","assignment_id","histfig_id"]:
		if typeof(row.get(key))!=TYPE_INT or row[key]<0 or row[key]>2147483647:return
	close();owner=_key();target={"entity_id":row.entity_id,"assignment_id":row.assignment_id,"holder_id":row.histfig_id}
	active=true;phase=Phase.Reading;details.phase=details.Phase.Editing;details.changed.emit()
	_send(false)

func _send(apply: bool, revision:=0) -> void:
	var intent: Dictionary={"action":C.ManagementAction.AreaUpdate if apply else C.ManagementAction.AreaInspect,
		"operation":C.AreaOperation.LocationReligiousStaffRemove if apply else C.AreaOperation.LocationReligiousStaffRead,
		"kind":C.AreaKind.Zone,"location_site_id":owner.identity.site_id,"location_id":owner.identity.id,
		"religious_entity_id":target.entity_id,"religious_assignment_id":target.assignment_id}
	if apply:intent.expected_revision=revision;intent.religious_holder_id=target.holder_id
	var guard:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if guard==generation and received==ticket:_receive(result,sent))
	if ticket==0:_finish(Phase.Unavailable);return
	changed.emit()

func _finish(next: Phase, completed:=false) -> void:
	active=false;phase=next
	if details!=null and _key()==owner and details.phase==details.Phase.Editing:
		details.phase=details.Phase.Ready
		if completed:details.refresh()
		else:details.changed.emit()
	changed.emit()

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	if not active or details==null or _key()!=owner:close();return
	var apply: bool=sent.operation==C.AreaOperation.LocationReligiousStaffRemove
	var area: Dictionary=result.get("area",{})
	var outcome:=int(area.get("location_edit_outcome",C.LocationEditOutcome.None))
	if result.get("outcome","")=="unknown" or outcome==C.LocationEditOutcome.Unknown:
		_finish(Phase.Unknown);return
	if int(result.get("status",C.ManagementStatus.Rejected))!=C.ManagementStatus.Ok:
		_finish(Phase.Stale if outcome==C.LocationEditOutcome.Stale else Phase.Rejected);return
	var receipt: Dictionary=area.get("location_religious_staff",{})
	if (int(result.get("action",-1))!=sent.action or int(area.get("operation",-1))!=sent.operation
		or receipt.get("site_id")!=owner.identity.site_id or receipt.get("location_id")!=owner.identity.id
		or receipt.get("entity_id")!=target.entity_id or receipt.get("assignment_id")!=target.assignment_id
		or typeof(receipt.get("revision"))!=TYPE_INT or receipt.revision<=0
		or typeof(receipt.get("removable"))!=TYPE_BOOL
		or (apply and (outcome!=C.LocationEditOutcome.Completed or receipt.removable or receipt.get("holder_id")!=-1))):
		_finish(Phase.Unknown if apply else Phase.Rejected);return
	if apply:_finish(Phase.Idle,true);return
	# A new holder cannot be removed by a gesture made on the previous holder.
	if not receipt.removable or receipt.get("holder_id")!=target.holder_id:
		_finish(Phase.Stale);return
	phase=Phase.Applying;_send(true,receipt.revision)
