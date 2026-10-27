extends RefCounted
# Displayed facts establish intent; a fresh native receipt authorizes one edit.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Idle, Reading, Applying, Rejected, Stale, Unknown, Unavailable }
var phase:=Phase.Idle
var details
var service
var owner: Dictionary={}
var blocked_owner: Dictionary={}
var target: Dictionary={}
var expected:=false
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
	details=null;service=null;blocked_owner={}

func _key() -> Dictionary:
	return {"generation":details.generation,"identity":details.identity.duplicate(true),"revision":details.snapshot.get("revision",0)}

func close() -> void:
	if phase==Phase.Applying:blocked_owner=owner.duplicate(true)
	var unlock: bool=details!=null and not owner.is_empty() and _key()==owner and details.phase==details.Phase.Editing
	generation+=1;var previous:=ticket
	ticket=0;active=false;owner={};target={};phase=Phase.Idle
	if service!=null and previous!=0:service.detach(previous)
	if unlock:details.phase=details.Phase.Ready;details.changed.emit()
	changed.emit()

func _details_changed() -> void:
	if details==null or owner.is_empty():return
	if _key()!=owner or details.phase not in [details.Phase.Ready,details.Phase.Editing]:close()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

static func row_target(row: Dictionary) -> Dictionary:
	var names: Dictionary=row.get("names",{})
	if row.get("source") not in [0,1] or names.get("holder_kind")!=1:return {}
	var value: Dictionary={"unit_id":names.get("holder_id"),"histfig_id":row.get("histfig_id"),
		"occupation_id":row.get("occupation_id",-1) if row.source==0 else -1,
		"entity_id":row.get("entity_id",-1) if row.source==1 else -1,
		"assignment_id":row.get("assignment_id",-1) if row.source==1 else -1}
	for key in value:
		var minimum: int=-1 if key in ["occupation_id","entity_id","assignment_id"] else 0
		if typeof(value[key])!=TYPE_INT or value[key]<minimum or value[key]>2147483647:return {}
	if (row.source==0 and value.occupation_id<0) or (row.source==1 and (value.entity_id<0 or value.assignment_id<0)):return {}
	return value

func _matches(receipt: Dictionary) -> bool:
	for key in target:
		if receipt.get(key)!=target[key]:return false
	return (receipt.get("site_id")==owner.identity.site_id and receipt.get("location_id")==owner.identity.id
		and typeof(receipt.get("revision"))==TYPE_INT and receipt.revision>0
		and typeof(receipt.get("eligible"))==TYPE_BOOL and typeof(receipt.get("specialized"))==TYPE_BOOL)

func toggle(row: Dictionary, displayed: Dictionary) -> void:
	if details==null or service==null or active or details.phase!=details.Phase.Ready or blocked_owner==_key():return
	var found:=false
	for current in details.snapshot.get("staff",{}).get("rows",[]):
		if current==row:found=true;break
	if not found:return
	var next:=row_target(row)
	if next.is_empty():return
	close();owner=_key();target=next
	if not _matches(displayed) or not displayed.eligible:close();return
	expected=displayed.specialized;active=true;phase=Phase.Reading
	details.phase=details.Phase.Editing;details.changed.emit()
	_send(false)

func _send(apply: bool, revision:=0) -> void:
	if not active or owner.is_empty() or details==null or _key()!=owner:return
	var intent: Dictionary={"action":C.ManagementAction.AreaUpdate if apply else C.ManagementAction.AreaInspect,
		"operation":C.AreaOperation.LocationSpecializationSet if apply else C.AreaOperation.LocationSpecializationRead,
		"kind":C.AreaKind.Zone,"location_site_id":owner.identity.site_id,"location_id":owner.identity.id,
		"occupation_id":target.occupation_id,"religious_entity_id":target.entity_id,
		"religious_assignment_id":target.assignment_id,"unit_id":target.unit_id}
	if apply:intent.expected_revision=revision;intent.value=int(not expected)
	var guard:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if guard==generation and ticket==received:_receive(result,sent))
	if ticket==0:_finish(Phase.Unavailable);return
	changed.emit()

func _finish(next: Phase, completed:=false) -> void:
	active=false;phase=next
	if not completed:blocked_owner=owner.duplicate(true)
	if details!=null and _key()==owner and details.phase==details.Phase.Editing:
		details.phase=details.Phase.Ready
		if completed:details.refresh();applied.emit()
		else:details.changed.emit()
	changed.emit()

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	if not active or details==null or _key()!=owner:close();return
	var apply: bool=sent.operation==C.AreaOperation.LocationSpecializationSet
	var area: Dictionary=result.get("area",{})
	var outcome:=int(area.get("location_edit_outcome",C.LocationEditOutcome.None))
	if result.get("outcome","")=="unknown" or outcome==C.LocationEditOutcome.Unknown:_finish(Phase.Unknown);return
	if int(result.get("status",C.ManagementStatus.Rejected))!=C.ManagementStatus.Ok:
		_finish(Phase.Stale if outcome==C.LocationEditOutcome.Stale else Phase.Rejected);return
	var receipt: Dictionary=area.get("location_specialization",{})
	if result.get("action")!=sent.action or area.get("operation")!=sent.operation or not _matches(receipt):
		_finish(Phase.Unknown if apply else Phase.Rejected);return
	if apply:
		var valid: bool=outcome==C.LocationEditOutcome.Completed and receipt.specialized!=expected
		_finish(Phase.Idle if valid else Phase.Unknown,valid);return
	# Do not silently invert a new state that the player never saw.
	if not receipt.eligible or receipt.specialized!=expected:_finish(Phase.Stale);return
	phase=Phase.Applying;_send(true,receipt.revision)
