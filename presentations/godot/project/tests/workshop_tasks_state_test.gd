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
	state.refresh();service.reply(9,page([job]))
	state.toggle_priority(42);check(service.requests.size()==9,"Unknown legacy Priority is not editable")
	job.priority=false;state.refresh();service.reply(10,page([job]))
	state.toggle_priority(42);state.toggle_priority(42)
	check(service.requests.size()==11 and service.requests[10].priority==1 and service.requests[10].expected_priority==0,"Priority submits one observed-state edit")
	var other:=job.duplicate();other.id=43;job.priority=true
	service.reply(11,page([other,job]))
	check(state.phase==State.Phase.Unknown,"Priority flag without native queue move is not confirmed")
	state.toggle_priority(42);check(service.requests.size()==11,"Unconfirmed Priority cannot replay")
	state.dispose();service.callbacks.clear()
	service=Service.new();state=State.new();state.configure(service);state.open(4)
	var root_page:=page([job]);root_page.task_category="";root_page.task_categories=[{"key":"reaction:PARTS","name":"Native category"}]
	service.reply(1,root_page);state.set_query("parts");service.reply(2,root_page)
	state.open_category("reaction:PARTS");state.open_category("reaction:PARTS")
	check(service.requests.size()==3 and service.requests[2].task_category=="reaction:PARTS" and service.requests[2].query=="","Category selection clears search and suppresses duplicates")
	state.reset_picker();service.reply(3,root_page)
	check(state.phase==State.Phase.Reading and state.category.is_empty(),"Retired category reply cannot replace root read")
	service.reply(4,root_page);state.open_category("reaction:PARTS");service.reply(5,root_page)
	check(state.phase==State.Phase.Rejected,"Wrong category echo must not be accepted")
	state.dispose();service.callbacks.clear()
	service=Service.new();state=State.new();state.configure(service);state.open(4)
	root_page.task_categories=[{"key":"opaque-group","name":"Native group"}]
	service.reply(1,root_page);state.open_category("opaque-group")
	var group:=page();group.task_category="opaque-group";group.task_parent="";group.task_categories=[{"key":"opaque-material","name":"Native material"}]
	service.reply(2,group);state.open_category("opaque-material")
	var material:=page();material.task_category="opaque-material";material.task_parent="opaque-group";material.task_categories=[]
	service.reply(3,material);state.set_query("bolt");service.reply(4,material)
	state.go_back();state.go_back()
	check(service.requests.size()==5 and service.requests[4].task_category=="opaque-group" and service.requests[4].query=="","Back uses the observed opaque parent once and clears search")
	service.reply(5,group);state.go_back();service.reply(6,root_page)
	check(state.category.is_empty() and state.parent==null,"Empty Back target returns root; absent parent means Cancel")
	state.go_back();check(service.requests.size()==6,"Cancel context cannot invent a parent")
	state.dispose();service.callbacks.clear()
	if not failed:print("WORKSHOP_TASKS_STATE_PASS")
	quit(1 if failed else 0)
