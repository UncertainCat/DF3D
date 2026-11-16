extends "res://tests/trade_catalog_state_test.gd"
const Goods=preload("res://scripts/trade_goods_state.gd")
func page_value(side: int,query: String="",selected: bool=false,total: int=1,offset: int=0) -> Dictionary:
	var rows: Array=[]
	for index in range(offset,total):rows.append({"group":false,"expanded":true,"id":992+side*100+index,"parent":-1,"type":1,"subtype":-1,"amount":0,"flags":1 if selected else 0,"caption":"Synthetic item","value":10,"appraisal":1,"value_caption":"10","weight_caption":"1","disposition":0,"contained_count":0,"expandable":false,"contents_caption":""})
	return {"side":side,"offset":offset,"total":total,"query":query,"rows":rows}
func draft_reply(service,state,page: Dictionary={},revision: int=-1,extra: Dictionary={},finish_summary: bool=true) -> void:
	var call: Dictionary=service.calls[state.ticket]
	var value: Dictionary={"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":state.revision if revision<0 else revision}
	if not page.is_empty():value.page=page
	var result: Dictionary={"status":C.ManagementStatus.Ok,"action":call.intent.action,"trade_draft":value};result.merge(extra,true)
	call.observer.call(state.ticket,result,call.intent)
	if finish_summary and state.ticket>0 and service.calls[state.ticket].intent.action==C.ManagementAction.TradeSessionRead:
		session_reply(service,state.ticket,{"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":state.revision,"footer":footer_value(),"header":header_value(),"actions":actions_value(),"conversation":conversation_value()})
func open_goods(service,state) -> void:
	state.open(7);var single:=snapshot();single.choices.resize(1);service.reply(state.ticket,single);session_reply(service,state.ticket,session_value())
	check(state.phase==Goods.Phase.GoodsReading,"Open did not request goods")
	draft_reply(service,state,page_value(0));check(state.pages==[{},{}],"Half-loaded goods became visible")
	draft_reply(service,state,page_value(1),-1,{},false)
	check(state.pages==[{},{}] and not state.goods_ready(),"Goods appeared before their footer")
	session_reply(service,state.ticket,{"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":state.revision,"footer":footer_value(),"header":header_value(),"actions":actions_value(),"conversation":conversation_value()})
	check(state.goods_ready() and state.footer==footer_value() and state.header==header_value(),"Goods and footer did not become ready together")
func run() -> void:
	var service=Service.new();root.add_child(service)
	var state=Goods.new();state.configure(service);open_goods(service,state)
	for malformed in [{}, {"columns":40}]:
		var retained: Array=state.pages.duplicate(true)
		state.read_page(0,0,64);draft_reply(service,state,page_value(0));draft_reply(service,state,page_value(1),-1,{},false)
		var reply: Dictionary={"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":state.revision,"footer":footer_value()}
		if not malformed.is_empty():reply.header=header_value();reply.header.columns=malformed.columns
		session_reply(service,state.ticket,reply)
		check(state.phase==Goods.Phase.Rejected and state.pages==retained and not state.goods_ready(),"Missing or wrong-width header activated goods")
		state.close();open_goods(service,state)
	var original: Array=state.pages.duplicate(true)
	state.toggle_row(0,0);var pending: int=state.ticket;state.toggle_row(0,0)
	check(state.ticket==pending and service.calls[pending].intent=={"action":C.ManagementAction.TradeDraftApply,"session":9007199254740995,"expected_revision":1,"side":0,"operation":C.TradeDraftOperation.Item,"item":992},"Double click or wide identity corrupted intent")
	draft_reply(service,state,{},2);draft_reply(service,state,page_value(0,"",true))
	check(state.pages==original and state.revision==2 and not state.goods_ready(),"Mutation exposed mixed draft revisions")
	draft_reply(service,state,page_value(1));check(state.goods_ready() and state.pages[0].rows[0].flags==1,"Confirmed selection was not refreshed")
	state.set_filter(0,"I");state.set_filter(0,"IR");state.set_filter(0,"IRON")
	draft_reply(service,state,{},3);draft_reply(service,state,page_value(0,"I"));draft_reply(service,state,page_value(1))
	check(state.phase==Goods.Phase.Applying and service.calls[state.ticket].intent.query=="IRON","Typing while pending lost the latest explicit filter")
	draft_reply(service,state,{},4);draft_reply(service,state,page_value(0,"IRON"));draft_reply(service,state,page_value(1))
	check(state.goods_ready() and state.revision==4,"Queued filter did not settle")
	# Malformed identity/revision keeps old content disabled, without retry.
	state.mark_all(1,true);pending=state.ticket;draft_reply(service,state,{},8)
	check(state.phase==Goods.Phase.Rejected and state.revision==4 and service.next==pending,"Mismatched mutation receipt became authority")
	state.close();check(service.calls[service.next].intent.action==C.ManagementAction.TradeSessionClose,"Rejected draft lost exact session cleanup")
	open_goods(service,state);state.mark_all(1,true);pending=state.ticket
	draft_reply(service,state,{},-1,{"outcome":"unknown"});state.mark_all(1,true)
	check(state.phase==Goods.Phase.Unknown and service.next==pending,"Unknown mutation was retried")
	state.close();open_goods(service,state);state.toggle_row(0,0);pending=state.ticket
	var old: Dictionary=service.calls[pending];state.close();open_goods(service,state)
	var current: Array=state.pages.duplicate(true)
	old.observer.call(pending,{"status":C.ManagementStatus.Ok,"action":C.ManagementAction.TradeDraftApply,"trade_draft":{"outcome":C.TradeSessionOutcome.Available,"session":9007199254740995,"revision":2}},old.intent)
	check(state.goods_ready() and state.revision==1 and state.pages==current and service.detached.has(pending),"Late mutation replaced reopened goods")
	state.exchange();pending=state.ticket;state.exchange()
	check(state.phase==Goods.Phase.Exchanging and state.ticket==pending and service.calls[pending].intent.action==C.ManagementAction.TradeSessionExchange,"Duplicate exchange was submitted")
	session_reply(service,pending,{"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":2})
	draft_reply(service,state,page_value(0));draft_reply(service,state,page_value(1),-1,{},false)
	var counter:=conversation_value();counter.counter_offer=true;counter.dialogue=24;counter.requested_items=[992]
	session_reply(service,state.ticket,{"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":2,"footer":footer_value(),"header":header_value(),"actions":actions_value(),"conversation":counter})
	check(not state.goods_ready() and state.conversation!=counter,"Counteroffer summary published before its page")
	var counter_page:=page_value(2);counter_page.rows[0].id=992;counter_page.rows[0].expanded=false
	counter_page.heading=["Synthetic heading","Synthetic second line"];counter_page.dismiss="Synthetic Okay"
	draft_reply(service,state,counter_page)
	check(state.goods_ready() and state.conversation==counter and state.counter_page==counter_page,"Exchange conversation was not published with refreshed goods")
	state.dismiss_counteroffer();pending=state.ticket;state.dismiss_counteroffer()
	check(service.calls[pending].intent.action==C.ManagementAction.TradeSessionDismiss and state.ticket==pending,"Duplicate Okay submitted")
	session_reply(service,pending,{"outcome":C.TradeSessionOutcome.Available,"session":state.session,"revision":3})
	draft_reply(service,state,page_value(0));draft_reply(service,state,page_value(1))
	check(state.goods_ready() and state.counter_page.is_empty() and state.revision==3,"Okay did not refresh and clear the pane")
	state.exchange();pending=state.ticket
	session_reply(service,pending,{"outcome":C.TradeSessionOutcome.Unknown,"session":0,"revision":0},{"outcome":"unknown"})
	state.exchange();check(state.phase==Goods.Phase.Unknown and state.ticket==0 and service.next==pending,"Uncertain exchange was replayed")
	state.close();check(state.phase==Goods.Phase.Closed and state.conversation.is_empty(),"Uncertain exchange could not close")
	open_goods(service,state)
	service.session_changed.emit();check(state.phase==Goods.Phase.Unavailable and state.pages==[{},{}],"Epoch replacement retained goods")
	state.dispose();service.queue_free();await process_frame
	if not failed:print("TRADE_GOODS_STATE_PASS")
	quit(1 if failed else 0)
