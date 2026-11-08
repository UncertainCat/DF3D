extends SceneTree
const State=preload("res://scripts/chores_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func response(applied: bool=false) -> Dictionary:
	var settings: Array=[];var captions: Array=[]
	for id in State.LABORS:settings.append({"id":id,"enabled":true});captions.append({"id":id,"caption":"fixture labor"})
	return {"chores":{"outcome":C.ChoresOutcome.Applied if applied else C.ChoresOutcome.None,"snapshot":{"enabled":true,"children":PackedInt32Array([42,7]),"exempted":PackedInt32Array([7]),"labors":settings},"children":[] if applied else [{"id":42,"caption":"fixture child"},{"id":7,"caption":"fixture child"}],"labors":[] if applied else captions}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service)
	state.open();service.reply(state.ticket,response())
	check(state.phase==State.Phase.Ready and state.children.size()==2,"Native read rejected")
	state.set_labor(0,false);state.set_exempt(99,true);check(state.ticket==0,"Invalid target submitted")
	state.set_enabled(false);var pending:=state.ticket
	check(service.calls[pending].intent.expected==state.snapshot,"Edit lost complete receipt")
	state.set_exempt(42,true);check(state.ticket==pending,"Concurrent edit submitted")
	service.reply(pending,response(true))
	check(state.phase==State.Phase.Reading and state.ticket!=pending and service.calls[state.ticket].intent.action==C.ManagementAction.ChoresRead,"Applied edit did not refresh metadata")
	var refreshed:=response();refreshed.chores.snapshot.enabled=false;service.reply(state.ticket,refreshed)
	check(state.phase==State.Phase.Ready and not state.snapshot.enabled,"Fresh authority missing")
	state.set_labor(23,false);pending=state.ticket
	check(not service.calls[pending].intent.expected.enabled,"Edit reused old receipt")
	service.reply(pending,{"status":C.ManagementStatus.Rejected,"chores":{"outcome":C.ChoresOutcome.Unknown}})
	var count: int=service.next;state.set_enabled(true)
	check(state.phase==State.Phase.Unknown and state.snapshot.is_empty() and state.children.is_empty() and service.next==count,"Unknown retained authority or replayed")
	state.open();pending=state.ticket;state.close();service.reply(pending,response())
	check(state.phase==State.Phase.Closed and state.snapshot.is_empty() and service.detached.has(pending),"Closed owner accepted late reply")
	state.open();pending=state.ticket;service.session_changed.emit();service.reply(pending,response())
	check(state.phase==State.Phase.Unavailable and state.snapshot.is_empty(),"Session change accepted old reply")
	for defect in ["children","exempted","labors","caption"]:
		state.open();var malformed:=response()
		if defect=="children":malformed.chores.snapshot.children=PackedInt32Array([42,42])
		if defect=="exempted":malformed.chores.snapshot.exempted=PackedInt32Array([7,7])
		if defect=="labors":malformed.chores.snapshot.labors[0].id=0
		if defect=="caption":malformed.chores.children[0].id=7
		service.reply(state.ticket,malformed)
		check(state.phase==State.Phase.Rejected and state.snapshot.is_empty(),"Malformed read published partial authority")
	state.open();service.reply(state.ticket,response());state.set_exempt(42,true);pending=state.ticket
	state.close();state.open();var newer:=state.ticket;service.reply(pending,response(true))
	check(state.ticket==newer and state.phase==State.Phase.Reading,"Late mutation replaced new read")
	service.reply(newer,response());state.set_exempt(42,true)
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"chores":{"outcome":C.ChoresOutcome.Stale}})
	check(state.phase==State.Phase.Rejected and state.snapshot.is_empty(),"Stale receipt retained authority")
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("CHORES_STATE_PASS")
	quit(1 if failures else 0)
