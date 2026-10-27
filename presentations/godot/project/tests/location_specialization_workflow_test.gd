extends SceneTree
const Model=preload("res://scripts/location_specialization_workflow.gd")
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
	func refresh():refreshes+=1;phase=Phase.Refreshing;changed.emit()
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func fresh(details) -> void:
	details.generation+=1;details.phase=Details.Phase.Ready;details.changed.emit()
func reply(world,service,facts: Dictionary,outcome:=0) -> void:
	var sent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,
		"area":{"operation":sent.operation,"location_edit_outcome":outcome,"location_specialization":facts}}
	service.poll()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for source in [0,1]:
		var world=World.new();var service=Service.new();service.configure(world)
		var details=Details.new();details.service=service
		var row: Dictionary={"source":source,"occupation_id":87 if source==0 else -1,"entity_id":383 if source==1 else -1,
			"assignment_id":2 if source==1 else -1,"histfig_id":9375,"names":{"holder_kind":1,"holder_id":5813}}
		details.snapshot.staff={"rows":[row]}
		var workflow=Model.new();workflow.configure(details)
		var facts: Dictionary=Model.row_target(row)
		facts.merge({"site_id":651,"location_id":0,"revision":9007199254740993,"eligible":true,"specialized":false})
		var changed:=facts.duplicate(true);changed.specialized=true;changed.revision+=2
		var invalid_row:=row.duplicate(true);invalid_row.names.holder_id=99
		workflow.toggle(invalid_row,facts)
		var invalid_display:=facts.duplicate(true);invalid_display.unit_id=99
		workflow.toggle(row,invalid_display);service.poll()
		check(world.calls.is_empty(),"foreign row or displayed unit cannot start a gesture")
		var cancel_read: Callable=func():
			if details.phase==Details.Phase.Editing:workflow.close()
		details.changed.connect(cancel_read);workflow.toggle(row,facts);details.changed.disconnect(cancel_read);service.poll()
		check(world.calls.is_empty() and not workflow.active,"synchronous owner cancellation prevents receipt dispatch")
		workflow.toggle(row,facts);workflow.toggle(row,facts);service.poll()
		check(world.calls.size()==1 and details.phase==Details.Phase.Editing,"one fresh read locks Details")
		var newer:=facts.duplicate(true);newer.revision+=1
		reply(world,service,newer);service.poll()
		check(world.calls.size()==2 and world.calls[-1].request.expected_revision==newer.revision and world.calls[-1].request.value==1,"fresh wide receipt authorizes explicit opposite state")
		workflow.toggle(row,facts);service.poll();check(world.calls.size()==2,"duplicate pending gesture refused")
		reply(world,service,changed,C.LocationEditOutcome.Completed)
		check(details.refreshes==1 and not workflow.active and details.phase==Details.Phase.Refreshing,"verified effect refreshes Details")
		# The reverse gesture sends an explicit zero, never a server-side toggle.
		fresh(details);workflow.toggle(row,changed);service.poll();reply(world,service,changed);service.poll()
		check(world.calls[-1].request.value==0,"reverse request preserves zero")
		reply(world,service,facts,C.LocationEditOutcome.Completed)
		check(details.refreshes==2,"reverse completed")
		for field in ["specialized","eligible","unit_id","histfig_id","location_id","revision"]:
			fresh(details);workflow.toggle(row,facts);service.poll();var count: int=world.calls.size()
			var bad:=facts.duplicate(true)
			if field=="specialized":bad[field]=true
			elif field=="eligible":bad[field]=false
			elif field=="location_id":bad[field]=99
			else:bad[field]=0
			reply(world,service,bad);service.poll()
			check(not workflow.active and world.calls.size()==count,"invalid/changed read cannot authorize edit: "+field)
			workflow.toggle(row,facts);service.poll();check(world.calls.size()==count,"failed read cannot auto-retry same owner")
		for outcome in [C.LocationEditOutcome.Rejected,C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown]:
			fresh(details);workflow.toggle(row,facts);service.poll();reply(world,service,facts);service.poll()
			var count: int=world.calls.size();reply(world,service,{},outcome)
			workflow.toggle(row,facts);service.poll();check(world.calls.size()==count and not workflow.active,"refused/uncertain edit never replays")
		fresh(details);workflow.toggle(row,facts);service.poll();reply(world,service,facts);service.poll()
		reply(world,service,facts,C.LocationEditOutcome.Completed)
		check(workflow.phase==Model.Phase.Unknown and details.refreshes==2,"success with unchanged value is unknown")
		# Both queued read and read-in-flight closure must prevent mutation.
		for sent in [false,true]:
			fresh(details);workflow.toggle(row,facts)
			if sent:service.poll()
			var count: int=world.calls.size();workflow.close()
			if sent:reply(world,service,facts)
			service.poll();check(world.calls.size()==count and not workflow.active and details.phase==Details.Phase.Ready,"read closure retires and unlocks")
		# At the receipt boundary the edit is queued, but may already be sent on a later poll.
		for sent in [false,true]:
			fresh(details);workflow.toggle(row,facts);service.poll()
			var close_queued: Callable=func():
				if workflow.phase==Model.Phase.Applying and workflow.ticket>0:workflow.close()
			if not sent:workflow.changed.connect(close_queued)
			reply(world,service,facts)
			if not sent:workflow.changed.disconnect(close_queued)
			var count: int=world.calls.size()
			if sent:workflow.close()
			workflow.toggle(row,facts)
			if sent:reply(world,service,changed,C.LocationEditOutcome.Completed)
			service.poll();check(world.calls.size()==count and not workflow.active and details.refreshes==2,"closed edit never revives or duplicates")
		fresh(details);workflow.toggle(row,facts);service.poll();reply(world,service,facts);service.poll()
		details.identity.id=7;fresh(details);reply(world,service,changed,C.LocationEditOutcome.Completed)
		check(details.identity.id==7 and details.refreshes==2 and not workflow.active,"late success cannot refresh replacement location")
		details.identity.id=0;fresh(details);workflow.toggle(row,facts);service.poll();reply(world,service,facts);service.poll()
		var count: int=world.calls.size();world.state={"world_epoch":6,"revision":1,"status":0};service.poll();service.poll()
		check(workflow.phase==Model.Phase.Unavailable and workflow.target.is_empty() and world.calls.size()==count,"epoch change clears ownership without replay")
		workflow.dispose();service.free()
	if failures==0:print("LOCATION_SPECIALIZATION_WORKFLOW_PASS")
	quit(1 if failures else 0)
