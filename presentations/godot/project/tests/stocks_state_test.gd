extends SceneTree
const View=preload("res://scripts/stocks_view.gd")
const FortressUI=preload("res://scripts/fortress_ui.gd")
const Registry=preload("res://scripts/ui_availability.gd")
const Owner=preload("res://scripts/stocks_panel.gd")
class ItemOwnerStub extends Node:
	var selected: int=-1
	func open_target(id: int) -> void:selected=id
const State=preload("res://scripts/stocks_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func response(category: int=39,matches: Array=[39,37,26],revision: int=9007199254740993) -> Dictionary:
	var categories: Array=[]
	var order: Array=[39,37,26]
	for type in 93:
		if not order.has(type):order.append(type)
	for type in order:categories.append({"type":type,"caption":"fixture category","stored":"1","unavailable":"","matches":matches.has(type)})
	var groups: Array=[]
	if category>=0:groups.append({"type":category,"subtype":-1,"subcat1":0,"subcat2":0,"amount":2,"caption":"fixture group","matches":matches.has(category),"expanded":true,"flags":0,"revision":revision,"item_ids":[7,8]})
	return {"stocks_menu":{"category":category,"categories":categories,"groups":groups,"items":[],"outcome":C.StocksMenuOutcome.None}}
func item(id: int) -> Dictionary:
	return {"id":id,"type":39,"caption":"fixture item","material_token":"","subtype_raw":"","flags":0,"can_dump":true,"can_melt":false}
func ready(state,service) -> void:
	state.open();service.reply(state.ticket,response(-1));service.reply(state.ticket,response())
func _initialize() -> void:call_deferred("run")
func click_filter() -> void:
	var move:=InputEventMouseMotion.new();move.position=Vector2(50,16);Input.parse_input_event(move)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=Vector2(50,16);event.global_position=event.position
		Input.parse_input_event(event);await process_frame
func wheel_at(point: Vector2,up:=false,page:=false) -> void:
	var event:=InputEventMouseButton.new();event.pressed=true;event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN;event.shift_pressed=page
	Input.parse_input_event(event);await process_frame
func run() -> void:
	var filter=preload("res://scripts/stocks_filter.gd").new();root.add_child(filter);filter.size=Vector2(300,36);filter.configure(StyleBoxEmpty.new(),[])
	await process_frame
	await click_filter();check(filter.has_focus(),"First filter click starts typing")
	await click_filter();check(not filter.has_focus(),"Second filter click ends typing")
	var letter:=InputEventKey.new();letter.pressed=true;letter.unicode=97;letter.keycode=KEY_A
	filter.feed_key(letter);check(filter.value.is_empty(),"Unfocused filter ignores text")
	await click_filter();filter.feed_key(letter);check(filter.value.get_string_from_utf8()=="A","Stocks filter keeps native uppercase ASCII")
	var enter:=InputEventKey.new();enter.pressed=true;enter.keycode=KEY_ENTER;filter.feed_key(enter)
	check(not filter.has_focus() and filter.value.get_string_from_utf8()=="A","Enter ends typing without clearing query")
	filter.free()
	check(Registry.PANEL_SCRIPTS.has("stocks") and not Registry.allows_launcher("Stocks"),"Incomplete Stocks launcher exposed")
	var service:=Service.new();root.add_child(service)
	var state:=State.new();state.configure(service);ready(state,service)
	check(state.phase==State.Phase.Ready and state.category==39,"Initial native category not selected")
	var identity: String=state.key(state.groups[0]);state.toggle_expansion(identity)
	check(not state.expanded(state.groups[0]),"Group collapse failed")
	state.set_query("silver");service.reply(state.ticket,response(39,[39]))
	check(not state.expanded(state.groups[0]),"Search reset expansion")
	state.set_query("");service.reply(state.ticket,response())
	state.select_category(37);service.reply(state.ticket,response(37));state.select_category(39);service.reply(state.ticket,response())
	check(state.expanded(state.groups[0]),"Category roundtrip retained expansion unlike native")
	# Native231025: ZZ chooses26; ZZZ has no matches and chooses39;
	# backspace to ZZ chooses26; clearing retains26 although first overall is39.
	for query in ["ZZ","ZZZ","ZZ",""]:state.set_query(query)
	service.reply(state.ticket,response(39,[26]));check(state.category==26,"Search did not choose first match")
	service.reply(state.ticket,response(26,[26]));check(service.calls[state.ticket].intent.query=="ZZZ","Queued query skipped")
	service.reply(state.ticket,response(26,[]));check(state.category==39,"Empty match did not choose first overall")
	service.reply(state.ticket,response(39,[]));service.reply(state.ticket,response(39,[26]))
	service.reply(state.ticket,response(26,[26]));service.reply(state.ticket,response(26))
	check(state.phase==State.Phase.Ready and state.category==26 and state.query=="","Fast typing lost native category history")
	ready(state,service);state.request_items([7,8]);var reply:=response();reply.stocks_menu.items=[item(7),item(8)];service.reply(state.ticket,reply)
	check(state.items.size()==2,"Visible row facts missing")
	state.request_items([7,8,7]);check(state.phase==State.Phase.Ready,"Duplicate requested item accepted")
	var calls: int=service.next;state.request_items([7]);state.request_items([99]);check(service.next==calls,"Cached or foreign item request submitted")
	identity=state.key(state.groups[0]);state.apply_group(identity,C.StocksFlagAction.Hidden,true)
	var pending: int=state.ticket
	check(state.phase==State.Phase.Applying and state.groups.is_empty() and state.items.is_empty() and service.calls[pending].intent.expected_revision==9007199254740993,"Mutation lost exact revision or retained authority")
	state.set_query("ignored");state.apply_group(identity,0,false);check(state.ticket==pending and state.query=="","Pending mutation replaced")
	reply=response(39,[39],9007199254740994);reply.stocks_menu.outcome=C.StocksMenuOutcome.Applied;service.reply(pending,reply)
	check(state.phase==State.Phase.Reading,"Mutation did not refresh retained filter")
	service.reply(state.ticket,response());state.apply_group(identity,3,false)
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"stocks_menu":{"outcome":C.StocksMenuOutcome.Unknown}})
	calls=service.next;state.apply_group(identity,3,false)
	check(state.phase==State.Phase.Unknown and state.groups.is_empty() and service.next==calls,"Unknown replayed or retained authority")
	ready(state,service);state.request_items([7]);pending=state.ticket;state.close();service.reply(pending,response())
	check(state.phase==State.Phase.Closed and state.groups.is_empty() and service.detached.has(pending),"Closed owner accepted late read")
	ready(state,service);state.apply_group(identity,3,true);pending=state.ticket;state.close();state.open();var fresh: int=state.ticket
	service.reply(pending,reply);check(state.ticket==fresh and state.phase==State.Phase.Reading,"Late edit replaced fresh owner")
	service.session_changed.emit();service.reply(fresh,response(-1))
	check(state.phase==State.Phase.Unavailable and state.category==-1 and state.query=="","Session retained state")
	for fault in ["duplicate category","duplicate member","foreign item","zero revision"]:
		ready(state,service);state.set_query("x");reply=response()
		if fault=="duplicate category":reply.stocks_menu.categories[1]=reply.stocks_menu.categories[0].duplicate()
		if fault=="duplicate member":reply.stocks_menu.groups[0].item_ids=[7,7]
		if fault=="foreign item":reply.stocks_menu.items=[item(99)]
		if fault=="zero revision":reply.stocks_menu.groups[0].revision=0
		service.reply(state.ticket,reply);check(state.phase==State.Phase.Rejected and state.groups.is_empty(),"Malformed receipt accepted: "+fault)
	ready(state,service);state.request_items([7]);reply=response();reply.stocks_menu.items=[item(7)]
	reply.stocks_menu.items[0].appearance={"material_token":"","subtype_raw":"","color_token":"","flags":0,"stack":0}
	service.reply(state.ticket,reply);check(state.phase==State.Phase.Rejected,"Invalid item appearance accepted")
	ready(state,service);state.items={7:item(7)}
	calls=service.next;state.apply_item(99,3,true);state.apply_item(7,2,true)
	check(service.next==calls,"Missing or ineligible individual target submitted")
	state.apply_item(7,3,true);pending=state.ticket
	check(service.calls[pending].intent=={"action":C.ManagementAction.StocksItemApply,"category":39,"subtype":-1,"subcat1":0,"subcat2":0,"item_id":7,"expected_revision":9007199254740993,"operation":3,"value":1},"Individual intent lost target/group authority")
	check(state.phase==State.Phase.Applying and state.items.is_empty(),"Individual edit retained authority")
	reply=response();reply.stocks_menu.outcome=C.StocksMenuOutcome.Applied;service.reply(pending,reply)
	check(state.phase==State.Phase.Reading,"Individual receipt did not refresh Stocks")
	service.reply(state.ticket,response());state.items={7:item(7)};state.apply_item(7,3,false)
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"stocks_menu":{"outcome":C.StocksMenuOutcome.Unknown}})
	calls=service.next;state.apply_item(7,3,false)
	check(state.phase==State.Phase.Unknown and service.next==calls,"Unknown individual edit replayed")
	ready(state,service);state.items={7:item(7)};state.apply_item(7,3,true);pending=state.ticket
	state.close();service.reply(pending,reply)
	check(state.phase==State.Phase.Closed and service.detached.has(pending),"Late individual receipt revived closed Stocks")
	ready(state,service);state.items={7:item(7)};state.groups[0].flags=240
	var view:=View.new();view.state=state
	view.item_canvas=Control.new();view.add_child(view.item_canvas);view.item_canvas.position=Vector2(328,60);view.item_canvas.size=Vector2(584,612)
	view.item_scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();view.add_child(view.item_scrollbar)
	view.page=[{"group":state.groups[0]},{"id":7}]
	for operation in 4:
		check(view.help_at(Vector2(812+24*operation,78))==["forbid","dump","melt","visibility"][operation],"Group hover hitbox differs")
	for control in 6:
		var expected: String=["recenter","view","forbid","dump","","visibility"][control]
		check(view.help_at(Vector2(764+24*control,114))==expected,"Individual hover eligibility differs")
	state.groups[0].flags=0;check(view.help_at(Vector2(812,78)).is_empty(),"Unavailable group control has hover")
	check(view.help_at(Vector2(764,78)).is_empty() and view.help_at(Vector2(500,78)).is_empty() and view.help_at(Vector2(764,40)).is_empty(),"Blank group/header space has hover")
	state.items={};check(view.help_at(Vector2(812,114)).is_empty(),"Missing item facts have hover")
	var hover=preload("res://scripts/native_hover_view.gd").new();root.add_child(hover);root.add_child(view)
	view.position=Vector2(32,52);view.size=Vector2(944,708)
	view.scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();view.add_child(view.scrollbar)
	view.scrollbar.size=Vector2(16,648);view.scrollbar.page=18;view.scrollbar.set_rows(93)
	view.item_scrollbar.size=Vector2(16,612);view.item_scrollbar.page=51;view.item_scrollbar.set_rows(105)
	await wheel_at(Vector2(100,130));check(view.scrollbar.first==1 and view.item_scrollbar.first==0,"Wheel selects category column")
	await wheel_at(Vector2(100,130),false,true);check(view.scrollbar.first==19,"Shift-wheel pages category rows")
	await wheel_at(Vector2(500,94));check(view.item_scrollbar.first==1,"Wheel over filter scrolls item text cells")
	await wheel_at(Vector2(960,250),false,true);check(view.item_scrollbar.first==52,"Shift-wheel over bar pages item cells")
	await wheel_at(Vector2(600,130),false,true);check(view.item_scrollbar.first==54,"Item wheel clamps to last page")
	await wheel_at(Vector2(600,130),true,true);check(view.item_scrollbar.first==3,"Page-up preserves text-cell units")
	for _step in 4:await wheel_at(Vector2(600,130),true)
	check(view.item_scrollbar.first==0,"Item wheel clamps at top")
	for point in [Vector2(31,250),Vector2(344,250),Vector2(351,250),Vector2(976,250),Vector2(100,47),Vector2(600,760)]:
		await wheel_at(point);check(view.scrollbar.first==19 and view.item_scrollbar.first==0,"Outside or gap wheel changed lists")
	state.phase=State.Phase.Reading;await wheel_at(Vector2(600,130));check(view.item_scrollbar.first==0,"Pending read accepted scroll")
	state.phase=State.Phase.Ready
	view.hover_help=hover;view.pointer_known=true;view.pointer_position=Vector2(812,78);state.groups[0].flags=240
	view._process(0);check(hover.state.key=="item_forbid","Stocks help did not use shared native flag text")
	state.phase=State.Phase.Applying;view._process(0);check(hover.state.key.is_empty(),"Pending mutation retained hover authority")
	state.phase=State.Phase.Ready;view._process(0);view.hide();view._process(0);check(hover.state.key.is_empty(),"Hidden Stocks retained hover")
	var owner:=Owner.new();owner.ui_host=preload("res://tests/work_details_state_test.gd").HostStub.new()
	owner.panel=Control.new();owner.add_child(owner.panel);owner.item_owner=ItemOwnerStub.new();owner.add_child(owner.item_owner)
	owner.state.configure(service);var destinations: Array=[]
	owner.focus_requested.connect(func(tile):destinations.append(tile))
	for inspect in [false,true]:
		ready(owner.state,service);owner.ui_host.activate(owner);owner.state.items={7:item(7)}
		owner.state.navigate(7,inspect);pending=owner.state.ticket
		check(owner.state.phase==State.Phase.Navigating and owner.state.items.is_empty(),"Navigation retained editable rows")
		service.reply(pending,{"production":{"item_position":{"id":7,"position":Vector3i(111,61,165)}}})
		check(owner.state.phase==State.Phase.Closed and not owner.panel.visible and destinations[-1]==Vector3i(111,61,165),"Destination did not close Stocks and focus item")
		check(owner.item_owner.selected==(7 if inspect else -1),"Recenter opened sheet or View lost identity")
	ready(owner.state,service);owner.ui_host.activate(owner);owner.state.items={7:item(7)}
	owner.state.navigate(7,false);pending=owner.state.ticket;owner.close_panel();calls=destinations.size()
	service.reply(pending,{"production":{"item_position":{"id":7,"position":Vector3i(111,61,165)}}})
	check(destinations.size()==calls,"Late navigation moved camera after close")
	owner.free()
	view.free();hover.free();state.dispose();service.queue_free();await process_frame
	if failures==0:print("STOCKS_STATE_PASS")
	quit(1 if failures else 0)
