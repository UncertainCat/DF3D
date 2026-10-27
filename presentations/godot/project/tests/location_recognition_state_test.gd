extends SceneTree
const Model=preload("res://scripts/location_recognition_state.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const C=preload("res://scripts/management_contract.gd")
var failures:=0
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
class Details:
	extends RefCounted
	signal changed
	enum Phase { Closed, Ready, Editing, Refreshing }
	var phase:=Phase.Ready
	var generation:=1
	var identity: Dictionary={"site_id":651,"id":0}
	var snapshot: Dictionary={"kind":2,"revision":11}
	var service
	var refreshes:=0
	func refresh():
		refreshes+=1;phase=Phase.Refreshing;changed.emit()
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func reply(world,service,snapshot: Dictionary,outcome:=0) -> void:
	var sent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,
		"area":{"operation":sent.operation,"location_edit_outcome":outcome,"location_recognition":snapshot}}
	service.poll()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world=World.new();var service=Service.new();service.configure(world)
	var model=Model.new();model.configure(service)
	var applied: Array=[];model.applied.connect(func():applied.append(true))
	var target={"site_id":651,"id":0}
	var facts={"site_id":651,"location_id":0,"religion_id":383,"revision":9007199254740993,"state":5,"continuing_agreements":[41]}
	model.open(target);service.poll();reply(world,service,facts)
	check(model.phase==Model.Phase.Ready and model.snapshot==facts,"read publishes exact receipt")
	facts.continuing_agreements.append(42);check(model.snapshot.continuing_agreements==[41],"snapshot owns nested data")
	model.recognize();model.recognize();model.refresh();service.poll()
	check(world.calls.size()==2 and world.calls[-1].request.expected_revision==9007199254740993,"apply sends exact revision once")
	check(model.phase==Model.Phase.Applying and model.snapshot.state==5,"pending apply preserves old display")
	var complete=facts.duplicate(true);complete.revision+=1;complete.state=0
	reply(world,service,complete,C.LocationEditOutcome.Completed)
	check(model.phase==Model.Phase.Ready and model.snapshot==complete and applied.size()==1,"only confirmed apply emits completion")
	model.recognize();service.poll();check(world.calls.size()==2,"completed control cannot submit")
	for outcome in [C.LocationEditOutcome.Rejected,C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown]:
		model.open(target);service.poll();reply(world,service,facts)
		model.recognize();service.poll();var previous: int=world.calls.size()
		reply(world,service,{},outcome)
		var expected=Model.Phase.Unknown if outcome==C.LocationEditOutcome.Unknown else Model.Phase.Stale if outcome==C.LocationEditOutcome.Stale else Model.Phase.Rejected
		model.recognize();model.refresh();service.poll()
		check(model.phase==expected and model.snapshot.is_empty() and world.calls.size()==previous,"failed action cannot retry")
	model.open(target);service.poll();reply(world,service,facts)
	var previous: int=world.calls.size();model.recognize();model.close();service.poll()
	check(world.calls.size()==previous,"close cancels unsent action")
	model.open(target);service.poll();reply(world,service,facts)
	model.recognize();service.poll();model.close();model.open({"site_id":651,"id":7})
	reply(world,service,complete,C.LocationEditOutcome.Completed)
	check(model.phase==Model.Phase.Reading and model.snapshot.is_empty() and applied.size()==1,"late success cannot revive old target")
	var replacement=facts.duplicate(true);replacement.location_id=7
	reply(world,service,replacement);check(model.snapshot.location_id==7,"replacement receives its own observation")
	model.recognize();service.poll();previous=world.calls.size()
	world.state={"world_epoch":6,"revision":1,"status":0};service.poll()
	check(model.phase==Model.Phase.Unavailable and model.snapshot.is_empty(),"epoch change retires pending owner")
	model.recognize();service.poll();check(world.calls.size()==previous,"epoch change never replays apply")
	model.dispose();model.configure(service);world.state={"world_epoch":5,"revision":1,"status":0};service.poll()
	model.open(target);service.poll();reply(world,service,facts);model.recognize();service.poll()
	var malformed=complete.duplicate(true);malformed.location_id=99
	reply(world,service,malformed,C.LocationEditOutcome.Completed)
	check(model.phase==Model.Phase.Unknown and model.snapshot.is_empty() and applied.size()==1,"malformed successful mutation is unknown")
	model.dispose()
	var details=Details.new();details.service=service
	var workflow=preload("res://scripts/location_recognition_workflow.gd").new();workflow.configure(details)
	service.poll();reply(world,service,facts)
	workflow.recognize();service.poll()
	check(details.phase==Details.Phase.Editing,"recognition excludes concurrent Details edits")
	reply(world,service,complete,C.LocationEditOutcome.Completed)
	check(details.refreshes==1 and details.phase==Details.Phase.Refreshing,"confirmed recognition refreshes staff and Details")
	details.snapshot.revision=12;details.phase=Details.Phase.Ready;details.changed.emit();service.poll();reply(world,service,facts)
	workflow.recognize();service.poll();previous=world.calls.size()
	reply(world,service,{},C.LocationEditOutcome.Unknown)
	check(details.phase==Details.Phase.Ready and workflow.recognition.phase==Model.Phase.Unknown,"unknown releases unrelated controls without retry")
	workflow.recognize();service.poll();check(world.calls.size()==previous,"unknown workflow does not replay")
	details.snapshot.revision=13;details.changed.emit();service.poll();reply(world,service,facts)
	workflow.recognize();service.poll()
	details.generation+=1;details.identity={};details.snapshot={};details.phase=Details.Phase.Closed;details.changed.emit()
	reply(world,service,complete,C.LocationEditOutcome.Completed)
	check(details.phase==Details.Phase.Closed and details.refreshes==1,"late success cannot refresh closed Details")
	workflow.dispose();service.free()
	if failures==0:print("LOCATION_RECOGNITION_STATE_PASS")
	quit(1 if failures else 0)
