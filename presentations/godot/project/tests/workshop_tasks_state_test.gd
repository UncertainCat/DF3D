extends SceneTree
const State=preload("res://scripts/workshop_tasks_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Service:
	extends RefCounted
	signal session_changed
	var requests: Array=[]
	var callbacks: Array=[]
	var detached: Array=[]
	func submit(_domain,request,observer):
		requests.append(request);callbacks.append(observer);return requests.size()
	func detach(ticket):detached.append(ticket)
	func reply(ticket,production):
		callbacks[ticket-1].call(ticket,{"status":C.ManagementStatus.Ok,"action":requests[ticket-1].action,"production":production},requests[ticket-1])
var failed:=false
func check(value: bool,message: String) -> void:
	if not value:failed=true;push_error(message)
func page(jobs: Array=[],created: int=-1) -> Dictionary:
	return {"selected_building":4,"recipes":[{"key":"builtin:bed","name":"Make bed"}],"jobs":jobs,"created_job":created}
func _initialize() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service)
	state.open(4);service.reply(1,page())
	state.queue_task("builtin:bed");state.queue_task("builtin:bed")
	check(service.requests.size()==2 and state.jobs().is_empty(),"Pending queue has no optimistic job or duplicate intent")
	var job: Dictionary={"id":42,"name":"Make bed","editable":true,"repeat":false,"suspended":false}
	service.reply(2,page([job],42));check(state.phase==State.Phase.Ready and state.jobs().size()==1,"Adopt confirmed created job")
	state.cancel_task(42);service.reply(3,page())
	check(state.phase==State.Phase.Ready and state.jobs().is_empty(),"Confirm cancellation from returned queue")
	state.queue_task("builtin:bed");service.reply(4,page())
	check(state.phase==State.Phase.Unknown,"Missing creation receipt is unknown")
	state.queue_task("builtin:bed");check(service.requests.size()==4,"Unknown outcome cannot replay")
	state.refresh();state.close();service.reply(5,page([job]))
	check(state.phase==State.Phase.Closed and state.jobs().is_empty() and service.detached==[5],"Closed panel retires its observer")
	state.open(4);service.reply(6,page())
	state.set_query("B");state.set_query("BREW")
	service.reply(7,page([job]))
	check(state.phase==State.Phase.Reading and state.jobs().is_empty(),"Superseded search cannot restore stale choices")
	service.reply(8,page())
	check(state.phase==State.Phase.Ready and service.requests[7].query=="BREW","Latest native search owns choices")
	state.dispose();service.callbacks.clear()
	if not failed:print("WORKSHOP_TASKS_STATE_PASS")
	quit(1 if failed else 0)
