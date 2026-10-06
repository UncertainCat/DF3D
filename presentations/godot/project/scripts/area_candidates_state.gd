extends RefCounted
# Selector reads own their query/order and list receipt; controller owns tickets.
signal request_ready(request: Dictionary)
signal changed
signal failed_page(message: String)
const C = preload("res://scripts/management_contract.gd")
var area: Dictionary = {}
var rows: Array = []
var pending: Dictionary = {}
var receipt := 0
var cursor := 0
var kind := 1
var query := ""
var sort := 0
var descending := false
var delay := -1.0
var search_delay := -1.0
var failed := false
var mutating := false
var squad_mask := 15

func clear() -> void:
	area = {}; rows = []; pending = {}; receipt = 0; cursor = 0
	kind = 1; query = ""; sort = 0; descending = false
	delay = -1; search_delay = -1; failed = false; mutating = false
	squad_mask = 15
	changed.emit()

func open(value: Dictionary, candidate_kind := 1, navigation: Dictionary = {}) -> void:
	clear(); area = value.duplicate(true); kind = candidate_kind
	query = str(navigation.get("query","")); sort = int(navigation.get("sort",0))
	descending = bool(navigation.get("descending",false))
	squad_mask = int(navigation.get("squad_mask",15))
	if int(area.get("kind",-1)) != 1 or int(area.get("revision",0)) <= 0 or kind not in [1,2,3]:
		reject("Inspect this zone before selecting assignments"); return
	read()

func busy() -> bool:
	return area.is_empty() or failed or mutating or not pending.is_empty() or search_delay >= 0

func read(next_cursor := 0) -> void:
	if area.is_empty() or failed or mutating or not pending.is_empty(): return
	pending = {"action":C.ManagementAction.AreaCandidates,"operation":C.AreaOperation.CandidateList,
		"id":int(area.id),"kind":1,"candidate_kind":kind,"query":query,"sort":sort,
		"sort_descending":descending,"cursor":next_cursor}
	if next_cursor != 0: pending.expected_list_revision = receipt
	delay = -1; changed.emit(); request_ready.emit(pending.duplicate(true))

func queue_search(value: String) -> void:
	if area.is_empty() or failed or mutating or value == query: return
	query = value; invalidate(0.25)

func order(value: int) -> void:
	if area.is_empty() or failed or mutating or value not in [0,1,2,3]: return
	descending = not descending if sort == value else false
	sort = value; invalidate(0)

func invalidate(debounce: float) -> void:
	rows = []; receipt = 0; cursor = 0; search_delay = debounce
	# During a builder wait there is no outstanding ticket to retire.
	if delay >= 0: pending = {}; delay = -1
	changed.emit()

func poll(delta: float) -> void:
	if search_delay >= 0:
		search_delay = maxf(0,search_delay-maxf(0,delta))
		if search_delay <= 0.000001 and pending.is_empty() and not mutating and not failed:
			search_delay = -1; read()
		return
	if delay >= 0 and not pending.is_empty():
		delay -= maxf(0,delta)
		if delay <= 0.000001:
			delay = -1; request_ready.emit(pending.duplicate(true))

func accept(page: Dictionary, sent: Dictionary) -> void:
	if pending.is_empty() or sent != pending: return
	if str(sent.query) != query or int(sent.sort) != sort or bool(sent.sort_descending) != descending:
		pending = {}; delay = -1; changed.emit(); return
	for key in ["candidate_kind","query","sort","sort_descending"]:
		if page.get(key,sent[key]) != sent[key]:
			reject("Candidate page changed; refresh"); return
	if int(page.get("list_revision",0)) == 0 or int(page.get("build_done",0)) < int(page.get("build_total",0)):
		delay = 0.25; return
	if int(sent.cursor) != 0 and int(page.list_revision) != receipt:
		reject("List changed; refresh"); return
	if int(sent.cursor) == 0: rows = []
	rows.append_array(page.get("candidates",[]))
	receipt = int(page.list_revision); cursor = int(page.get("next_cursor",0))
	pending = {}; delay = -1; changed.emit()

func more() -> void:
	if not busy() and cursor != 0: read(cursor)

func reject(reason: String) -> void:
	pending = {}; delay = -1; search_delay = -1; failed = true; mutating = false
	changed.emit(); failed_page.emit(reason)

func assign_owner(id: int) -> void:
	if busy() or kind != 1 or not bool(area.get("owner_allowed",false)): return
	var found := id == -1
	for row in rows:
		if int(row.id) == id: found = true
	if not found or id == int(area.get("owner_id",-1)): return
	mutating = true; changed.emit()
	request_ready.emit({"action":C.ManagementAction.AreaUpdate,"id":int(area.id),"kind":1,
		"expected_revision":int(area.revision),"owner_id":id})

func toggle_animal(id: int) -> void:
	if busy() or kind != 2: return
	for row in rows:
		if int(row.id) != id: continue
		mutating = true; changed.emit()
		request_ready.emit({"action":C.ManagementAction.AreaUpdate,"operation":C.AreaOperation.AssignUnits,
			"id":int(area.id),"kind":1,"expected_revision":int(area.revision),
			"unit_id":id,"assign":0 if bool(row.get("assigned",false)) else 1})
		return

func toggle_squad(id: int, bit: int) -> void:
	if busy() or kind != 3 or bit not in [1,2,4,8] or (bit & squad_mask) == 0: return
	for row in rows:
		if int(row.id) != id: continue
		var current := int(row.get("squad_use",-1))
		if current < 0 or (current & ~squad_mask) != 0: return
		mutating = true; changed.emit()
		request_ready.emit({"action":C.ManagementAction.AreaUpdate,"operation":C.AreaOperation.SquadUse,
			"id":int(area.id),"kind":1,"expected_revision":int(area.revision),
			"squad_id":id,"squad_use":current ^ bit})
		return
