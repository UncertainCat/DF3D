extends RefCounted
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
const Session=preload("res://scripts/creature_name_session.gd")
enum Phase {Closed,Reading,Ready,Editing,Rejected,Stale,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var unit_id: int=-1
var snapshot: Dictionary={}
var generation:=0
var ticket:=0
var name_session

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_invalidated)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_invalidated):service.session_changed.disconnect(_invalidated)
	service=null
func close() -> void:
	generation+=1
	var old=name_session;name_session=null
	if old!=null:old.finish()
	if service!=null and ticket!=0:service.detach(ticket)
	ticket=0;unit_id=-1;snapshot={};phase=Phase.Closed;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	unit_id=id;phase=Phase.Reading
	var owner:=generation
	ticket=service.submit("creature_header",{"action":C.ManagementAction.CreatureHeaderRead,"unit_id":id},func(received,result,_request):
		if owner!=generation or received!=ticket:return
		ticket=0
		var header: Dictionary=result.get("creature_header",{})
		var observed: Dictionary=header.get("snapshot",{})
		if result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=C.ManagementAction.CreatureHeaderRead or header.get("outcome")!=C.CreatureHeaderOutcome.Completed or not Session.valid_snapshot(observed,unit_id):
			_fail(Phase.Rejected);return
		snapshot=observed.duplicate(true);phase=Phase.Ready;changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func begin() -> bool:
	if phase!=Phase.Ready or ticket!=0 or name_session!=null:return false
	var owner:=generation
	var owned=Session.new();service.add_child(owned);owned.configure(service,snapshot)
	if owned.stopped:return false
	name_session=owned;phase=Phase.Editing
	owned.changed.connect(func(observed):
		if owner!=generation or name_session!=owned:return
		snapshot=observed.duplicate(true);changed.emit();applied.emit())
	owned.finished.connect(func():
		if owner!=generation or name_session!=owned:return
		name_session=null;phase=Phase.Ready;changed.emit())
	owned.failed.connect(func(result):
		if owner!=generation or name_session!=owned:return
		name_session=null
		var outcome: int=result.get("creature_header",{}).get("outcome",0)
		_fail(Phase.Unknown if result.get("outcome","")=="unknown" or outcome==C.CreatureHeaderOutcome.Unknown else Phase.Stale if outcome==C.CreatureHeaderOutcome.Stale else Phase.Rejected))
	changed.emit();return true
func edit(profession: bool,value: String) -> bool:
	return name_session!=null and name_session.edit(profession,value)
func finish() -> void:
	if name_session!=null:name_session.finish()
func _invalidated() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()
