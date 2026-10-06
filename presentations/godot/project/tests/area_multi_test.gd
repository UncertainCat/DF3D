extends SceneTree
const State = preload("res://scripts/area_multi_state.gd")
const Contract = preload("res://scripts/management_contract.gd")
const Op = Contract.AreaOperation
const Outcome = Contract.AreaRoomOutcome
var failures := 0
func check(value: bool, description: String) -> void:
	if not value: failures += 1; push_error(description)
func reply(request: Dictionary, created := 129, token := 9007199254740993) -> Dictionary:
	var create := int(request.operation) == Op.MultiCreate
	return {"action":request.action,"status":Contract.ManagementStatus.Ok,"area":{
		"operation":request.operation,"interaction_id":request.interaction_id,"room_outcome":Outcome.Completed,
		"undo_token":token if create else 0,"rooms_created":created if create else 0,
		"rooms_in_use":7 if create else 0,"rooms_unenclosed":3 if create else 0,"rooms_removed":0 if create else 129,
		"rooms_dormitories":mini(7,created) if create else 0}}
func select(state) -> Dictionary:
	return state.selection(Vector3i(511,511,4),Vector3i(0,0,4))
func _initialize() -> void:
	var state := State.new()
	check(state.open(1,Vector2i(512,512)),"bed interaction opens")
	var request := select(state)
	check(request.origin == Vector3i(0,0,4) and request.width == 512 and request.height == 512,"full furniture selection exceeds paint limits and normalizes corners")
	check(request.operation == Op.MultiCreate and request.room_furniture == 1 and not request.has("spans"),"selection dispatches native discovery directly")
	check(select(state).is_empty() and state.undo().is_empty(),"pending operation cannot duplicate or overlap")
	check(state.accept(reply(request),request),"native complete result accepted")
	check(state.undo_token == 9007199254740993 and state.observed.rooms_created == 129,"whole-set receipt and counts preserve exact identity")
	check(state.observed.rooms_dormitories == 7,"native Dormitory count is preserved separately")
	var undo := state.undo()
	check(undo.undo_token == 9007199254740993 and undo.interaction_id == request.interaction_id,"Undo uses exact scoped token")
	check(state.accept(reply(undo),undo) and state.undo_token == 0,"Undo consumes latest set once")
	check(state.observed.rooms_removed == 129,"native removal count retained")
	check(state.undo().is_empty(),"repeated Undo cannot delete an older set")
	# Empty, all-in-use and all-unenclosed are successful empty native results.
	for counts in [[0,0],[7,0],[0,3]]:
		request = select(state); state.accept(reply(request),request)
		request = select(state)
		var empty := reply(request,0,0)
		empty.area.rooms_in_use = counts[0]; empty.area.rooms_unenclosed = counts[1]
		check(state.accept(empty,request) and state.undo_token == 0,"empty/rejected native selection replaces old history")
		check(state.observed.rooms_in_use == counts[0] and state.observed.rooms_unenclosed == counts[1],"rejection counts remain authoritative")
		check(state.has_result() == (counts[0]+counts[1] > 0),"empty selection returns initial panel; rejected selection shows native result")
		check(state.undo().is_empty() and state.observed.is_empty(),"Undo after rejected-only selection resets panel without a deletion request")
	request = select(state); state.accept(reply(request),request)
	var unsent := select(state)
	check(state.accept({"outcome":"not_sent"},unsent) and state.undo_token == 9007199254740993,"cancelled unsent selection retains preceding authority")
	request = select(state)
	var finish := state.finish()
	check(finish.operation == Op.MultiFinish and finish.interaction_id == request.interaction_id,"Done can queue after a sent selection")
	check(not state.accept(reply(request),request) and state.undo_token == 0,"late create cannot restore closed authority")
	state.open(1,Vector2i(512,512))
	var next := select(state)
	check(next.interaction_id > request.interaction_id,"reopen never reuses interaction")
	check(not state.accept(reply(request),request) and state.pending == next,"foreign old reply cannot consume newer pending request")
	check(state.accept(reply(next),next),"current result still completes")
	for native_unknown in [false,true]:
		request = select(state)
		var unknown := reply(request)
		if native_unknown:
			unknown.status = Contract.ManagementStatus.Rejected; unknown.area.room_outcome = Outcome.Unknown; unknown.area.undo_token = 0
		else: unknown = {"outcome":"unknown"}
		check(not state.accept(unknown,request) and state.stopped and state.undo_token == 0,"unknown outcome retires authority")
		check(select(state).is_empty() and state.undo().is_empty(),"unknown cannot replay selection or Undo")
		state.open(1,Vector2i(512,512))
	for outcome in [Outcome.Rejected,Outcome.Stale]:
		request = select(state); state.accept(reply(request),request); undo = state.undo()
		var rejected := reply(undo); rejected.status = Contract.ManagementStatus.Rejected; rejected.area.room_outcome = outcome
		rejected.area.rooms_removed = 0
		check(state.accept(rejected,undo) and state.undo().is_empty(),"stale/rejected Undo has no fallback history")
		check(state.ready(),"fresh explicit selection allowed after known rejection")
	for defect in range(4):
		state.open(1,Vector2i(512,512)); request = select(state)
		var invalid := reply(request)
		if defect == 0: invalid.area.interaction_id += 1
		if defect == 1: invalid.area.undo_token = 0
		if defect == 2: invalid.area.room_outcome = Outcome.None
		if defect == 3: invalid.status = Contract.ManagementStatus.Rejected
		check(not state.accept(invalid,request) and state.stopped,"malformed matching result cannot grant authority")
	state.open(4,Vector2i(32768,32768))
	check(not state.selection(Vector3i(0,0,32767),Vector3i(32767,32767,32767)).is_empty(),"full coordinate domain supported")
	state.clear(); check(state.interaction_id == 0 and state.pending.is_empty() and state.undo_token == 0,"session reset clears local authority")
	state.open(4,Vector2i(512,512))
	for pair in [[Vector3i(-1,0,4),Vector3i(0,0,4)],[Vector3i(0,0,4),Vector3i(512,0,4)],[Vector3i(0,0,4),Vector3i(0,0,5)]]:
		check(state.selection(pair[0],pair[1]).is_empty() and state.ready(),"invalid selection cannot change pending state")
	var another := State.new()
	check(another.open(1,Vector2i(1,1)) and another.interaction_id > state.interaction_id,"recreated controllers cannot reuse interaction identity")
	State._next_interaction = 9223372036854775807
	check(state.open(1,Vector2i(1,1)) and state.interaction_id == 9223372036854775807,"last positive identity supported")
	check(not state.open(1,Vector2i(1,1)) and state.interaction_id == 0,"identity exhaustion refuses wrap")
	print("AREA_MULTI PASS" if failures == 0 else "AREA_MULTI FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
