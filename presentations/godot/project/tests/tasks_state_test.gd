extends SceneTree
const View=preload("res://scripts/tasks_view.gd")
const State=preload("res://scripts/tasks_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
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
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("TASKS_STATE_PASS")
	quit(1 if failures else 0)
