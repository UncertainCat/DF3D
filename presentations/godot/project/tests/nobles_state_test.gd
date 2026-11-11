extends SceneTree
const View=preload("res://scripts/nobles_view.gd")
const State=preload("res://scripts/nobles_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func row(assignment: int) -> Dictionary:
	return {"entity_id":7,"position_id":2,"assignment_id":assignment,"unit_id":-1,"nemesis_id":-1,"priority":0,"title":"fixture","squad_caption":"","holder_caption":"fixture","can_appoint":true,"has_room_assessment":false,"required_rooms":[0,0,0,0],"actual_rooms":[0,0,0,0],"required_furniture":[0,0,0,0],"actual_furniture":[0,0,0,0],"demand_status":-1,"mandate_status":-1}
func page(ids: Array=[-1],total:=1,offset:=0,revision:=9007199254740993) -> Dictionary:
	return {"nobles":{"outcome":C.NoblesOutcome.None,"list_revision":revision,"total":total,"offset":offset,"rows":ids.map(func(id):return row(id))}}
func stale() -> Dictionary:
	return {"status":C.ManagementStatus.Rejected,"nobles":{"outcome":C.NoblesOutcome.Stale,"list_revision":0,"total":0,"offset":0,"rows":[]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page([-1],2));check(state.phase==State.Phase.Reading and state.rows.is_empty(),"Partial Nobles list exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_list_revision==9007199254740993,"Continuation lost exact identity")
	service.reply(state.ticket,page([42],2,1));check(state.phase==State.Phase.Ready and state.rows.size()==2,"NEW and assigned office conflated")
	state.seek(99,1);check(state.first==1,"Nobles scroll unbounded")
	state.refresh();var old: int=state.ticket;state.open();var current: int=state.ticket
	service.reply(old,page([99]));check(state.ticket==current and service.detached.has(old) and state.rows.is_empty(),"Reopened controller accepted retired reply")
	state.close();service.reply(current,page());check(state.phase==State.Phase.Closed and state.rows.is_empty(),"Closed controller accepted late reply")
	state.open();old=state.ticket;service.session_changed.emit();service.reply(old,page());check(state.phase==State.Phase.Unavailable and state.rows.is_empty(),"Epoch change accepted old rows")
	state.open();service.reply(state.ticket,page([-1],2));service.reply(state.ticket,stale())
	check(service.calls[state.ticket].intent.offset==0 and service.calls[state.ticket].intent.expected_list_revision==0,"Stale continuation did not restart")
	service.reply(state.ticket,stale());check(state.phase==State.Phase.Rejected and state.ticket==0,"Stale retry unbounded")
	for fault in 7:
		state.open();service.reply(state.ticket,page([-1],2));var second:=page([42],2,1)
		match fault:
			0:second.nobles.rows[0].assignment_id=-1
			1:second.nobles.list_revision+=1
			2:second.nobles.rows=[]
			3:second.nobles.rows[0].actual_rooms=[1,2,3]
			4:second.nobles.rows[0].has_room_assessment=true
			5:second.nobles.rows[0].mandate_status=0
			6:second.nobles.total=3
		service.reply(state.ticket,second);check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Invalid Nobles page accepted: %d"%fault)
	for fault in 3:
		state.open();var portrait_page:=page()
		var holder: Dictionary=portrait_page.nobles.rows[0]
		holder.unit_id=10 if fault!=1 else -1;holder.has_room_assessment=fault!=1
		holder.appearance={"tile_pages":["fixture"],"palettes":[],"layers":[[0,0,0,1,1,65535,0,0,0,0]]}
		if fault==2:holder.appearance.layers[0][0]=1
		service.reply(state.ticket,portrait_page)
		check(state.phase==(State.Phase.Ready if fault==0 else State.Phase.Rejected),"Nobles holder recipe validation differs")
	state.open();service.reply(state.ticket,page([],0));check(state.phase==State.Phase.Ready and state.rows.is_empty(),"Empty Nobles list rejected")
	state.refresh();old=state.ticket;var submitted: int=service.next;service.reply(old,{"outcome":"unknown"})
	check(state.phase==State.Phase.Rejected and service.next==submitted,"Uncertain read replayed automatically")
	state.dispose();state.open();check(state.phase==State.Phase.Unavailable,"Missing service retained rows")
	var view:=View.new();view.state=state;view.size=Vector2(944,708)
	check(view.list_top()==108 and view.capacity()==16 and view.status_x()==496,"Nobles native geometry differs")
	check(view.groups()[1][0]=="Nobles and administrators","Nobles selected header row differs")
	check(view.room_suffix(0,0)=="NA" and view.room_suffix(1,0)=="MISSING" and view.room_suffix(2,1)=="PARTIAL" and view.room_suffix(1,1)=="GOOD","Nobles room artwork mapping differs")
	view.free();state.dispose();service.queue_free();await process_frame
	if failures==0:print("NOBLES_STATE_PASS")
	quit(1 if failures else 0)
