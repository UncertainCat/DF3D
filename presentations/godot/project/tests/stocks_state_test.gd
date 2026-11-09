extends SceneTree
const View=preload("res://scripts/stocks_view.gd")
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
func run() -> void:
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
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("STOCKS_STATE_PASS")
	quit(1 if failures else 0)
