extends SceneTree
const Owner=preload("res://scripts/standing_orders_panel.gd")
const State=preload("res://scripts/standing_orders_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func snapshot(outcome: int=C.StandingOrdersOutcome.None) -> Dictionary:
	var rows: Array=[]
	for id in 11:rows.append({"id":id,"value":2 if id==0 else 0,"visible":id<8,"editable":id<8})
	return {"standing_orders":{"category":0,"outcome":outcome,"settings":rows}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service)
	var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,snapshot());state.set_value(0,0)
	var pending:=state.ticket
	check(service.calls[pending].intent.expected_value==2,"Edit must use displayed native value")
	state.set_value(1,1)
	check(state.ticket==pending,"Pending edits must serialize")
	var applied:=snapshot(C.StandingOrdersOutcome.Applied);applied.standing_orders.settings[0].value=0
	service.reply(pending,applied)
	check(state.phase==State.Phase.Ready and state.settings[0].value==0,"Applied receipt becomes authority")
	state.set_value(8,1);check(state.ticket==0,"Unavailable automation cannot submit")
	state.set_value(1,1);pending=state.ticket
	service.reply(pending,{"status":C.ManagementStatus.Rejected,"outcome":"unknown"})
	var count:=service.next;state.set_value(1,1)
	check(state.phase==State.Phase.Unknown and state.settings.is_empty() and service.next==count,"Uncertain writes discard authority without replay")
	state.open();pending=state.ticket;state.close();service.reply(pending,snapshot())
	check(state.phase==State.Phase.Closed and state.settings.is_empty() and service.detached.has(pending),"Closed owner ignores late replies")
	state.open();pending=state.ticket;service.session_changed.emit();service.reply(pending,snapshot())
	check(state.phase==State.Phase.Unavailable and state.settings.is_empty(),"Session change retires authority")
	state.open();var malformed:=snapshot();malformed.standing_orders.settings[5].id=4
	service.reply(state.ticket,malformed)
	check(state.phase==State.Phase.Rejected and state.settings.is_empty(),"Malformed receipt cannot publish partial authority")
	state.open();service.reply(state.ticket,snapshot());state.set_value(1,1)
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"standing_orders":{"outcome":C.StandingOrdersOutcome.Stale,"settings":[]}})
	check(state.phase==State.Phase.Rejected and state.settings.is_empty(),"Stale edit requires fresh read")
	state.open();pending=state.ticket;state.select_category(1)
	service.reply(pending,snapshot())
	check(state.category==1 and state.settings.is_empty(),"Late category read replaced navigation")
	var hauling:=snapshot();hauling.standing_orders.category=1;hauling.standing_orders.settings.resize(6);hauling.standing_orders.settings[0].value=1
	service.reply(state.ticket,hauling)
	check(state.phase==State.Phase.Ready and state.settings.size()==6,"Hauling read rejected")
	state.set_value(0,2);check(state.ticket==0,"Hauling accepted weaving value")
	state.select_category(2)
	var refuse:=snapshot();refuse.standing_orders.category=2;refuse.standing_orders.settings.resize(10);refuse.standing_orders.settings[0].value=1
	for row: Dictionary in refuse.standing_orders.settings:row.visible=true;row.editable=true
	refuse.standing_orders.settings[2].editable=false
	service.reply(state.ticket,refuse);state.set_value(2,1)
	check(state.phase==State.Phase.Ready and state.ticket==0,"Visible disabled control submitted an edit")
	state.set_value(1,1);pending=state.ticket;state.select_category(0)
	check(state.category==2 and state.ticket==pending,"Navigation replaced pending mutation")
	state.close();state.open();service.reply(state.ticket,snapshot())
	for category in [3,4,6]:
		state.select_category(category)
		var extended: Dictionary={"standing_orders":{"category":category,"outcome":C.StandingOrdersOutcome.None,"settings":[]}}
		for id in State.COUNTS[category]:extended.standing_orders.settings.append({"id":id,"value":state.max_value(id),"visible":true,"editable":true})
		service.reply(state.ticket,extended)
		check(state.phase==State.Phase.Ready,"Extended maximum value was rejected")
		state.set_value(0,0)
		check(service.calls[state.ticket].intent.expected_value==state.max_value(0),"Extended edit lost native expected value")
		extended.standing_orders.outcome=C.StandingOrdersOutcome.Applied;extended.standing_orders.settings[0].value=0
		service.reply(state.ticket,extended)
		state.select_category(5);check(state.category==category,"Scalar navigation accepted Chores")
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("STANDING_ORDERS_STATE_PASS")
	quit(1 if failures else 0)
