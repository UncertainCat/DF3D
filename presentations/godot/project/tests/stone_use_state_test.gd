extends SceneTree
const State=preload("res://scripts/stone_use_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func response() -> Dictionary:
	return {"stone_use":{"outcome":C.StoneUseOutcome.None,"restrictions":[1,0],"rows":[
		{"category":0,"index":0,"restricted":true,"name":"fixture economic","uses":"fixture use","magma_safe":true,"material_token":"INORGANIC:FIXTURE_A"},
		{"category":1,"index":1,"restricted":false,"name":"fixture other","uses":"","magma_safe":false,"material_token":"INORGANIC:FIXTURE_B"}]}}
func applied() -> Dictionary:return {"stone_use":{"outcome":C.StoneUseOutcome.Applied,"rows":[],"restrictions":[]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service)
	var state:=State.new();state.configure(service);state.open();service.reply(state.ticket,response())
	check(state.phase==State.Phase.Ready and state.category_rows()[0].index==0,"Stone use read rejected")
	state.select_category(1);check(state.category_rows()[0].index==1,"Category lost native rows")
	state.toggle(0);check(state.phase==State.Phase.Ready,"Other category target accepted")
	state.toggle(1);var pending:=state.ticket
	check(state.rows.is_empty() and state.restrictions.is_empty() and service.calls[pending].intent.expected==[1,0],"Edit lost complete receipt or retained authority")
	state.toggle(1);state.select_category(0);check(state.ticket==pending and state.category==1,"Pending edit was replaced")
	service.reply(pending,applied());check(state.phase==State.Phase.Reading,"Successful edit failed to refresh")
	service.reply(state.ticket,response());check(state.category==1,"Refresh reset category")
	state.toggle(1);service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"stone_use":{"outcome":C.StoneUseOutcome.Unknown,"rows":[],"restrictions":[]}})
	var count: int=service.next;state.toggle(1);check(state.phase==State.Phase.Unknown and state.rows.is_empty() and service.next==count,"Unknown retained authority or replayed")
	state.open();pending=state.ticket;state.close();service.reply(pending,response());check(state.phase==State.Phase.Closed and state.rows.is_empty() and service.detached.has(pending),"Closed read was accepted")
	state.open();service.reply(state.ticket,response());state.toggle(0);pending=state.ticket;state.close();state.open();var fresh:=state.ticket
	service.reply(pending,applied());check(state.ticket==fresh and state.phase==State.Phase.Reading,"Late apply replaced new owner")
	service.session_changed.emit();service.reply(fresh,response());check(state.phase==State.Phase.Unavailable and state.category==0 and state.rows.is_empty(),"Session change retained state")
	for fault in ["duplicate","flag","contradiction","caption","category","index"]:
		state.open();var malformed:=response();var v: Dictionary=malformed.stone_use
		if fault=="duplicate":v.rows.append(v.rows[0].duplicate())
		if fault=="flag":v.restrictions[0]=2
		if fault=="contradiction":v.rows[0].restricted=false
		if fault=="caption":v.rows[0].name=""
		if fault=="category":v.rows[0].category=2
		if fault=="index":v.rows[0].index=1.5
		service.reply(state.ticket,malformed);check(state.phase==State.Phase.Rejected and state.restrictions.is_empty(),"Malformed read accepted: "+fault)
	state.open();service.reply(state.ticket,response());state.select_category(1);state.first=[4,7];state.close(true);state.open(true)
	check(state.category==1 and state.first==[4,7] and state.rows.is_empty(),"Retained navigation kept authority or lost intent")
	service.reply(state.ticket,response());check(state.first==[0,0],"Fresh shorter category lists failed to clamp")
	state.close();check(state.category==0 and state.first==[0,0],"Full close retained navigation")
	state.dispose();service.queue_free()
	if failures==0:print("STONE_USE_STATE_PASS")
	quit(1 if failures else 0)
