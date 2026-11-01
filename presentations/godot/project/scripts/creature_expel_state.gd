extends RefCounted
signal changed
signal applied(unit_id: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Choosing,Confirming,Refused,Applying,Completed,Rejected,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var unit_id: int=-1
var destination_id: int=-1
var generation:=0
var ticket:=0
var _preview: Dictionary={}

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_invalidated)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_invalidated):service.session_changed.disconnect(_invalidated)
	service=null
func close() -> void:
	generation+=1
	if service!=null and ticket!=0:service.detach(ticket)
	ticket=0;unit_id=-1;destination_id=-1;_preview={};phase=Phase.Closed;changed.emit()
func snapshot() -> Dictionary:
	return _preview.duplicate(true)
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	unit_id=id;phase=Phase.Reading
	var owner:=generation
	ticket=service.submit("creature_expel",{"action":C.ManagementAction.CreatureExpelRead,"unit_id":id},func(received,result,_request):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("outcome","")=="unknown":_fail(Phase.Unavailable);return
		var payload: Dictionary=result.get("creature_expel",{})
		var observed: Dictionary=payload.get("preview",{})
		if result.get("action")!=C.ManagementAction.CreatureExpelRead or result.get("status")!=C.ManagementStatus.Ok or payload.get("outcome")!=C.CreatureExpelOutcome.Ready or not _valid(observed):
			_fail(Phase.Rejected);return
		_preview=observed.duplicate(true)
		phase=Phase.Refused if not observed.eligible or observed.reason!=-1 else Phase.Choosing if not observed.destinations.is_empty() else Phase.Confirming
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func choose(id: int) -> bool:
	if phase!=Phase.Choosing or ticket!=0:return false
	for row in _preview.destinations:
		if row.id==id:
			destination_id=id;phase=Phase.Confirming;changed.emit();return true
	return false
func confirm() -> bool:
	if phase!=Phase.Confirming or ticket!=0:return false
	var ids: Array=[]
	for row in _preview.units:ids.append(row.id)
	var owner:=generation
	var target:=unit_id
	phase=Phase.Applying
	ticket=service.submit("creature_expel",{"action":C.ManagementAction.CreatureExpelApply,"unit_id":target,"destination_id":destination_id,"expected_unit_ids":ids},func(received,result,_request):
		if owner!=generation or received!=ticket:return
		ticket=0
		var outcome: int=result.get("creature_expel",{}).get("outcome",-1)
		if result.get("outcome","")=="unknown" or outcome==C.CreatureExpelOutcome.Unknown:
			_fail(Phase.Unknown);return
		if result.get("action")!=C.ManagementAction.CreatureExpelApply:
			_fail(Phase.Unknown);return
		if result.get("status")==C.ManagementStatus.Ok and outcome==C.CreatureExpelOutcome.Applied:
			_preview={};phase=Phase.Completed;changed.emit();applied.emit(target);return
		# A malformed success is uncertain, never authority to send again.
		_fail(Phase.Rejected if result.get("status")==C.ManagementStatus.Rejected else Phase.Unknown))
	if ticket==0:_fail(Phase.Unavailable);return false
	changed.emit();return true
func _valid(value: Dictionary) -> bool:
	# Wire validation owns row/artwork bounds. The observer additionally binds
	# the receipt to its selected target and protects local confirmation authority.
	if value.get("unit_id",-1)!=unit_id or typeof(value.get("eligible"))!=TYPE_BOOL or typeof(value.get("reason"))!=TYPE_INT or typeof(value.get("units"))!=TYPE_ARRAY or typeof(value.get("destinations"))!=TYPE_ARRAY:return false
	var previous: int=-1
	var selected:=false
	for row in value.units:
		if not row is Dictionary or typeof(row.get("id"))!=TYPE_INT or row.id<=previous:return false
		previous=row.id;selected=selected or row.id==unit_id
	if value.eligible and value.reason==-1 and not selected:return false
	return true
func _fail(next: Phase) -> void:
	_preview={};destination_id=-1;phase=next;changed.emit()
func _invalidated() -> void:
	close();phase=Phase.Unavailable;changed.emit()
