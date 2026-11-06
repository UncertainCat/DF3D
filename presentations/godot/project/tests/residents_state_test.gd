extends SceneTree
const State=preload("res://scripts/residents_state.gd")
const View=preload("res://scripts/residents_view.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends RefCounted:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,request: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"request":request.duplicate(true),"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket]
		var result:=payload.duplicate(true);result.status=C.ManagementStatus.Ok;result.action=call.request.action
		call.observer.call(ticket,result,call.request)
var failures:=0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.capacity=2;state.open()
	var stale:=state.ticket
	state.set_query(PackedByteArray([84,195]))
	check(service.detached.has(stale) and service.calls[state.ticket].request.query_bytes==PackedByteArray([84,195]),"Raw textbox bytes survive replacement")
	service.reply(stale,{"residents":{"unit_ids":PackedInt32Array([999])}})
	check(state.ids.is_empty(),"Late superseded roster cannot publish")
	service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42,7,19,3])}})
	var first_batch:=state.ticket
	check(service.calls[first_batch].request.unit_ids==PackedInt32Array([42,7]),"Rows follow native order")
	state.seek(2,2)
	service.reply(first_batch,{"residents_rows":{"rows":[{"id":42},{"id":7}]}})
	check(service.calls[state.ticket].request.unit_ids==PackedInt32Array([19,3]),"Scroll during read fills current viewport next")
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":19},{"id":3}]}})
	check(state.phase==State.Phase.Ready and state.row_at(2).id==19 and state.rows.size()<=4,"Visible rows become ready without reordering")
	state.select_sort(C.ResidentsSort.Name);state.select_sort(C.ResidentsSort.Name)
	state.select_sort(C.ResidentsSort.Activity);state.select_sort(C.ResidentsSort.Name)
	check(state.directions[C.ResidentsSort.Name] and service.calls[state.ticket].request.descending,"Reselecting inactive header retains direction")
	var old:=state.ticket;service.session_changed.emit()
	service.reply(old,{"residents":{"unit_ids":PackedInt32Array([42])}})
	check(state.phase==State.Phase.Unavailable and state.ids.is_empty() and state.rows.is_empty(),"Session retirement rejects late rows")
	state.open();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array()}})
	check(state.phase==State.Phase.Ready and state.ticket==0,"Empty native search requires no content request")
	state.refresh();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42,7])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":7},{"id":42}]}})
	check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Mismatched row receipt cannot acquire identity authority")
	state.refresh();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"specialization":{"only_assigned":false,"revision":91}}]}})
	state.specialize(42);var edit_ticket:=state.ticket
	check(state.phase==State.Phase.Applying and service.calls[edit_ticket].request.only_assigned and service.calls[edit_ticket].request.expected_revision==91,"Specialization uses the displayed receipt")
	state.specialize(42);check(state.ticket==edit_ticket,"Pending edit cannot be repeated")
	service.reply(edit_ticket,{"residents_specialization":{"unit_id":42,"outcome":C.ResidentsSpecializationOutcome.Applied,"only_assigned":true}})
	check(state.phase==State.Phase.Reading and service.calls[state.ticket].request.action==C.ManagementAction.ResidentsQuery,"Successful edit refreshes native rows")
	service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"specialization":{"only_assigned":true,"revision":92}}]}})
	state.specialize(42);edit_ticket=state.ticket;state.close()
	service.reply(edit_ticket,{"residents_specialization":{"unit_id":42,"outcome":C.ResidentsSpecializationOutcome.Applied,"only_assigned":false}})
	check(state.phase==State.Phase.Closed and state.ticket==0 and state.rows.is_empty(),"Late edit completion cannot reopen a closed screen")
	state.dispose()
	var view:=View.new();view.state=state;view.ticks_override=0
	view.search=LineEdit.new();view.add_child(view.search);root.add_child(view)
	view.size=Vector2(944,708);view.page_rows=2
	var inspected: Array[int]=[]
	var focused: Array[Vector3i]=[]
	view.inspect_requested.connect(func(id):inspected.append(id))
	view.focus_requested.connect(func(tile):focused.append(tile))
	state.ids=PackedInt32Array([7,42]);state.rows={7:{"id":7},42:{"id":42,"position":Vector3i(25,31,4)}};state.first=1;state.phase=State.Phase.Ready
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=Vector2(348,view.list_top()+18);view._gui_input(click)
	check(inspected==[42],"Details uses the scrolled row identity")
	click.position.x=316;view._gui_input(click)
	check(focused==[Vector3i(25,31,4)],"Recenter uses the captured row position")
	state.close();view._gui_input(click)
	check(inspected==[42] and focused==[Vector3i(25,31,4)],"Closed rows cannot navigate using retired identity")
	view.free()
	if failures==0:print("RESIDENTS_STATE_PASS")
	quit(1 if failures else 0)
