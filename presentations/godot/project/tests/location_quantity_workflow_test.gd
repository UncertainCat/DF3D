extends SceneTree
const Model=preload("res://scripts/location_details_state.gd")
const Workflow=preload("res://scripts/location_quantity_workflow.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const C=preload("res://scripts/management_contract.gd")
var failures:=0
var world
var service
var model
var workflow
var facts: Dictionary={"site_id":651,"id":2,"kind":5,"revision":9007199254740993,"supplies":[{"kind":4,"desired":30001}]}
class World:
	extends RefCounted
	var state: Dictionary={"world_epoch":5,"revision":1,"status":0}
	var calls: Array=[]
	func reconnect_management():pass
	func session_generation():return 1
	func is_live():return true
	func last_error():return ""
	func poll_management():return state.duplicate(true)
	func management_request(domain,request):
		calls.append({"domain":domain,"request":request.duplicate(true)})
		return calls.size()
func check(ok: bool, reason: String) -> void:
	if not ok:failures+=1;push_error(reason)
func reply(outcome:=0,details: Dictionary=facts) -> void:
	var intent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":intent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,
		"area":{"operation":intent.operation,"location_details":details}}
	world.state.area["location_edit_outcome" if intent.operation==C.AreaOperation.LocationQuantity else "location_entry_outcome"]=outcome
	service.poll()
func ready() -> void:
	model.open({"site_id":651,"id":2});service.poll();reply();reply(1)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	world=World.new();service=Service.new();service.configure(world)
	model=Model.new();model.configure(service);workflow=Workflow.new();workflow.configure(model)
	ready()
	var before: int=world.calls.size()
	for bad in [[-1,0,1],[11,0,1],[4,3,0],[4,0,-1],[4,0,1000],[4,1,1]]:model.edit_quantity(bad[0],bad[1],bad[2]);service.poll()
	check(world.calls.size()==before,"malformed local quantities cannot send")
	workflow.begin(4);workflow.type_text("-abc")
	check(workflow.text=="" and world.calls.size()==before and model.snapshot==facts,"empty/invalid draft leaves native value untouched")
	workflow.type_text("1");service.poll()
	check(world.calls[-1].request.quantity_value==1 and world.calls[-1].request.expected_revision==facts.revision,"first digit sends exact receipt")
	workflow.type_text("12");workflow.type_text("1234");workflow.type_text("123")
	check(workflow.queue.size()==1 and workflow.queue[0].value==123 and workflow.text=="123","only latest consecutive unsent text survives")
	workflow.step(4,C.LocationQuantityMode.Increase)
	check(workflow.editing==4 and workflow.text=="123","native step preserves current numeric draft")
	workflow.type_text("5")
	check(workflow.queue.size()==3,"step separates Sets and retains order")
	workflow.finish()
	check(workflow.editing==-1 and workflow.queue.size()==3 and model.snapshot==facts,"Enter does not cancel typed values or optimistically mutate facts")
	facts.revision+=1;reply(1)
	check(world.calls[-1].request.quantity_value==123 and world.calls[-1].request.expected_revision==facts.revision,"next explicit value uses confirmed new receipt")
	facts.revision+=1;reply(1)
	check(world.calls[-1].request.quantity_mode==C.LocationQuantityMode.Increase and world.calls[-1].request.quantity_value==0,"step remains raw semantic intent")
	facts.revision+=1;reply(1)
	check(world.calls[-1].request.quantity_value==5,"later Set follows step")
	facts.revision+=1;reply(1)
	check(not workflow.pending and workflow.queue.is_empty(),"completed queue retires")
	workflow.begin(4);workflow.type_text("0");service.poll();facts.revision+=1;reply(1)
	before=world.calls.size();workflow.begin(4)
	check(workflow.text=="" and workflow.editing==4 and world.calls.size()==before,"repeated number icon clears only local draft")
	workflow.type_text("0");service.poll();facts.revision+=1;reply(1)
	workflow.type_text("");service.poll()
	check(world.calls[-1].request.quantity_value==0,"backspace to empty requests zero")
	facts.revision+=1;reply(1)
	for outcome in [C.LocationEditOutcome.Stale,C.LocationEditOutcome.Rejected,C.LocationEditOutcome.Unknown]:
		workflow.begin(4);workflow.type_text("7");service.poll();workflow.type_text("8")
		before=world.calls.size();reply(outcome,{})
		workflow.type_text("9");workflow.step(4,C.LocationQuantityMode.Decrease);service.poll()
		check(world.calls.size()==before and workflow.editing==-1 and workflow.queue.is_empty() and not workflow.pending,"failed or unknown write discards dependent intents without replay")
		ready()
	workflow.begin(4);workflow.type_text("7");workflow.type_text("8")
	before=world.calls.size();model.close();service.poll()
	check(world.calls.size()==before and workflow.queue.is_empty(),"closing cancels queued unsent work")
	ready();workflow.begin(4);workflow.type_text("7");service.poll();workflow.type_text("8")
	model.close();model.open({"site_id":651,"id":2});before=world.calls.size();reply(1)
	check(model.phase==Model.Phase.ReadingEntry and workflow.queue.is_empty() and world.calls.size()==before+1,"late success cannot revive an old draft")
	reply();reply(1)
	workflow.begin(4);workflow.type_text("7");service.poll();workflow.type_text("8")
	world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
	check(model.phase==Model.Phase.Unavailable and workflow.queue.is_empty() and workflow.editing==-1,"epoch invalidates pending input")
	workflow.dispose();model.close();service.free()
	print("LOCATION_QUANTITY_WORKFLOW_PASS" if failures==0 else "LOCATION_QUANTITY_WORKFLOW_FAIL")
	quit(failures)
