extends SceneTree
const Model=preload("res://scripts/trade_catalog_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends Node:
	signal session_changed
	var calls: Dictionary={}
	var next:=0
	var detached: Array=[]
	var retired: Array=[]
	func submit(domain: String,intent: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"intent":intent,"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func retire_trade_open(ticket: int) -> void:retired.append(ticket);detach(ticket)
	func reply(ticket: int,value: Dictionary) -> void:
		calls[ticket].observer.call(ticket,{"status":C.ManagementStatus.Ok,"action":C.ManagementAction.TradeCatalogRead,"trade_catalog":value},calls[ticket].intent)
var failed:=false
func check(ok: bool,message: String) -> void:
	if not ok:failed=true;push_error(message)
func snapshot(id: int=7) -> Dictionary:
	return {"depot_id":id,"title":"Synthetic title","from_text":" / ","choices":[{"token":9007199254740993,"entity_id":4,"race":"Synthetic race","name":"Synthetic name"},{"token":9007199254740994,"entity_id":4,"race":"Synthetic race","name":"Synthetic name"}]}
func session_value() -> Dictionary:
	return {"outcome":C.TradeSessionOutcome.Available,"session":9007199254740995,"revision":1,"entry":{"entity_id":4,"fortress_trader":988,"merchant_trader":-1,"dialogue":-1,"unloading":false,"has_speaker":false,"title":"Synthetic entry","speaker":"","fortress":"Synthetic fortress","place":"Synthetic place"}}
func conversation_value() -> Dictionary:
	return {"dialogue":0,"counter_offer":false,"requested_items":[],"announcement":[]}
func header_value() -> Dictionary:
	return {"speaker":-1,"columns":102,"name":"","mood":"","mood_color":-1,"status":[],"status_color":-1,"lines":[]}
func footer_value() -> Dictionary:
	return {"merchant_value":"Value: 10","fortress_value":"Value: 12","profit":"Trader Profit: 2","profit_color":6,"capacity":"Allowed Weight: 100","capacity_color":7}
func session_reply(service,ticket: int,value: Dictionary,extra: Dictionary={}) -> void:
	var call: Dictionary=service.calls[ticket]
	var result: Dictionary={"status":C.ManagementStatus.Ok,"action":call.intent.action,"trade_session":value};result.merge(extra,true)
	call.observer.call(ticket,result,call.intent)
func sessions(service,state) -> void:
	state.open(7);service.reply(state.ticket,snapshot());state.choose(9007199254740994)
	var opened: int=state.ticket
	check(service.calls[opened].intent=={"action":C.ManagementAction.TradeSessionOpen,"depot_id":7,"choice_token":9007199254740994},"Chooser lost exact open intent")
	session_reply(service,opened,session_value())
	check(state.phase==Model.Phase.Active and state.session==9007199254740995 and state.entry.title=="Synthetic entry","Open receipt did not establish session")
	state.refresh_session();var value:=session_value();value.erase("entry");value.footer=footer_value();value.header=header_value();value.conversation=conversation_value();session_reply(service,state.ticket,value)
	check(state.phase==Model.Phase.Active,"Read did not preserve active session")
	state.close();check(service.calls[service.next].intent=={"action":C.ManagementAction.TradeSessionClose,"session":9007199254740995},"Close did not retire known native session")
	state.open(7);var single:=snapshot();single.choices.resize(1);service.reply(state.ticket,single)
	check(state.phase==Model.Phase.Choosing and service.calls[state.ticket].intent.choice_token==9007199254740993,"Single merchant did not enter directly")
	opened=state.ticket;state.close();session_reply(service,opened,session_value())
	check(service.retired.has(opened) and state.phase==Model.Phase.Closed and state.session==0,"Late open resurrected closed chooser")
	state.open(7);service.reply(state.ticket,single);opened=state.ticket
	session_reply(service,opened,{}, {"outcome":"unknown"});state.close()
	check(service.retired.has(opened),"Unknown open lost its eventual retirement obligation")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service=Service.new();root.add_child(service)
	var state=Model.new();state.configure(service)
	var selected: Array=[];state.choice_requested.connect(func(depot,token):selected.append([depot,token]))
	state.open(7);var old: int=state.ticket
	state.close();state.open(8);var current: int=state.ticket
	service.reply(old,snapshot());check(state.ticket==current and state.phase==Model.Phase.Reading and service.detached.has(old),"Old read replaced the current chooser")
	service.reply(current,snapshot(8));check(state.phase==Model.Phase.Ready and state.choices.size()==2,"Duplicate civilization captions must remain separate choices")
	state.choose(4);check(selected.is_empty(),"Entity ID became a choice token")
	state.choose(9007199254740994);state.choose(9007199254740993)
	check(selected==[[8,9007199254740994]] and state.phase==Model.Phase.Choosing,"Exact token must dispatch once without float conversion")
	service.session_changed.emit();check(state.phase==Model.Phase.Unavailable and state.choices.is_empty(),"Session replacement retained choices")
	for kind in ["depot","token","duplicate","float"]:
		state.open(7);var value:=snapshot()
		if kind=="depot":value.depot_id=8
		elif kind=="token":value.choices[0].token=0
		elif kind=="duplicate":value.choices[1].token=value.choices[0].token
		else:value.choices[0].token=1.5
		service.reply(state.ticket,value);check(state.phase==Model.Phase.Rejected and state.choices.is_empty(),"Invalid receipt exposed choices: "+kind)
	state.open(7);old=state.ticket;state.dispose();service.reply(old,snapshot())
	check(state.phase==Model.Phase.Closed and state.choices.is_empty(),"Disposed chooser accepted a late reply")
	state.configure(service);sessions(service,state);state.dispose()
	service.queue_free();await process_frame
	if not failed:print("TRADE_CATALOG_STATE_PASS")
	quit(1 if failed else 0)
