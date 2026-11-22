extends SceneTree
const State=preload("res://scripts/display_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func receipt(category: int=-1,inventory: int=9007199254740993,outcome: int=C.DisplayOutcome.Available) -> Dictionary:
	var categories: Array=[]
	if category>=0:
		for type in 93:categories.append({"type":type,"matches":true})
	return {"display":{"building_id":1490,"category":category,"revision":9007199254740995,"inventory_revision":inventory if category>=0 else 0,"outcome":outcome,"body":[],"categories":categories,"groups":[{"type":category,"subtype":-1,"subcat1":0,"subcat2":0,"matches":true,"expanded":true,"item_ids":[7,8]}] if category>=0 else [],"items":[]}}
func ready(state,service) -> void:
	state.open(1490);service.reply(state.ticket,receipt());state.open_picker();service.reply(state.ticket,receipt(39))
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service=Service.new();root.add_child(service)
	var state=State.new();state.configure(service);ready(state,service)
	var before: int=service.next
	state.toggle_item(8);state.toggle_item(7)
	check(service.next==before and state.selected.size()==2,"Draft toggles must remain local")
	state.select_category(37);service.reply(state.ticket,receipt(37))
	check(state.selected.size()==2,"Category changes lost draft")
	state.finish_picker()
	check(service.calls[state.ticket].intent.selected_ids==[7,8],"Commit requires sorted cross-category draft")
	check(service.calls[state.ticket].intent.expected_revision==9007199254740993,"Inventory revision lost precision")
	var pending: int=state.ticket;state.finish_picker()
	check(state.ticket==pending,"Pending commit replayed")
	service.reply(pending,{"outcome":"unknown"})
	check(state.phase==State.Phase.Unknown,"Unknown commit became definite failure")
	before=service.next;state.finish_picker();check(before==service.next,"Unknown commit replayed")
	ready(state,service);state.toggle_item(7);state.request_items([7]);service.reply(state.ticket,receipt(39,9007199254740997))
	check(state.phase==State.Phase.Stale,"Changed inventory silently rebound draft")
	before=service.next;state.finish_picker();check(before==service.next,"Stale draft committed")
	ready(state,service);state.select_category(37);pending=state.ticket;state.close();service.reply(pending,receipt(37))
	check(state.phase==State.Phase.Closed and state.building_id==-1,"Late reply revived retired target")
	ready(state,service);state.toggle_item(7);service.session_changed.emit()
	check(state.selected.is_empty() and state.phase==State.Phase.Unavailable,"Session replacement retained draft")
	ready(state,service);state.toggle_item(7);state.finish_picker();service.reply(state.ticket,receipt(-1,0,C.DisplayOutcome.Applied))
	check(state.phase==State.Phase.Ready and state.category==-1 and state.selected.is_empty(),"Commit receipt failed to return to parent")
	state.dispose();service.queue_free();await process_frame
	print("DISPLAY_STATE_PASS" if failures==0 else "DISPLAY_STATE_FAIL")
	quit(0 if failures==0 else 1)
