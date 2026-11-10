extends SceneTree
const View=preload("res://scripts/places_view.gd")
const Owner=preload("res://scripts/places_panel.gd")
const Shell=preload("res://scripts/fortress_ui.gd")
const State=preload("res://scripts/places_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
class Host extends RefCounted:
	var active
	func activate(owner) -> bool:
		if is_instance_valid(active) and active!=owner:active.close_panel()
		active=owner;return true
	func allows_panel_input(owner) -> bool:return active==owner
	func release(owner) -> void:
		if active==owner:active=null
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func row(id: int,tab:=0) -> Dictionary:
	return {"building_id":id,"name":"fixture","subtitle":"","job_caption":"","status_caption":"","secondary_status":"","status_overlay":"","operator_caption":"","additional_jobs":0,"siege_action":0 if tab==5 else -1}
func page(tab:=0,offset:=0,ids: Array=[1],total:=1,revision:=8) -> Dictionary:
	return {"places":{"outcome":C.PlacesOutcome.None,"tab":tab,"list_revision":revision,"offset":offset,"total":total,"rows":ids.map(func(id):return row(id,tab))}}
func stale(tab:=0) -> Dictionary:
	return {"status":C.ManagementStatus.Rejected,"places":{"outcome":C.PlacesOutcome.Stale,"tab":tab,"list_revision":0,"total":0,"offset":0,"rows":[]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	check(Shell.Registry.PANEL_SCRIPTS.has("places") and not Shell.Registry.PANEL_ROUTES.has("Places"),"Places public gate changed")
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page(0,0,[1],2));check(state.phase==State.Phase.Reading and state.rows.is_empty(),"Partial list exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_list_revision==8,"Continuation lost identity")
	service.reply(state.ticket,page(0,1,[2],2));check(state.phase==State.Phase.Ready and state.rows.size()==2,"Pages not assembled")
	state.seek(99,1);check(state.first==1,"Scroll not clamped")
	state.select_tab(5);service.reply(state.ticket,page(5));check(state.tab==5 and state.first==0 and state.rows[0].siege_action==0,"Tab data mixed")
	state.select_tab(0);service.reply(state.ticket,page(0,0,[1,2],2));check(state.first==1,"Tab scroll not retained")
	state.refresh();var old: int=state.ticket;state.select_tab(3);var current: int=state.ticket
	service.reply(old,page());check(state.ticket==current and state.tab==3 and state.rows.is_empty() and service.detached.has(old),"Old tab reply changed current tab")
	service.reply(current,page(3));state.refresh();old=state.ticket;state.close();service.reply(old,page(3))
	check(state.phase==State.Phase.Closed and state.rows.is_empty(),"Closed controller accepted late reply")
	state.open();old=state.ticket;service.session_changed.emit();service.reply(old,page())
	check(state.phase==State.Phase.Unavailable and state.rows.is_empty(),"Epoch change retained rows")
	state.open();service.reply(state.ticket,page(0,0,[1],2));service.reply(state.ticket,stale())
	check(service.calls[state.ticket].intent.offset==0 and service.calls[state.ticket].intent.expected_list_revision==0,"Stale list did not restart from zero")
	service.reply(state.ticket,stale());check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Stale restart unbounded")
	for fault in 6:
		state.open();service.reply(state.ticket,page(0,0,[1],2));var second:=page(0,1,[2],2)
		match fault:
			0:second.places.rows[0].building_id=1
			1:second.places.tab=1
			2:second.places.list_revision=9
			3:second.places.rows=[]
			4:second.places.rows[0].siege_action=0
			5:second.places.rows[0].position=Vector3i(-1,0,0)
		service.reply(state.ticket,second);check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Malformed page accepted: %d"%fault)
	state.open(4);service.reply(state.ticket,page(4,0,[],0));check(state.phase==State.Phase.Ready and state.rows.is_empty(),"Empty tab rejected")
	state.dispose();state.open();check(state.phase==State.Phase.Unavailable,"Missing service retained read")
	var view:=View.new();view.state=state;view.size=Vector2(944,708)
	check(view.tab_rect(0)==Rect2(8,60,72,24) and view.tab_rect(3)==Rect2(8,84,104,24),"Places tabs differ from native reference")
	check(view.list_top()==120 and view.capacity()==15,"Places row geometry differs")
	view.free();state.dispose()
	var owner:=Owner.new();root.add_child(owner);var host:=Host.new();owner.ui_host=host;owner.state.configure(service)
	var focused: Array=[];var inspected: Array=[]
	owner.focus_requested.connect(func(tile):focused.append(tile))
	owner.inspect_requested.connect(func(tab,id,tile):inspected.append([tab,id,tile]))
	var initial:=page();initial.places.rows[0].position=Vector3i(1,2,3)
	var fresh:=page();fresh.places.rows[0].position=Vector3i(4,5,6)
	owner.open_panel();service.reply(owner.state.ticket,initial);owner._navigate(owner.state.rows[0],false)
	check(focused.is_empty() and owner.state.phase==State.Phase.Reading,"Recenter used displayed coordinates")
	service.reply(owner.state.ticket,fresh)
	check(focused==[Vector3i(4,5,6)] and host.active==null and owner.state.phase==State.Phase.Closed,"Recenter did not release owner with fresh coordinates")
	for tab in 6:
		owner.open_panel();if tab>0:owner.state.select_tab(tab)
		var current_page:=page(tab);current_page.places.rows[0].position=Vector3i(4,5,6)
		service.reply(owner.state.ticket,current_page);owner._navigate(owner.state.rows[0],true);service.reply(owner.state.ticket,current_page)
		check(inspected[-1]==[tab,1,Vector3i(4,5,6)] and host.active==null,"Inspector handoff lost identity or retained input")
	owner.open_panel();service.reply(owner.state.ticket,initial);owner._navigate(owner.state.rows[0],false);old=owner.state.ticket
	owner.state.select_tab(2);service.reply(old,fresh);service.reply(owner.state.ticket,page(2))
	check(focused.size()==1 and owner.destination.is_empty(),"Tab change retained navigation intent")
	owner.close_panel();owner.open_panel();service.reply(owner.state.ticket,initial);owner._navigate(owner.state.rows[0],true);old=owner.state.ticket
	owner.set_play_enabled(false);service.reply(old,fresh)
	check(inspected.size()==6 and host.active==null,"Disabled play accepted late navigation")
	owner.queue_free();service.queue_free();await process_frame
	if failures==0:print("PLACES_STATE_PASS")
	quit(1 if failures else 0)
