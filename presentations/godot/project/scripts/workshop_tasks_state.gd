extends RefCounted
# Staged workshop Tasks controller. DF owns choices, captions and queue effects.
# The legacy recipe payload lacks category/availability facts; the public picker
# must wait for the native catalog contract rather than infer those in Godot.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;snapshot={};phase=Phase.Closed;changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	building_id=id;refresh()

func refresh() -> void:
	if building_id<0 or ticket!=0:return
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_id":building_id})

func jobs() -> Array:
	return snapshot.get("jobs",[]).duplicate(true)

func recipes() -> Array:
	return snapshot.get("recipes",[]).duplicate(true)

func queue_task(key: String) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for recipe in snapshot.recipes:
		if recipe.key==key:found=true;break
	if not found:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.ProductionQueue,"building_id":building_id,"recipe":key})

func cancel_task(id: int) -> void:
	_edit(id,{"cancel":true})

func set_repeat(id: int, desired: bool) -> void:
	_edit(id,{"repeat":int(desired)})

func set_suspended(id: int, desired: bool) -> void:
	_edit(id,{"suspend":int(desired)})

func _edit(id: int, fields: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for job in snapshot.jobs:
		if job.id==id and job.editable:found=true;break
	if not found:return
	var intent: Dictionary={"action":C.ManagementAction.ProductionJobEdit,"building_id":building_id,"job_id":id}
	intent.merge(fields);phase=Phase.Applying;_send(intent)

func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	snapshot={};phase=next;changed.emit()

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action!=C.ManagementAction.ProductionInspect
	if result.get("outcome","")=="unknown":_fail(Phase.Unknown);return
	if result.get("status",-1)!=C.ManagementStatus.Ok:_fail(Phase.Rejected);return
	var data: Dictionary=result.get("production",{})
	if result.get("action",-1)!=sent.action or data.get("selected_building",-1)!=building_id or not data.get("jobs") is Array or not data.get("recipes") is Array:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	# A successful transport reply is insufficient: confirm the requested effect
	# in DF's returned queue. Unknown effects are never replayed automatically.
	if sent.action==C.ManagementAction.ProductionQueue:
		var created: int=data.get("created_job",-1)
		var found:=false
		for job in data.jobs:
			if job.id==created and created>=0:found=true;break
		for job in snapshot.get("jobs",[]):
			if job.id==created:found=false;break
		if not found:_fail(Phase.Unknown);return
	elif sent.action==C.ManagementAction.ProductionJobEdit:
		var selected: Dictionary={}
		for job in data.jobs:
			if job.id==sent.job_id:selected=job;break
		if sent.get("cancel",false):
			if not selected.is_empty():_fail(Phase.Unknown);return
		elif selected.is_empty() or (sent.has("repeat") and selected.get("repeat")!=bool(sent.repeat)) or (sent.has("suspend") and selected.get("suspended")!=bool(sent.suspend)):
			_fail(Phase.Unknown);return
	snapshot=data.duplicate(true);phase=Phase.Ready;changed.emit()
	if editing:applied.emit()
