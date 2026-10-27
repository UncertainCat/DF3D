extends RefCounted
# A vacant-row gesture owns one list, one selected receipt and at most one edit.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
const Candidates=preload("res://scripts/location_staff_candidates_state.gd")
enum Mode { Closed, Choosing, Reading, Applying, Rejected, Stale, Unknown, Unavailable }
var mode:=Mode.Closed
var candidates=Candidates.new()
var details
var service
var owner: Dictionary={}
var blocked_owner: Dictionary={}
var target: Dictionary={}
var selected: Dictionary={}
var list_revision:=0
var ticket:=0
var generation:=0

func configure(model) -> void:
	dispose();details=model;service=model.service
	details.changed.connect(_details_changed)
	candidates.changed.connect(_candidates_changed)
	if service!=null:
		candidates.configure(service);service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	if candidates.changed.is_connected(_candidates_changed):candidates.changed.disconnect(_candidates_changed)
	if service!=null:
		if service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
		if service.session_changed.is_connected(candidates._session_changed):service.session_changed.disconnect(candidates._session_changed)
	details=null;service=null;blocked_owner={}

func _key() -> Dictionary:
	return {"generation":details.generation,"identity":details.identity.duplicate(true),"revision":details.snapshot.get("revision",0)}

func close() -> void:
	if mode==Mode.Applying:blocked_owner=owner.duplicate(true)
	var unlock: bool=details!=null and not owner.is_empty() and _key()==owner and details.phase==details.Phase.Editing
	generation+=1;var previous:=ticket;ticket=0;mode=Mode.Closed
	owner={};target={};selected={};list_revision=0
	if service!=null and previous!=0:service.detach(previous)
	candidates.close()
	if unlock:details.phase=details.Phase.Ready;details.changed.emit()
	changed.emit()

func open(row: Dictionary) -> void:
	if details==null or service==null or mode!=Mode.Closed or details.phase!=details.Phase.Ready or blocked_owner==_key():return
	if row.get("source")!=1 or row.get("histfig_id")!=-1:return
	var found:=false
	for current in details.snapshot.get("staff",{}).get("rows",[]):
		if current==row:found=true;break
	if not found:return
	for key in ["entity_id","assignment_id"]:
		if typeof(row.get(key))!=TYPE_INT or row[key]<0 or row[key]>2147483647:return
	owner=_key();target={"site_id":owner.identity.site_id,"location_id":owner.identity.id,
		"entity_id":row.entity_id,"assignment_id":row.assignment_id,"holder_id":-1}
	mode=Mode.Choosing;candidates.open_religious(target);changed.emit()

func choose(unit_id: int) -> void:
	if mode!=Mode.Choosing or candidates.phase!=Candidates.Phase.Ready or details.phase!=details.Phase.Ready:return
	if _key()!=owner:close();return
	for row in candidates.rows:
		if row.unit_id==unit_id:selected=row.duplicate(true);break
	if selected.is_empty():return
	list_revision=candidates.revision;mode=Mode.Reading
	details.phase=details.Phase.Editing;details.changed.emit();_send(false)

func _send(apply: bool, revision:=0) -> void:
	var intent: Dictionary={"action":C.ManagementAction.AreaUpdate if apply else C.ManagementAction.AreaInspect,
		"operation":C.AreaOperation.LocationReligiousAssign if apply else C.AreaOperation.LocationReligiousAssignmentRead,
		"kind":C.AreaKind.Zone,"location_site_id":target.site_id,"location_id":target.location_id,
		"religious_entity_id":target.entity_id,"religious_assignment_id":target.assignment_id,
		"religious_holder_id":target.holder_id,"unit_id":selected.unit_id,"expected_list_revision":list_revision}
	if apply:intent.expected_revision=revision
	var guard:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if guard==generation and ticket==received:_receive(result,sent))
	if ticket==0:_finish(Mode.Unavailable);return
	changed.emit()

func _finish(next: Mode, completed:=false) -> void:
	mode=next
	if not completed:blocked_owner=owner.duplicate(true)
	if details!=null and _key()==owner and details.phase==details.Phase.Editing:
		details.phase=details.Phase.Ready
		if completed:details.refresh();applied.emit()
		else:details.changed.emit()
	changed.emit()

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	if details==null or _key()!=owner:close();return
	var apply: bool=sent.operation==C.AreaOperation.LocationReligiousAssign
	var area: Dictionary=result.get("area",{})
	var outcome:=int(area.get("location_edit_outcome",C.LocationEditOutcome.None))
	if result.get("outcome","")=="unknown" or outcome==C.LocationEditOutcome.Unknown:_finish(Mode.Unknown);return
	if int(result.get("status",C.ManagementStatus.Rejected))!=C.ManagementStatus.Ok:
		_finish(Mode.Stale if outcome==C.LocationEditOutcome.Stale else Mode.Rejected);return
	var receipt: Dictionary=area.get("location_religious_staff",{}) if apply else area.get("location_religious_assignment",{}).get("target",{})
	var valid: bool=result.get("action")==sent.action and area.get("operation")==sent.operation
	for key in ["site_id","location_id","entity_id","assignment_id"]:
		valid=valid and receipt.get(key)==target[key]
	valid=valid and typeof(receipt.get("revision"))==TYPE_INT and int(receipt.get("revision",0))>0
	if apply:
		valid=valid and outcome==C.LocationEditOutcome.Completed and receipt.get("holder_id")==selected.histfig_id and receipt.get("unit_id")==selected.unit_id
		_finish(Mode.Closed if valid else Mode.Unknown,valid);return
	var candidate: Dictionary=area.get("location_religious_assignment",{})
	valid=valid and receipt==candidates.target_receipt and candidate.get("unit_id")==selected.unit_id and candidate.get("histfig_id")==selected.histfig_id
	valid=valid and candidate.get("list_revision")==list_revision and candidate.get("eligible")==true
	valid=valid and typeof(candidate.get("revision"))==TYPE_INT and int(candidate.get("revision",0))>0
	if not valid:_finish(Mode.Stale);return
	mode=Mode.Applying;_send(true,candidate.revision)

func _details_changed() -> void:
	if owner.is_empty():
		# Session loss retires authority. A later explicit Details observation may
		# enable a new gesture; reconnect alone must never submit or reopen it.
		if mode==Mode.Unavailable and details.phase==details.Phase.Ready:close()
		return
	if _key()!=owner or details.phase not in [details.Phase.Ready,details.Phase.Editing]:close()

func _candidates_changed() -> void:
	if mode==Mode.Choosing and candidates.phase in [Candidates.Phase.Rejected,Candidates.Phase.Unavailable]:
		_finish(Mode.Unavailable if candidates.phase==Candidates.Phase.Unavailable else Mode.Rejected)
	changed.emit()

func _session_changed() -> void:
	close();mode=Mode.Unavailable;changed.emit()
