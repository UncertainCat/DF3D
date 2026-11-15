extends SceneTree
const C=preload("res://scripts/management_contract.gd")
class Service:
	extends RefCounted
	signal session_changed
	var next:=0
	var requests: Dictionary={}
	var detached: Array=[]
	func submit(domain,intent,observer):
		next+=1;requests[next]={"domain":domain,"intent":intent.duplicate(true),"observer":observer};return next
	func detach(ticket):detached.append(ticket)
	func reply(ticket,value):requests[ticket].observer.call(ticket,value,requests[ticket].intent)
func _initialize() -> void:call_deferred("run")
var failed:=false
func check(value: bool,message: String) -> void:
	if not value:failed=true;push_error(message)
func page(receipt: int,kind: int,rows: Array) -> Dictionary:
	return {"action":C.ManagementAction.SelectionArtRead,"status":C.ManagementStatus.Ok,"selection_art":{"receipt":receipt,"revision":91,"art":{"page":kind,"rows":rows,"caption":"Reference","total":rows.size(),"next_cursor":0,"list_revision":0 if kind==-1 else 92}}}
func run() -> void:
	var service:=Service.new();var state=preload("res://scripts/selection_art_state.gd").new();state.configure(service)
	state.open_selection(41);var first: int=state.ticket
	check(service.requests[first].domain=="selection_art" and service.requests[first].intent.receipt==41,"Wrong artwork owner")
	service.reply(first,page(41,-1,[{"id":2,"caption":"Site"}]))
	check(state.phase==state.Phase.Ready,"Root not ready")
	state.choose(2);var read: int=state.ticket
	check(service.requests[read].intent.expected_revision==91 and service.requests[read].intent.art.page==2,"Site read lost revision")
	service.reply(read,page(41,2,[{"id":320,"caption":"Site"}]))
	state.choose(320);var edit: int=state.ticket
	check(service.requests[edit].intent.action==C.ManagementAction.SelectionArtApply and service.requests[edit].intent.art.expected_list_revision==92,"Site edit lost list authority")
	service.reply(edit,{"outcome":"unknown","status":C.ManagementStatus.Rejected})
	check(state.phase==state.Phase.Unknown,"Unknown edit became retryable")
	var count:=service.next;state.read_root();check(service.next==count,"Unknown edit was replayed")
	state.close();state.open_selection(42);read=state.ticket;state.close()
	service.reply(read,page(42,-1,[]));check(state.phase==state.Phase.Closed and state.snapshot.is_empty(),"Late read reopened picker")
	state.open_selection(43);read=state.ticket;service.session_changed.emit()
	service.reply(read,page(43,-1,[]));check(state.selection_receipt==0 and state.phase==state.Phase.Closed,"Session replacement retained artwork owner")
	state.dispose()
	if not failed:print("SELECTION_ART_STATE_PASS")
	quit(1 if failed else 0)
