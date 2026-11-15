extends RefCounted
# Owns Link targeting and receipts; native menu state is never an input.
signal changed
signal applied(operation: int,job_id: int)
signal mechanisms_unavailable
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Targeting, Previewing, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var target: Dictionary={}
var tile:=Vector3i(-1,-1,-1)
var ticket:=0
var generation:=0
var pending_link:=false

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();building_id=-1;snapshot={};target={};tile=Vector3i(-1,-1,-1);pending_link=false;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func _fail(next: Phase) -> void:
	_retire();target={};pending_link=false;phase=next;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	building_id=id;_initial(false)
func _initial(linking: bool) -> void:
	if service==null:_fail(Phase.Unavailable);return
	pending_link=linking;phase=Phase.Reading
	_send(0,{},linking)
func begin_link() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	# Re-run native selection at the actual Link click, not from panel-open stock.
	_initial(true)
func cancel_link() -> void:
	if phase not in [Phase.Targeting,Phase.Previewing] and not (phase==Phase.Reading and pending_link):return
	_retire();target={};tile=Vector3i(-1,-1,-1);pending_link=false;phase=Phase.Ready;changed.emit()
func preview(position: Vector3i) -> void:
	if phase not in [Phase.Targeting,Phase.Previewing] or position==tile:return
	_retire();tile=position;target={};phase=Phase.Targeting
	if position.x<0 or position.y<0 or position.z<0 or position.x>32767 or position.y>32767 or position.z>32767:changed.emit();return
	phase=Phase.Previewing;_send(1,_selection())
func _selection() -> Dictionary:
	return {"lever_x":tile.x,"lever_y":tile.y,"lever_z":tile.z,
		"lever_source_mechanism":snapshot.source_mechanism,"lever_target_mechanism":snapshot.target_mechanism}
func link() -> void:
	if phase!=Phase.Targeting or ticket!=0 or target.get("target_id",-1)<0:return
	var intent:=_selection();intent.lever_target_id=target.target_id
	phase=Phase.Applying;_send(3,intent)
func pull() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	phase=Phase.Applying;_send(2)

static func valid(value: Dictionary,id: int,op: int) -> bool:
	for key in ["building_id","revision","operation","outcome","source_mechanism","target_mechanism","target_id","job_id"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.building_id!=id or value.revision<=0 or value.operation!=op:return false
	if typeof(value.get("source_name"))!=TYPE_STRING or typeof(value.get("target_name"))!=TYPE_STRING:return false
	if value.source_name.to_utf8_buffer().size()>2048 or value.target_name.to_utf8_buffer().size()>2048:return false
	if value.source_mechanism < -1 or value.target_mechanism < -1 or value.target_id < -1 or value.job_id < -1:return false
	if value.source_mechanism<0 and value.target_mechanism>=0:return false
	if value.source_mechanism>=0 and value.source_mechanism==value.target_mechanism:return false
	if op<2:return value.outcome==0 and value.job_id==-1 and (op!=0 or value.target_id==-1)
	return value.outcome in [1,2] and ((value.outcome==1 and value.job_id>=0) or (value.outcome==2 and value.job_id==-1))

func _send(op: int,extra: Dictionary={},linking: bool=false) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.ProductionQueue if op>=2 else C.ManagementAction.ProductionInspect,
		"building_id":building_id,"lever_operation":op,"expected_revision":snapshot.get("revision",0) if op!=0 else 0}
	intent.merge(extra)
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("outcome","")=="unknown":_fail(Phase.Unknown if op>=2 else Phase.Rejected);return
		var value: Dictionary=result.get("production",{}).get("lever",{})
		if result.get("status",-1)==C.ManagementStatus.Rejected:_fail(Phase.Rejected);return
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=sent.action or not valid(value,building_id,op):
			_fail(Phase.Unknown if op>=2 else Phase.Rejected);return
		if op==1 or op==3:
			if value.source_mechanism!=sent.lever_source_mechanism or value.target_mechanism!=sent.lever_target_mechanism:
				_fail(Phase.Unknown if op==3 else Phase.Rejected);return
		if op==1:
			if value.revision!=sent.expected_revision:_fail(Phase.Rejected);return
			target=value.duplicate(true);phase=Phase.Targeting
		elif op==0:
			pending_link=false
			snapshot=value.duplicate(true);target={};tile=Vector3i(-1,-1,-1)
			phase=Phase.Targeting if linking and value.target_mechanism>=0 else Phase.Ready
			if linking and phase==Phase.Ready:mechanisms_unavailable.emit()
		else:
			if value.outcome!=1:_fail(Phase.Rejected);return
			if (op==3 and value.target_id!=sent.lever_target_id) or (op==2 and value.target_id!=-1):_fail(Phase.Unknown);return
			snapshot=value.duplicate(true);target={};tile=Vector3i(-1,-1,-1);phase=Phase.Ready
			applied.emit(op,value.job_id)
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
