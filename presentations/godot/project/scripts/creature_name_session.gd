extends Node
# Service-owned explicit typing survives panel closure. Revisions come only
# from confirmed receipts; buffered text is discarded on an uncertain outcome.
signal changed(snapshot: Dictionary)
signal finished
signal failed(result: Dictionary)
const C=preload("res://scripts/management_contract.gd")
var service
var snapshot: Dictionary={}
var pending: Array[Dictionary]=[]
var ticket:=0
var ending:=false
var stopped:=false
var receiving:=false
var unit_id: int=-1

static func valid_snapshot(value: Dictionary,id: int) -> bool:
	for key in ["unit_id","historical_figure_id","revision"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.unit_id!=id or id<0 or id>2147483647 or value.revision<=0 or value.historical_figure_id < -1:return false
	if typeof(value.get("has_figure"))!=TYPE_BOOL or (value.has_figure and value.historical_figure_id<0):return false
	for key in ["nickname","profession","figure_nickname"]:
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>1536:return false
	return value.has_figure or value.figure_nickname.is_empty()

func configure(source,observed: Dictionary) -> void:
	service=source
	if service==null or typeof(observed.get("unit_id"))!=TYPE_INT:_fail({});return
	unit_id=observed.unit_id
	if not valid_snapshot(observed,unit_id):_fail({});return
	snapshot=observed.duplicate(true);service.session_changed.connect(_invalidated)

func edit(profession: bool,value: String) -> bool:
	var bytes:=value.to_utf8_buffer()
	if stopped or ending or bytes.size()>90 or bytes.has(0):return false
	var intent: Dictionary={"profession":profession,"name":value}
	if not pending.is_empty() and pending[-1].profession==profession:pending[-1]=intent
	else:pending.append(intent)
	_drain();return true

func finish() -> void:
	if stopped:return
	ending=true;_drain()

func _drain(previous:=0) -> void:
	if stopped or receiving or ticket!=0:return
	while not pending.is_empty():
		var intent: Dictionary=pending.pop_front()
		if intent.name==snapshot["profession" if intent.profession else "nickname"]:continue
		intent.merge({"action":C.ManagementAction.CreatureHeaderEdit,"unit_id":unit_id,"expected_revision":snapshot.revision})
		ticket=service.submit_continuation(previous,"creature_header",intent,_received) if previous>0 else service.submit("creature_header",intent,_received)
		if ticket==0:_fail({})
		return
	if ending:_stop();finished.emit();queue_free()

func _received(receipt: int,result: Dictionary,request: Dictionary) -> void:
	if stopped or receipt!=ticket:return
	ticket=0
	var header: Dictionary=result.get("creature_header",{})
	if result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or header.get("outcome")!=C.CreatureHeaderOutcome.Completed:
		_fail(result);return
	var observed: Dictionary=header.get("snapshot",{})
	var correct: bool=result.get("action")==C.ManagementAction.CreatureHeaderEdit and valid_snapshot(observed,unit_id)
	if correct:
		var expected:=snapshot.duplicate(true)
		expected["profession" if request.profession else "nickname"]=request.name
		if not request.profession and expected.has_figure:expected.figure_nickname=request.name
		for key in ["unit_id","historical_figure_id","has_figure","nickname","profession","figure_nickname"]:
			if observed[key]!=expected[key]:correct=false
	if not correct:
		var uncertain:=result.duplicate(true);uncertain.outcome="unknown";_fail(uncertain);return
	snapshot=observed.duplicate(true)
	receiving=true;changed.emit(snapshot.duplicate(true));receiving=false
	_drain(receipt)

func _invalidated() -> void:_fail({"outcome":"unknown"})
func _stop() -> void:
	stopped=true
	if service!=null:
		if service.session_changed.is_connected(_invalidated):service.session_changed.disconnect(_invalidated)
		if ticket!=0:service.detach(ticket)
	ticket=0
func _fail(result: Dictionary) -> void:
	if stopped:return
	_stop();pending.clear();snapshot={};failed.emit(result.duplicate(true));queue_free()
func _exit_tree() -> void:_stop()
