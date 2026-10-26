extends RefCounted
# Read ownership is separate from assignment, so refresh never disables input.
const C = preload("res://scripts/management_contract.gd")
var service
var state
var ticket := 0
var generation := 0
var age := 0.0
var interval := 1.0
var first_row := 0

func configure(source, model) -> void:
	service = source; state = model
	state.changed.connect(clear)
	service.session_changed.connect(clear)

func clear() -> void:
	generation += 1
	if ticket != 0 and service != null: service.detach(ticket)
	ticket = 0; age = 0.0; first_row = 0

func poll(delta: float, first: int) -> void:
	if service == null or state == null or state.kind not in [1,2] or state.busy() or state.receipt == 0 or state.rows.is_empty():
		clear(); return
	first = clampi(first,0,state.rows.size()-1)
	state.retain_owner_recipes(first)
	if first != first_row:
		clear(); first_row = first; age = interval
	age += maxf(delta,0)
	if ticket != 0 or age < interval: return
	age = 0
	var request := {"action":C.ManagementAction.AreaCandidates,"operation":C.AreaOperation.CandidateList,
		"id":int(state.area.id),"kind":1,"candidate_kind":state.kind,"query":state.query,"sort":state.sort,
		"sort_descending":state.descending,"cursor":clampi(first,0,state.rows.size()-1),"expected_list_revision":state.receipt,
		"candidate_limit":18} # 600px viewport: at most18 partially visible36px rows.
	if state.query_bytes is PackedByteArray: request.query_bytes = state.query_bytes.duplicate()
	var version := generation
	ticket = service.submit("areas",request,func(received, result, sent):
		if version != generation or received != ticket: return
		ticket = 0
		if int(result.get("status",-1)) != C.ManagementStatus.Ok:
			state.reject(str(result.get("message",""))); return
		if int(result.get("action",-1)) != C.ManagementAction.AreaCandidates: return
		state.accept_owner_facts(result.get("area",{}),sent))
