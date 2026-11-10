extends SceneTree
const Owner=preload("res://scripts/tasks_panel.gd")
const View=preload("res://scripts/tasks_view.gd")
const State=preload("res://scripts/tasks_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
class Host extends RefCounted:
	var active
	func activate(owner) -> bool:
		if is_instance_valid(active) and active!=owner:active.close_panel()
		active=owner;return true
	func allows_panel_input(owner) -> bool:return active==owner
	func release(owner) -> void:
		if active==owner:active=null
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func row(id: int) -> Dictionary:
	return {"job_id":id,"worker_id":-1,"building_id":7,"revision":9,"caption":"fixture","worker_name":"","building_caption":"fixture","can_view_job":true,"can_repeat":false,"can_suspend":true,"can_remove_worker":false,"can_cancel":true,"repeating":false,"suspended":true}
func page(offset:=0,ids: Array=[1],total:=1,revision:=8) -> Dictionary:
	return {"tasks":{"outcome":C.TasksOutcome.None,"list_revision":revision,"total":total,"offset":offset,"job_id":-1,"rows":ids.map(func(id):return row(id))}}
func receipt(id:=1,outcome:=C.TasksOutcome.Applied) -> Dictionary:
	return {"tasks":{"outcome":outcome,"list_revision":0,"total":0,"offset":0,"job_id":id,"rows":[]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page(0,[1],2));check(state.phase==State.Phase.Reading and state.rows.is_empty() and service.calls[state.ticket].intent.offset==1,"Partial page exposed authority")
	service.reply(state.ticket,page(1,[2],2));check(state.phase==State.Phase.Ready and state.rows.size()==2,"Pages not assembled")
	state.apply(1,C.TasksOperation.Repeat);check(state.phase==State.Phase.Ready,"Unavailable native capability submitted")
	state.apply(1,C.TasksOperation.Suspend);var pending: int=state.ticket
	check(state.rows.is_empty() and service.calls[pending].intent.expected_revision==9 and service.calls[pending].intent.expected_state==1,"Edit lost receipt or retained authority")
	state.apply(1,C.TasksOperation.Suspend);check(state.ticket==pending,"Pending mutation replaced")
	service.reply(pending,receipt());check(state.phase==State.Phase.Reading,"Applied mutation did not refresh")
	service.reply(state.ticket,page());state.apply(1,C.TasksOperation.Cancel);var unknown:=receipt(1,C.TasksOutcome.Unknown);unknown.status=C.ManagementStatus.Rejected
	service.reply(state.ticket,unknown);var count: int=service.next;state.apply(1,C.TasksOperation.Cancel)
	check(state.phase==State.Phase.Unknown and state.rows.is_empty() and service.next==count,"Unknown mutation replayed")
	state.open();pending=state.ticket;state.close();service.reply(pending,page());check(state.phase==State.Phase.Closed and state.rows.is_empty() and service.detached.has(pending),"Late read survived close")
	state.open();service.reply(state.ticket,page());state.apply(1,C.TasksOperation.Suspend);pending=state.ticket;state.close();state.open();var current: int=state.ticket
	service.reply(pending,receipt());check(state.ticket==current,"Late mutation replaced new owner")
	service.session_changed.emit();service.reply(current,page());check(state.phase==State.Phase.Unavailable and state.rows.is_empty(),"Session change retained authority")
	state.open();service.reply(state.ticket,page(0,[1],2));service.reply(state.ticket,page(1,[1],2));check(state.phase==State.Phase.Rejected,"Duplicate job across pages accepted")
	state.open();service.reply(state.ticket,page(0,[1],2));service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"tasks":{"outcome":C.TasksOutcome.Stale}})
	check(state.phase==State.Phase.Reading and service.calls[state.ticket].intent.offset==0,"Stale page failed to restart")
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"tasks":{"outcome":C.TasksOutcome.Stale}});check(state.phase==State.Phase.Rejected,"Stale restart loop unbounded")
	state.open();service.reply(state.ticket,page());state.rows[0].worker_id=42
	state.inspect_worker(1);pending=state.ticket
	check(state.phase==State.Phase.Navigating and state.rows.is_empty() and service.calls[pending].intent.unit_id==42,"Worker sheet navigation retained stale rows")
	state.close();service.reply(pending,{"creature_position":{"unit_id":42,"position":Vector3i(1,2,3)}})
	check(state.phase==State.Phase.Closed,"Closed worker navigation accepted late reply")
	var view:=View.new();root.add_child(view);view.state=state;view.size=Vector2(944,708)
	state.phase=State.Phase.Ready;state.rows=[row(1)];state.rows[0].building_position=Vector3i(1,2,3)
	check(view.hover_target(Vector2(220,90))=="job-recenter","Task recenter hover missing")
	check(view.hover_target(Vector2(316,90))=="suspend" and view.hover_target(Vector2(340,90))=="remove","Task edit hover mismatch")
	check(view.hover_target(Vector2(292,90)).is_empty(),"Disabled worker control has hover")
	state.rows[0].worker_id=42;state.rows[0].can_remove_worker=true
	check(view.hover_target(Vector2(292,90))=="remove-worker" and view.hover_target(Vector2(676,90))=="worker-recenter" and view.hover_target(Vector2(700,90))=="worker-view","Worker control hover mismatch")
	state.phase=State.Phase.Applying;check(view.hover_target(Vector2(340,90)).is_empty(),"Pending Tasks retained hover authority")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_tasks.json"))
	for sample in fixture.actions_reference.actions.hover:
		check(preload("res://scripts/native_hover_view.gd").TASKS_HELP[sample.kind]==sample.lines,"Tasks help differs from native capture")
	view.queue_free();await process_frame
	var owner:=Owner.new();root.add_child(owner);var host:=Host.new();owner.ui_host=host;owner.state.configure(service)
	var focused: Array=[];owner.focus_requested.connect(func(tile):focused.append(tile))
	owner.open_panel();var initial:=page();initial.tasks.rows[0].building_position=Vector3i(1,2,3)
	service.reply(owner.state.ticket,initial)
	owner._navigate(owner.state.rows[0].duplicate(true),false,false)
	check(owner.state.phase==State.Phase.Reading and focused.is_empty(),"Recenter used stale displayed coordinates")
	var fresh_page:=page();fresh_page.tasks.rows[0].building_position=Vector3i(4,5,6)
	service.reply(owner.state.ticket,fresh_page)
	check(focused==[Vector3i(4,5,6)] and owner.state.phase==State.Phase.Closed and host.active==null,"Recenter failed to close owner and use fresh destination")
	owner.open_panel();service.reply(owner.state.ticket,initial);owner._navigate(owner.state.rows[0].duplicate(true),false,false);pending=owner.state.ticket
	owner.close_panel();service.reply(pending,fresh_page);check(focused.size()==1,"Retired navigation moved camera")
	owner.job_state.configure(service);owner.open_panel();service.reply(owner.state.ticket,initial)
	owner._navigate(owner.state.rows[0].duplicate(true),false,true)
	check(owner.job_open() and owner.job_state.job_id==1 and owner.job_state.building_id==7 and host.active==owner,"View task did not enter owned Details")
	owner.job_state.close();check(owner.state.phase==State.Phase.Ready and host.active==owner,"Details close lost Tasks owner")
	owner._navigate(owner.state.rows[0].duplicate(true),false,true);owner.close_panel()
	check(not owner.job_open() and host.active==null,"Closing Tasks retained Details")
	owner.open_panel();owner.set_play_enabled(false);check(owner.state.phase==State.Phase.Closed and host.active==null,"Disabled play retained Tasks owner")
	owner.queue_free();await process_frame
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("TASKS_STATE_PASS")
	quit(1 if failures else 0)
