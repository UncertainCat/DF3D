extends SceneTree
const Model = preload("res://scripts/location_details_state.gd")
const Service = preload("res://scripts/semantic_action_service.gd")
const C = preload("res://scripts/management_contract.gd")
var failures := 0
class World:
	extends RefCounted
	var state := {"world_epoch":5,"revision":1,"status":0}
	var calls: Array = []
	func reconnect_management(): pass
	func session_generation(): return 1
	func is_live(): return true
	func last_error(): return ""
	func poll_management(): return state.duplicate(true)
	func management_request(domain,request):
		calls.append({"domain":domain,"request":request.duplicate(true)})
		return calls.size()
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func reply(world,service,details: Dictionary,outcome := 0) -> void:
	var intent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),
		"action":intent.action,"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,
		"area":{"operation":intent.operation,"location_entry_outcome":outcome,"location_details":details}}
	if int(intent.operation) in [C.AreaOperation.LocationAccess,C.AreaOperation.LocationStaffEdit]:
		world.state.area.location_entry_outcome=0;world.state.area.location_edit_outcome=outcome
	service.poll()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world=World.new();var service=Service.new();service.configure(world)
	var model=Model.new();model.configure(service)
	var target={"site_id":651,"id":2};var facts={"site_id":651,"id":2,"kind":5,"revision":9007199254740993,"staff":{"rows":[]}}
	model.open(target);service.poll()
	check(world.calls.size()==1 and world.calls[0].request.operation==C.AreaOperation.LocationDetails,"opening starts with an observational receipt")
	reply(world,service,facts)
	check(world.calls.size()==2 and world.calls[1].request.operation==C.AreaOperation.LocationOpen and world.calls[1].request.expected_revision==facts.revision,"entry uses exact observed receipt once")
	check(model.snapshot.is_empty() and model.phase==Model.Phase.Entering,"unconfirmed entry cannot become ready")
	reply(world,service,facts,C.LocationEntryOutcome.Completed)
	check(model.phase==Model.Phase.Ready and model.snapshot==facts,"confirmed entry publishes snapshot")
	facts.staff.rows.append({"id":17});check(model.snapshot.staff.rows.is_empty(),"snapshot must own its nested data")
	model.refresh();model.refresh();service.poll()
	check(world.calls.size()==3 and world.calls[-1].request.operation==C.AreaOperation.LocationDetails,"refresh is read-only and cannot duplicate pending work")
	reply(world,service,facts);check(model.snapshot==facts,"refresh replaces observed facts")
	# Staff edits share service ownership, but bind both the Details and selector receipts.
	facts.staff.rows=[{"source":0,"occupation_id":87,"role":8,"unit_id":-1,"histfig_id":-1}]
	model.refresh();service.poll();reply(world,service,facts)
	var staff_prior: int=world.calls.size()
	for invalid in [[87,-1,5],[88,100,5],[87,-2,5],[87,100,0],[87,2147483648,5]]:
		model.set_staff(invalid[0],invalid[1],invalid[2]);service.poll()
	check(world.calls.size()==staff_prior,"invalid staff target/empty removal cannot send")
	model.set_staff(87,100,9223372036854775807);model.set_staff(87,101,5);model.refresh();service.poll()
	check(world.calls.size()==staff_prior+1 and world.calls[-1].request.operation==C.AreaOperation.LocationStaffEdit
		and world.calls[-1].request.expected_revision==facts.revision and world.calls[-1].request.expected_list_revision==9223372036854775807
		and world.calls[-1].request.unit_id==100 and world.calls[-1].request.occupation_id==87,"staff edit carries exact identities and both receipts once")
	check(model.snapshot==facts and model.phase==Model.Phase.Editing,"staff edit must not apply optimistically")
	var staffed=facts.duplicate(true);staffed.revision+=1;staffed.staff.rows[0].unit_id=100;staffed.staff.rows[0].histfig_id=900
	reply(world,service,staffed,C.LocationEditOutcome.Completed)
	check(model.snapshot==staffed and model.phase==Model.Phase.Ready,"staff success replaces confirmed Details")
	model.set_staff(87,-1,7);service.poll()
	check(world.calls[-1].request.unit_id==-1,"staff removal uses explicit native sentinel")
	reply(world,service,facts,C.LocationEditOutcome.Completed)
	for outcome in [C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown,C.LocationEditOutcome.Rejected]:
		model.set_staff(87,100,7);service.poll();var staff_ticket: int=model.ticket
		reply(world,service,{},outcome)
		if outcome==C.LocationEditOutcome.Unknown:check(service.result(staff_ticket).get("outcome","")=="unknown","staff unknown retained by service")
		staff_prior=world.calls.size();model.set_staff(87,100,7);model.refresh();service.poll()
		var expected_phase=Model.Phase.Stale if outcome==C.LocationEditOutcome.Stale else Model.Phase.Unknown if outcome==C.LocationEditOutcome.Unknown else Model.Phase.Rejected
		check(model.phase==expected_phase and model.snapshot.is_empty() and world.calls.size()==staff_prior,"failed staff edit cannot retry")
		model.open(target);service.poll();reply(world,service,facts);reply(world,service,facts,C.LocationEntryOutcome.Completed)
	staff_prior=world.calls.size();model.set_staff(87,100,7);model.close();service.poll()
	check(world.calls.size()==staff_prior,"close cancels unsent staff edit")
	model.open(target);service.poll();reply(world,service,facts);reply(world,service,facts,C.LocationEntryOutcome.Completed)
	model.set_staff(87,100,7);service.poll();model.close();model.open(target)
	reply(world,service,staffed,C.LocationEditOutcome.Completed)
	check(model.phase==Model.Phase.ReadingEntry and model.snapshot.is_empty(),"late staff success cannot revive closed owner")
	reply(world,service,facts);reply(world,service,facts,C.LocationEntryOutcome.Completed)
	# Native access edits use the displayed receipt and never optimistically change facts.
	var prior: int=world.calls.size()
	model.set_access(3);model.set_access(-1);model.set_access(4);service.poll()
	check(world.calls.size()==prior,"unavailable Members and invalid access modes cannot be sent")
	model.set_access(0);model.set_access(1);model.refresh();service.poll()
	check(world.calls.size()==prior+1 and world.calls[-1].request.operation==C.AreaOperation.LocationAccess
		and world.calls[-1].request.expected_revision==facts.revision and world.calls[-1].request.value==0,"access must send one exact-receipt mutation")
	check(model.phase==Model.Phase.Editing and model.snapshot==facts,"pending edit retains confirmed facts")
	var edited=facts.duplicate(true);edited.access=0;edited.revision+=1
	reply(world,service,edited,C.LocationEditOutcome.Completed)
	check(model.phase==Model.Phase.Ready and model.snapshot==edited,"confirmed edit publishes returned snapshot")
	for outcome in [C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown,C.LocationEditOutcome.Rejected]:
		model.set_access(1);service.poll();var edit_ticket: int=model.ticket
		reply(world,service,{},outcome)
		if outcome==C.LocationEditOutcome.Unknown:
			check(service.result(edit_ticket).get("outcome","")=="unknown","service retains unknown edit outcome")
		prior=world.calls.size();model.set_access(2);model.refresh();service.poll()
		var expected=Model.Phase.Stale if outcome==C.LocationEditOutcome.Stale else Model.Phase.Unknown if outcome==C.LocationEditOutcome.Unknown else Model.Phase.Rejected
		check(model.phase==expected and model.snapshot.is_empty() and world.calls.size()==prior,"failed/unknown access cannot retry")
		model.open(target);service.poll();reply(world,service,facts);reply(world,service,facts,C.LocationEntryOutcome.Completed)
	model.set_access(0);model.close();service.poll()
	check(world.calls.size()==prior+2,"queued access edit is cancelled by close")
	model.open(target);service.poll();reply(world,service,facts);reply(world,service,facts,C.LocationEntryOutcome.Completed)
	model.set_access(0);service.poll();model.close();model.open(target)
	reply(world,service,edited,C.LocationEditOutcome.Completed)
	check(model.phase==Model.Phase.ReadingEntry and model.snapshot.is_empty(),"late access success cannot revive previous owner")
	reply(world,service,facts);reply(world,service,facts,C.LocationEntryOutcome.Completed)
	# Closing after transmission and reopening the same target must invalidate the old callback.
	model.refresh();service.poll();model.close();model.open(target)
	reply(world,service,facts)
	check(model.phase==Model.Phase.ReadingEntry and model.snapshot.is_empty(),"late old reply cannot advance a reopened target")
	reply(world,service,facts);reply(world,service,{},C.LocationEntryOutcome.Stale)
	var count=world.calls.size();model.refresh();service.poll()
	check(model.phase==Model.Phase.Stale and world.calls.size()==count,"stale entry must not replay")
	model.open(target);service.poll();reply(world,service,facts);reply(world,service,{},C.LocationEntryOutcome.Unknown)
	count=world.calls.size();model.refresh();service.poll()
	check(model.phase==Model.Phase.Unknown and world.calls.size()==count,"partial entry stays unknown and cannot auto-refresh into success")
	# A queued close cancels before the bridge sees the read or entry.
	model.open(target);model.close();service.poll();check(world.calls.size()==count,"closed queued entry cannot be sent")
	# Cancel the entry while it is queued by the receipt callback.
	var cancel_entry=func():
		if model.phase==Model.Phase.Entering: model.close()
	model.changed.connect(cancel_entry)
	model.open(target);service.poll();count=world.calls.size();reply(world,service,facts)
	check(model.phase==Model.Phase.Closed and world.calls.size()==count,"closing queued entry prevents the mutation")
	model.changed.disconnect(cancel_entry)
	model.open(target);service.poll();reply(world,service,facts);model.close()
	reply(world,service,{},C.LocationEntryOutcome.Unknown)
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty(),"late partial entry cannot revive closed state")
	model.open(target);service.poll();var wrong=facts.duplicate(true);wrong.id=3
	reply(world,service,wrong);check(model.phase==Model.Phase.Rejected,"mismatched native identity is rejected")
	model.open(target);service.poll();world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
	check(model.phase==Model.Phase.Unavailable and model.snapshot.is_empty(),"epoch change retires the Details owner")
	model.close();service.free()
	print("LOCATION_DETAILS_STATE_PASS" if failures==0 else "LOCATION_DETAILS_STATE_FAIL")
	quit(failures)
