extends SceneTree
const State=preload("res://scripts/work_details_state.gd")
const C=preload("res://scripts/management_contract.gd")
const A=C.ManagementAction
class Service extends RefCounted:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,intent: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"intent":intent.duplicate(true),"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket];var result:=payload.duplicate(true)
		if not result.has("status"):result.status=C.ManagementStatus.Ok
		result.action=call.intent.action;call.observer.call(ticket,result,call.intent)
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func detail(index: int,revision: int=9007199254740993) -> Dictionary:
	return {"index":index,"revision":revision,"name":"Synthetic detail","editable":true,"mode_editable":true,"mode":3,"assigned_units":PackedInt32Array([7]),"cannot_be_everybody":false}
func page(rows: Array,revision: int=9007199254740995,next: int=0) -> Dictionary:
	return {"citizen":{"details":rows,"detail_list_revision":revision,"next_cursor":next,"external_controller":false}}
func workers(ids: Array) -> Dictionary:return {"residents":{"unit_ids":PackedInt32Array(ids)}}
func complete_workers(service,state,ids: Array) -> void:
	service.reply(state.ticket,workers(ids))
	if state.ticket!=0 and service.calls[state.ticket].intent.action==A.WorkDetailRowsRead:
		var page: Array=[]
		for id in service.calls[state.ticket].intent.unit_ids:page.append({"id":id,"skills":[],"member":id==7})
		service.reply(state.ticket,{"residents_rows":{"rows":page}})
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page([detail(0)],9007199254740995,1))
	check(state.details.is_empty() and service.calls[state.ticket].intent.expected_list_revision==9007199254740995,"List pages retain exact receipt and publish atomically")
	service.reply(state.ticket,page([detail(1)],9007199254740995))
	var old:=state.ticket
	check(service.calls[old].intent.expected_revision==9007199254740993,"Selected worker query uses exact detail revision")
	state.select_detail(1);service.reply(old,workers([999]))
	check(state.ids.is_empty() and state.selected.index==1 and service.detached.has(old),"Late query cannot replace another detail")
	complete_workers(service,state,[42,7,19])
	check(state.ids==PackedInt32Array([42,7,19]),"Native worker order is retained")
	state.seek(1,2);check(state.first==1 and state.capacity==2,"Local viewport follows native IDs")
	state.set_query(PackedByteArray([84,195]));old=state.ticket
	check(service.calls[old].intent.query_bytes==PackedByteArray([84,195]),"Partial UTF8 search survives unchanged")
	state.select_sort(C.WorkDetailWorkerSort.Name);service.reply(old,workers([999]))
	complete_workers(service,state,[7,42])
	state.select_sort(C.WorkDetailWorkerSort.Name);state.select_sort(C.WorkDetailWorkerSort.Skills);state.select_sort(C.WorkDetailWorkerSort.Name)
	check(service.calls[state.ticket].intent.descending,"Each header retains its direction")
	complete_workers(service,state,[7,42])
	state.set_member(42,true);old=state.ticket
	check(state.phase==State.Phase.Applying and service.calls[old].intent.unit_id==42 and service.calls[old].intent.expected_revision==9007199254740993,"Membership uses selected detail authority")
	state.set_member(42,true);state.select_detail(0);state.set_mode(2);state.create_detail()
	check(state.ticket==old,"Pending action blocks duplicate and conflicting inputs")
	service.reply(old,{"citizen":{"selected_detail":1}})
	check(service.calls[state.ticket].intent.action==A.WorkDetailList and state.details.is_empty(),"Applied membership refreshes all header receipts")
	service.reply(state.ticket,page([detail(0,11),detail(1,12)],13));complete_workers(service,state,[7,42])
	state.set_mode(1);old=state.ticket
	check(service.calls[old].intent.expected_revision==12 and service.calls[old].intent.mode==1,"Mode uses refreshed authority")
	service.reply(old,{"status":C.ManagementStatus.Rejected,"outcome":"unknown"})
	var count:=service.next;state.create_detail();state.set_mode(1)
	check(state.phase==State.Phase.Rejected and service.next==count and state.selected.is_empty(),"Unknown mutation has no automatic replay or reusable receipt")
	state.open();old=state.ticket;state.close();service.reply(old,page([detail(0)]))
	check(state.phase==State.Phase.Closed and state.details.is_empty(),"Closed owner ignores late list")
	state.open();service.reply(state.ticket,page([]));state.create_detail();old=state.ticket
	check(service.calls[old].intent.action==A.WorkDetailCreate and service.calls[old].intent.expected_revision==9007199254740995,"Empty list can create using list receipt")
	service.reply(old,{"citizen":{"selected_detail":0}});service.reply(state.ticket,page([detail(0)]));complete_workers(service,state,[])
	check(state.phase==State.Phase.Ready and state.ids.is_empty(),"Empty worker list is valid")
	state.refresh();service.reply(state.ticket,page([detail(0)],10,1));service.reply(state.ticket,page([detail(1)],11))
	check(state.phase==State.Phase.Rejected and state.details.is_empty(),"Changed paginated list cannot publish mixed identities")
	state.open();service.reply(state.ticket,page([detail(0)]));old=state.ticket;service.session_changed.emit();service.reply(old,workers([7]))
	check(state.phase==State.Phase.Unavailable and state.ids.is_empty() and state.list_revision==0,"Session retirement clears all authority")
	state.open();service.reply(state.ticket,page([detail(0)]));service.reply(state.ticket,workers([7,42]))
	old=state.ticket
	check(service.calls[old].intent.expected_revision==9007199254740993 and service.calls[old].intent.unit_ids==PackedInt32Array([7,42]),"Visible row request carries exact selected authority and native order")
	state.set_query(PackedByteArray([88]));service.reply(old,{"residents_rows":{"rows":[{"id":7,"skills":[],"member":true},{"id":42,"skills":[],"member":false}]}})
	check(state.rows.is_empty(),"Late content cannot repopulate replaced query")
	service.reply(state.ticket,workers([7,42]));service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"skills":[],"member":false},{"id":7,"skills":[],"member":true}]}})
	check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Reordered content cannot acquire row authority")
	state.dispose()
	if failures==0:print("WORK_DETAILS_STATE_PASS")
	quit(0 if failures==0 else 1)
