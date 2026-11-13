extends RefCounted
# Staged workshop Tasks controller. DF owns choices, captions and queue effects.
# Choices and category keys come from DF; this controller never derives them.
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
var query:=""
var category:=""
var parent: Variant=null

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
	building_id=-1;snapshot={};query="";category="";parent=null;phase=Phase.Closed;changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	building_id=id;refresh()

func refresh() -> void:
	if building_id<0 or ticket!=0:return
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_id":building_id,"query":query,"task_category":category})

func reset_picker() -> void:
	if phase not in [Phase.Ready,Phase.Reading]:return
	if category.is_empty() and query.is_empty():return
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	category="";query="";parent=null;refresh()

func go_back() -> void:
	if phase!=Phase.Ready or ticket!=0 or parent==null:return
	generation+=1;category=parent;query="";refresh()

func open_category(key: String) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	for row in snapshot.get("task_categories",[]):
		if row.key==key:
			generation+=1;category=key;query="";refresh();return

func choices() -> Array:
	var rows: Array=[]
	for value in snapshot.get("task_categories",[]):
		var row: Dictionary=value.duplicate(true);row["category_choice"]=true;rows.append(row)
	rows.append_array(recipes());return rows

func set_query(value: String) -> void:
	if value==query or building_id<0 or phase not in [Phase.Ready,Phase.Reading]:return
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	query=value;refresh()

func jobs() -> Array:
	return snapshot.get("jobs",[]).duplicate(true)

func recipes() -> Array:
	return snapshot.get("recipes",[]).duplicate(true)

func queue_task(key: String) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for recipe in snapshot.recipes:
		if recipe.key==key:
			if recipe.has("availability") and not recipe.availability.available:return
			found=true;break
	if not found:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.ProductionQueue,"building_id":building_id,"recipe":key,"task_category":category})

func move_up(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var rows: Array=snapshot.get("jobs",[])
	for index in range(1,rows.size()):
		if rows[index].id==id and rows[index].get("can_move_up",false):
			_edit(id,{"expected_previous_job_id":rows[index-1].id});return

func cancel_task(id: int) -> void:
	_edit(id,{"cancel":true})

func set_repeat(id: int, desired: bool) -> void:
	_edit(id,{"repeat":int(desired)})

func toggle_priority(id: int) -> void:
	if phase!=Phase.Ready:return
	for job in snapshot.get("jobs",[]):
		if job.id==id and job.has("priority"):
			_edit(id,{"priority":int(not job.priority),"expected_priority":int(job.priority)});return

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
	# The legacy production reply does not distinguish pre-write rejection from
	# an error after native worker release. Never retry an uncertain Priority edit.
	if result.get("status",-1)!=C.ManagementStatus.Ok:_fail(Phase.Unknown if sent.has("priority") or sent.has("expected_previous_job_id") else Phase.Rejected);return
	var data: Dictionary=result.get("production",{})
	var expected_category: String=sent.get("task_category","")
	if data.get("task_category","")!=expected_category or (not expected_category.is_empty() and not data.has("task_category")):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
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
		elif selected.is_empty() or (sent.has("repeat") and selected.get("repeat")!=bool(sent.repeat)) or (sent.has("suspend") and selected.get("suspended")!=bool(sent.suspend)) or (sent.has("priority") and (selected.get("priority")!=bool(sent.priority) or (sent.priority==1 and data.jobs[0].id!=sent.job_id))):
			_fail(Phase.Unknown);return
	if sent.has("expected_previous_job_id"):
		var expected: Array=snapshot.get("jobs",[]).map(func(row):return row.id)
		var index:=expected.find(sent.job_id)
		if index<=0 or expected[index-1]!=sent.expected_previous_job_id:_fail(Phase.Unknown);return
		expected[index]=sent.expected_previous_job_id;expected[index-1]=sent.job_id
		if data.jobs.map(func(row):return row.id)!=expected:_fail(Phase.Unknown);return
	category=expected_category;parent=data.get("task_parent",null);snapshot=data.duplicate(true);phase=Phase.Ready;changed.emit()
	if editing:applied.emit()
