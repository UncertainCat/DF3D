extends SceneTree
const Model=preload("res://scripts/trade_catalog_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends Node:
	signal session_changed
	var calls: Dictionary={}
	var next:=0
	var detached: Array=[]
	func submit(domain: String,intent: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"intent":intent,"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,value: Dictionary) -> void:
		calls[ticket].observer.call(ticket,{"status":C.ManagementStatus.Ok,"action":C.ManagementAction.TradeCatalogRead,"trade_catalog":value},calls[ticket].intent)
var failed:=false
func check(ok: bool,message: String) -> void:
	if not ok:failed=true;push_error(message)
func snapshot(id: int=7) -> Dictionary:
	return {"depot_id":id,"title":"Synthetic title","from_text":" / ","choices":[{"token":9007199254740993,"entity_id":4,"race":"Synthetic race","name":"Synthetic name"},{"token":9007199254740994,"entity_id":4,"race":"Synthetic race","name":"Synthetic name"}]}
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
	service.queue_free();await process_frame
	if not failed:print("TRADE_CATALOG_STATE_PASS")
	quit(1 if failed else 0)
