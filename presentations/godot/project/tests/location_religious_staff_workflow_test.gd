extends SceneTree
const Model=preload("res://scripts/location_religious_staff_workflow.gd")
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
func reply(world,service,facts: Dictionary,outcome:=0) -> void:
	var sent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,
		"area":{"operation":sent.operation,"location_edit_outcome":outcome,"location_religious_staff":facts}}
	service.poll()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world=World.new();var service=Service.new();service.configure(world)
	var details=Details.new();details.service=service
	var row={"source":1,"entity_id":383,"assignment_id":2,"histfig_id":9375}
	details.snapshot.staff={"rows":[row]}
	var workflow=Model.new();workflow.configure(details)
	var facts={"site_id":651,"location_id":0,"entity_id":383,"assignment_id":2,"position_id":0,"holder_id":9375,"unit_id":5813,"revision":9007199254740993,"removable":true}
	var vacant=facts.duplicate(true);vacant.holder_id=-1;vacant.unit_id=-1;vacant.removable=false;vacant.revision+=1
	workflow.remove(row);workflow.remove(row);service.poll()
	check(world.calls.size()==1 and details.phase==Details.Phase.Editing,"gesture locks Details and reads once")
	reply(world,service,facts);service.poll()
	check(world.calls.size()==2 and world.calls[-1].request.expected_revision==9007199254740993 and world.calls[-1].request.religious_holder_id==9375,"fresh native revision and displayed holder bind removal")
	workflow.remove(row);service.poll();check(world.calls.size()==2,"pending removal cannot duplicate")
	reply(world,service,vacant,C.LocationEditOutcome.Completed)
	check(details.refreshes==1 and details.phase==Details.Phase.Refreshing and not workflow.active,"confirmed removal refreshes Details")
	for outcome in [C.LocationEditOutcome.Rejected,C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown]:
		details.phase=Details.Phase.Ready;details.snapshot.revision+=1;details.changed.emit()
		workflow.remove(row);service.poll();reply(world,service,facts);service.poll()
		var count: int=world.calls.size();reply(world,service,{},outcome)
		workflow.remove(row);service.poll()
		check(world.calls.size()==count and not workflow.active and details.phase==Details.Phase.Ready,"refused/unknown mutation does not replay")
	details.snapshot.revision+=1;details.changed.emit()
	workflow.remove(row);service.poll()
	var changed=facts.duplicate(true);changed.holder_id=99
	var count: int=world.calls.size();reply(world,service,changed);service.poll()
	check(workflow.phase==Model.Phase.Stale and world.calls.size()==count,"new holder cannot inherit old gesture")
	details.snapshot.revision+=1;details.changed.emit()
	workflow.remove(row);details.generation+=1;details.phase=Details.Phase.Closed;details.changed.emit();service.poll()
	check(world.calls.size()==count and not workflow.active,"closing cancels queued read")
	details.phase=Details.Phase.Ready;details.changed.emit();workflow.remove(row);service.poll();reply(world,service,facts)
	# The read succeeded but the mutation has not been sent yet.
	details.generation+=1;details.phase=Details.Phase.Closed;details.changed.emit();count=world.calls.size();service.poll()
	check(world.calls.size()==count and not workflow.active,"closing cancels queued mutation")
	details.phase=Details.Phase.Ready;details.changed.emit();workflow.remove(row);service.poll();reply(world,service,facts);service.poll()
	details.generation+=1;details.identity={"site_id":651,"id":7};details.snapshot.revision+=1;details.phase=Details.Phase.Ready;details.changed.emit()
	reply(world,service,vacant,C.LocationEditOutcome.Completed)
	check(details.refreshes==1 and not workflow.active and details.identity.id==7,"late success cannot refresh replacement owner")
	details.identity.id=0;details.generation+=1;details.changed.emit();workflow.remove(row);service.poll();reply(world,service,facts);service.poll()
	count=world.calls.size();world.state={"world_epoch":6,"revision":1,"status":0};service.poll()
	check(workflow.phase==Model.Phase.Unavailable and not workflow.active,"session change retires action")
	service.poll();check(world.calls.size()==count,"session change never replays")
	workflow.dispose();service.free()
	var view=preload("res://scripts/location_staff_view.gd").new();root.add_child(view)
	view.size=Vector2(576,636);view.display({"site_id":651,"id":0,"kind":2,"staff":{"rows":[row]}})
	var gestures: Array=[];view.religious_removal_requested.connect(func(value):gestures.append(value))
	var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=Vector2((view.row_columns()-4)*8+2,(int(view.geometry.first_y)-6)*12+2)
	view._gui_input(click);check(gestures.is_empty(),"disabled staff ignores remove click")
	view.actions_enabled=true;view._gui_input(click)
	check(gestures==[row],"occupied religious remove hitbox carries exact row")
	gestures[0].histfig_id=99;check(view.rows[0].histfig_id==9375,"gesture owns its row copy")
	var empty=row.duplicate(true);empty.histfig_id=-1
	view.display({"site_id":651,"id":0,"kind":2,"staff":{"rows":[empty]}})
	view._gui_input(click);click.position.x=194;view._gui_input(click)
	check(gestures.size()==1,"vacant religious row never submits removal")
	view.queue_free()

	if failures==0:print("LOCATION_RELIGIOUS_STAFF_WORKFLOW_PASS")
	quit(1 if failures else 0)
