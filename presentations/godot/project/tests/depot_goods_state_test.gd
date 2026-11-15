extends SceneTree
const State=preload("res://scripts/depot_goods_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends Node:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,intent: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"intent":intent.duplicate(true),"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket]
		call.observer.call(ticket,{"status":C.ManagementStatus.Ok,"action":call.intent.action,"depot_goods":payload},call.intent)
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func snapshot(category: int=-1) -> Dictionary:
	return {"depot_id":7,"revision":9007199254740993,"category":category,"categories":[{"type":45,"caption":"Synthetic anvils"}],"groups":[] if category==-1 else [{"subtype":-1,"subcat1":0,"subcat2":1,"amount":2,"caption":"Synthetic group","matches":true,"expanded":true,"flags":0,"item_ids":[11,12]}],"items":[]}
func ready(service,state) -> void:
	service.reply(state.ticket,snapshot())
	service.reply(state.ticket,snapshot(45))
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service)
	var state:=State.new();state.configure(service);state.open(7)
	check(service.calls[state.ticket].domain=="depot_goods","Reads use semantic depot domain")
	ready(service,state)
	check(state.phase==State.Phase.Ready and state.revision==9007199254740993,"Catalog selects first native category without losing revision precision")
	check(state.row_count()==3 and state.page(1,2)==[{"id":11},{"id":12}],"Expanded rows retain native membership order")
	check(state.page(2,1)==[{"id":12}] and state.page(3,2).is_empty(),"Viewport bounds omit preceding and trailing rows")
	state.request_items([11]);var intent: Dictionary=service.calls[state.ticket].intent
	check(intent.item_ids==[11] and state.groups.is_empty(),"Detail read retires old source")
	var value:=snapshot(45);value.items=[{"id":11,"caption":"Synthetic item","distance":8,"value":20,"tag":2,"prohibited":false}]
	service.reply(state.ticket,value)
	check(state.items.has(11),"Requested native detail is published")
	var count: int=service.next;state.request_items([11]);state.request_items([999]);state.request_items([12,12])
	check(service.next==count,"Cached, foreign and duplicate detail requests do not submit")
	state.set_query("I");state.set_query("IR");state.set_query("IRON")
	for query in ["I","IR","IRON"]:
		check(service.calls[state.ticket].intent.query==query,"Queued query preserves input order")
		service.reply(state.ticket,snapshot(45))
	check(state.phase==State.Phase.Ready and state.query=="IRON","Search settles after final native response")
	state.set_options(true,true,true);value=snapshot(45);value.categories=[];value.groups[0].item_ids=[]
	service.reply(state.ticket,value)
	check(state.category==45 and state.row_count()==0 and state.page(0,10).is_empty(),"Exclusion retains selected category but native empty-item gate hides groups")
	state.set_query("");var old: int=state.ticket;state.close();service.reply(old,snapshot(45))
	check(service.detached.has(old) and state.phase==State.Phase.Closed and state.groups.is_empty(),"Close retires late replies")
	state.open(7);old=state.ticket;service.session_changed.emit();service.reply(old,snapshot())
	check(state.phase==State.Phase.Unavailable and state.depot_id==-1,"Session replacement retires source ownership")
	state.open(7);ready(service,state);state.request_items([11]);value=snapshot(45)
	service.reply(state.ticket,value)
	check(state.phase==State.Phase.Rejected and state.revision==0 and state.groups.is_empty(),"Missing requested detail rejects without stale data")
	state.open(7);ready(service,state);state.set_query("bad");value=snapshot(45);value.groups[0].item_ids=[11,11]
	service.reply(state.ticket,value)
	check(state.phase==State.Phase.Rejected,"Duplicate membership rejects")
	state.dispose();service.queue_free()
	if failures==0:print("PASS depot goods state")
	quit(1 if failures else 0)
