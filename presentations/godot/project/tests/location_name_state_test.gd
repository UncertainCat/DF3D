extends SceneTree
const Model=preload("res://scripts/location_name_state.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const C=preload("res://scripts/management_contract.gd")
const Workflow=preload("res://scripts/location_name_workflow.gd")
var failures:=0
var world
var service
var model
var facts: Dictionary={"site_id":651,"id":2,"kind":5,"revision":9007199254740993,
	"native_header":"Synthetic native","english_header":"Synthetic English","value":{}}
var choices: Array=[{"word":0,"part":0,"english":"noun","translated":"native"},
	{"word":0,"part":1,"english":"nouns","translated":"native"}]
class Parent:
	extends RefCounted
	signal changed
	enum Phase { Closed, Ready }
	var phase:=Phase.Ready
	var service
	var generation:=1
	var identity: Dictionary={"site_id":651,"id":2}
	var refreshes:=0
	func refresh():refreshes+=1
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
func reply(area: Dictionary, status: int=C.ManagementStatus.Ok) -> void:
	var intent: Dictionary=world.calls[-1].request
	area.operation=intent.operation
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":intent.action,
		"status":status,"area":area}
	service.poll()
func name_reply(edit:=false) -> void:
	var area: Dictionary={"location_name":facts.duplicate(true)}
	if edit:area.location_edit_outcome=C.LocationEditOutcome.Completed
	reply(area)
func page(batch: Array=choices,total:=2,next:=0) -> void:
	var intent: Dictionary=world.calls[-1].request
	reply({"location_name_page":{"snapshot":facts.duplicate(true),"component":intent.name_query.component,
		"query_bytes":intent.name_query.query_bytes,"cursor":intent.name_query.cursor,"choices":batch,
		"total":total,"next_cursor":next,"truncated":next!=0}})
func ready() -> void:
	model.open({"site_id":651,"id":2});service.poll();name_reply();page()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	world=World.new();service=Service.new();service.configure(world);model=Model.new();model.configure(service)
	ready()
	check(model.phase==Model.Phase.Ready and model.rows==choices,"native order and duplicate word grammar preserved")
	model.choose(1);service.poll()
	check(world.calls[-1].request.name_edit.word==0 and world.calls[-1].request.name_edit.part==1,"selection exact native identity")
	model.clear_component(6);model.random_whole()
	check(model.queue.size()==2 and model.snapshot==facts,"explicit edits queue without optimistic name mutation")
	facts.revision+=1;name_reply(true)
	check(world.calls[-1].request.expected_revision==facts.revision and world.calls[-1].request.name_edit.target==6,"next edit uses confirmed revision")
	facts.revision+=1;name_reply(true)
	check(world.calls[-1].request.name_edit.mode==C.LocationNameMode.RandomWhole,"whole Random retains order")
	facts.revision+=1;name_reply(true);page()
	check(model.phase==Model.Phase.Ready and model.queue.is_empty(),"mutation completion refreshes native choices")
	model.set_choices(6,PackedByteArray([130,255]));service.poll()
	check(world.calls[-1].request.name_query.query_bytes==PackedByteArray([130,255]),"opaque query bytes preserved")
	page([choices[0]],2,1)
	check(model.rows.is_empty() and world.calls[-1].request.name_query.cursor==1,"bounded short page continues without selectable partial rows")
	page([choices[1]],2)
	check(model.rows==choices,"short page concatenation retains forms")
	model.set_choices(0,PackedByteArray());service.poll()
	var old_call: int=world.calls.size()
	model.set_choices(1,PackedByteArray([65]));page()
	check(world.calls.size()==old_call+1 and model.phase==Model.Phase.Loading,"obsolete read cannot apply after filter change")
	page([],0)
	var before: int=world.calls.size();model.random_component(0);service.poll()
	check(world.calls.size()==before and model.phase==Model.Phase.Ready,"empty Random sends nothing")
	model.set_choices(1,PackedByteArray([1,2,3,4,5,6,7,8,9,10,11]));service.poll()
	check(world.calls.size()==before,"query length limit enforced")
	model.clear_component(0);service.poll();model.random_whole()
	reply({"location_edit_outcome":C.LocationEditOutcome.Stale},C.ManagementStatus.Rejected)
	check(model.phase==Model.Phase.Stale and model.queue.is_empty() and model.snapshot.is_empty(),"stale stops all queued work")
	ready();model.random_whole();service.poll();model.clear_component(1)
	service.poll(16.0)
	check(model.phase==Model.Phase.Unknown and model.queue.is_empty(),"timeout never replays mutation")
	name_reply(true)
	check(model.phase==Model.Phase.Unknown,"late success cannot resurrect unknown editor")
	ready();before=world.calls.size();model.clear_component(0);model.close();service.poll()
	check(world.calls.size()==before and model.phase==Model.Phase.Closed,"close cancels unsent edit")
	ready();model.random_whole();service.poll();model.close();facts.revision+=1;name_reply(true)
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty(),"sent edit receipt cannot reopen closed editor")
	var previous=model
	var parent:=Parent.new();parent.service=service
	var workflow:=Workflow.new();workflow.configure(parent);model=workflow.names
	workflow.open();service.poll();name_reply();page()
	model.random_whole();service.poll();facts.revision+=1;name_reply(true);page();workflow.close()
	check(parent.refreshes==1 and not workflow.active,"closing edited name refreshes parent Details")
	workflow.open();service.poll();name_reply();page();model.random_whole();service.poll();workflow.close()
	check(parent.refreshes==2,"closing sent edit schedules parent refresh")
	facts.revision+=1;name_reply(true)
	check(not workflow.active and model.phase==Model.Phase.Closed,"late mutation cannot reactivate workflow")
	workflow.open();service.poll();name_reply();page();parent.generation+=1;parent.identity.id=3;parent.changed.emit()
	check(not workflow.active and model.phase==Model.Phase.Closed and parent.refreshes==2,"parent target change retires without refreshing new target")
	workflow.dispose();model=previous
	ready();model.random_whole();service.poll();world.state.world_epoch=6;service.poll()
	check(model.phase==Model.Phase.Unavailable and model.identity.is_empty(),"epoch retires owner")
	model.dispose();service.free()
	print("LOCATION_NAME_STATE_PASS" if failures==0 else "LOCATION_NAME_STATE_FAILED")
	quit(0 if failures==0 else 1)
