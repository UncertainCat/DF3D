extends SceneTree
const Details=preload("res://scripts/location_details_state.gd")
const Workflow=preload("res://scripts/location_staff_workflow.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const Fixtures=preload("res://tests/location_staff_candidates_state_test.gd")
const C=preload("res://scripts/management_contract.gd")
var failures:=0
var world
var service
var details
var flow

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

func ready(occupied:=false) -> void:
	details.close()
	details.identity={"site_id":651,"id":2}
	details.snapshot={"site_id":651,"id":2,"kind":5,"revision":9007199254740993,
		"staff":{"rows":[{"source":0,"occupation_id":87,"role":8,"unit_id":100 if occupied else -1,"histfig_id":900 if occupied else -1}]}}
	details.phase=Details.Phase.Ready;details.changed.emit()

func reply_page() -> void:
	var sent: Dictionary=world.calls[-1].request
	var page: Dictionary={"site_id":651,"location_id":2,"occupation_id":87,"role":8,"revision":9007199254740995,
		"cursor":0,"next_cursor":0,"total":1,"rows":[{"unit_id":100,"histfig_id":900,"name":"Synthetic candidate",
		"base_name":"Synthetic","profession_name":"candidate","profession_color":7,"legendary":false,
		"source_index":0,"profession_order":809,"status_order":0,"name_sort_key":PackedByteArray([97]),"profession_sort_key":PackedByteArray([112]),
		"score":1,"skills":[{"id":58,"rating":1,"experience":0,"weight":1}]}]}
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Ok,"area":{"operation":sent.operation,"location_staff_candidates":page}}
	service.poll()

func reply_edit(outcome: int) -> void:
	var sent: Dictionary=world.calls[-1].request
	var area: Dictionary={"operation":sent.operation,"location_edit_outcome":outcome}
	if outcome==C.LocationEditOutcome.Completed:
		area.location_details=details.snapshot.duplicate(true);area.location_details.revision+=1
		area.location_details.staff.rows[0].unit_id=sent.unit_id
		area.location_details.staff.rows[0].histfig_id=900 if sent.unit_id>=0 else -1
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Ok if outcome==C.LocationEditOutcome.Completed else C.ManagementStatus.Rejected,"area":area}
	service.poll()

func _initialize() -> void:call_deferred("run")
func run() -> void:
	world=Fixtures.World.new();service=Service.new();service.configure(world)
	details=Details.new();details.configure(service);flow=Workflow.new();flow.configure(details)
	ready();flow.open(87);flow.open(87);flow.choose(100);service.poll()
	check(world.calls.size()==1 and world.calls[-1].request.operation==C.AreaOperation.LocationStaffCandidates,"opening can only read once; partial list cannot edit")
	reply_page();flow.choose(999);service.poll()
	check(world.calls.size()==1,"unobserved candidate cannot be selected")
	flow.choose(100);flow.choose(100);service.poll()
	check(world.calls.size()==2 and flow.mode==Workflow.Mode.Editing and flow.candidates.rows.is_empty(),"selecting submits once and retires candidate facts")
	check(world.calls[-1].request.expected_revision==9007199254740993 and world.calls[-1].request.expected_list_revision==9007199254740995,"both owning receipts preserved without rounding")
	reply_edit(C.LocationEditOutcome.Completed)
	check(flow.mode==Workflow.Mode.Closed and details.phase==Details.Phase.Ready and details.snapshot.staff.rows[0].unit_id==100,"completion returns to authoritative Details")
	for outcome in [C.LocationEditOutcome.Completed,C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown]:
		ready(true);var before: int=world.calls.size()
		flow.open(87);service.poll();check(world.calls.size()==before,"occupied portrait cannot open assignment selector")
		flow.open(87,true);service.poll();check(flow.mode==Workflow.Mode.Removing,"remove first obtains current list receipt")
		reply_page();check(world.calls[-1].request.unit_id==-1 and flow.mode==Workflow.Mode.Editing,"fresh removal read continues to explicit removal")
		reply_edit(outcome);before=world.calls.size();flow.choose(100);service.poll()
		check(flow.mode==Workflow.Mode.Closed and world.calls.size()==before,"completed/failed removal cannot replay")
	ready();var before: int=world.calls.size();flow.open(87);flow.close();service.poll()
	check(world.calls.size()==before and details.phase==Details.Phase.Ready,"cancelled queued selector read is local only")
	flow.open(87);service.poll();before=world.calls.size();flow.close();reply_page();flow.choose(100);service.poll()
	check(world.calls.size()==before and flow.mode==Workflow.Mode.Closed,"late read cannot revive cancelled selector")
	flow.open(87);service.poll();details.snapshot.revision+=1;details.changed.emit();reply_page();flow.choose(100);service.poll()
	check(flow.mode==Workflow.Mode.Closed and world.calls[-1].request.operation==C.AreaOperation.LocationStaffCandidates,"new Details revision cancels old selector")
	ready();flow.open(87,true);service.poll();check(flow.mode==Workflow.Mode.Closed,"empty role cannot remove")
	flow.open(87);service.poll();reply_page();before=world.calls.size();flow.choose(100);details.close();service.poll()
	check(world.calls.size()==before and flow.mode==Workflow.Mode.Closed,"closing Details cancels unsent assignment")
	ready();flow.open(87);service.poll();reply_page();flow.choose(100);service.poll();details.close();reply_edit(C.LocationEditOutcome.Unknown)
	check(flow.mode==Workflow.Mode.Closed and details.phase==Details.Phase.Closed,"late unknown edit cannot revive closed Details")
	flow.dispose();details.close();service.free()
	print("LOCATION_STAFF_WORKFLOW_PASS" if failures==0 else "LOCATION_STAFF_WORKFLOW_FAIL "+str(failures));quit(0 if failures==0 else 1)
