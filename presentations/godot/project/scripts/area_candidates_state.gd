extends RefCounted
# Selector reads own their query/order and list receipt; controller owns tickets.
signal request_ready(request: Dictionary)
signal changed
signal facts_changed
signal failed_page(message: String)
const C = preload("res://scripts/management_contract.gd")
var area: Dictionary = {}
var rows: Array = []
var pending: Dictionary = {}
var receipt := 0
var cursor := 0
var kind := 1
var query := ""
var query_bytes: Variant = null
var sort := 0
var descending := false
var sort_directions: Array = [false,false,false,false,false]
var delay := -1.0
var search_delay := -1.0
var failed := false
var mutating := false
var squad_mask := 15
var recipe_first := 0
const OWNER_RECIPE_ROWS := 36

func clear() -> void:
	area = {}; rows = []; pending = {}; receipt = 0; cursor = 0
	kind = 1; query = ""; query_bytes = null; sort = 0; descending = false
	sort_directions = [false,false,false,false,false]
	delay = -1; search_delay = -1; failed = false; mutating = false
	squad_mask = 15
	recipe_first = 0
	changed.emit()

func open(value: Dictionary, candidate_kind := 1, navigation: Dictionary = {}) -> void:
	clear(); area = value.duplicate(true); kind = candidate_kind
	query = str(navigation.get("query","")); sort = int(navigation.get("sort",2 if kind == 1 else 0))
	query_bytes = navigation.get("query_bytes") if kind == 1 else null
	if query_bytes is PackedByteArray: query_bytes = query_bytes.duplicate(); query = ""
	if kind == 1 and sort == 0: sort = 2
	descending = bool(navigation.get("descending",false))
	if navigation.get("sort_directions") is Array and navigation.sort_directions.size() == 5:
		sort_directions = navigation.sort_directions.duplicate()
	if kind == 1 and sort in [1,2,3,4]: sort_directions[sort] = descending
	squad_mask = int(navigation.get("squad_mask",15))
	if int(area.get("kind",-1)) != 1 or int(area.get("revision",0)) <= 0 or kind not in [1,2,3]:
		reject("Inspect this zone before selecting assignments"); return
	read()

func busy() -> bool:
	return area.is_empty() or failed or mutating or not pending.is_empty() or search_delay >= 0 or (kind == 1 and cursor != 0)

func read(next_cursor := 0) -> void:
	if area.is_empty() or failed or mutating or not pending.is_empty(): return
	pending = {"action":C.ManagementAction.AreaCandidates,"operation":C.AreaOperation.CandidateList,
		"id":int(area.id),"kind":1,"candidate_kind":kind,"query":query,"sort":sort,
		"sort_descending":descending,"cursor":next_cursor}
	if query_bytes is PackedByteArray: pending.query_bytes = query_bytes.duplicate()
	if next_cursor != 0: pending.expected_list_revision = receipt
	delay = -1; changed.emit(); request_ready.emit(pending.duplicate(true))

func queue_search(value: String) -> void:
	if area.is_empty() or failed or mutating or (value == query and query_bytes == null): return
	query = value; query_bytes = null; invalidate(0.25)

func queue_owner_search(value: PackedByteArray) -> void:
	if kind != 1 or area.is_empty() or failed or mutating or value.size() > 33 or value == query_bytes: return
	query = ""; query_bytes = value.duplicate(); invalidate(0.25)

func order(value: int) -> void:
	if area.is_empty() or failed or mutating: return
	if kind == 1:
		if value not in [1,2,3,4]: return
		if sort == value: sort_directions[value] = not bool(sort_directions[value])
		descending = bool(sort_directions[value])
	else:
		if value not in [0,1,2,3]: return
		descending = not descending if sort == value else false
	sort = value; invalidate(0)

func sort_direction(value: int) -> bool:
	return bool(sort_directions[value]) if kind == 1 and value in [1,2,3,4] else descending

func invalidate(debounce: float) -> void:
	rows = []; receipt = 0; cursor = 0; search_delay = debounce
	recipe_first = 0
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

	# Owner scrollbar extent and navigation require complete retained membership.
	# Keep transport pages bounded; fetch the next page on the next controller tick.
	if kind == 1 and cursor != 0 and pending.is_empty(): more()

func accept(page: Dictionary, sent: Dictionary) -> void:
	if pending.is_empty() or sent != pending: return
	if sent.get("query_bytes") != query_bytes or str(sent.query) != query or int(sent.sort) != sort or bool(sent.sort_descending) != descending:
		pending = {}; delay = -1; changed.emit(); return
	if sent.has("query_bytes") and page.get("query_bytes") != sent.query_bytes:
		reject("Candidate page changed; refresh"); return
	for key in ["candidate_kind","query","sort","sort_descending"]:
		if page.get(key,sent[key]) != sent[key]:
			reject("Candidate page changed; refresh"); return
	if int(page.get("list_revision",0)) == 0 or int(page.get("build_done",0)) < int(page.get("build_total",0)):
		delay = 0.25; return
	if int(sent.cursor) != 0 and int(page.list_revision) != receipt:
		reject("List changed; refresh"); return
	if int(sent.cursor) == 0: rows = []
	rows.append_array(page.get("candidates",[]))
	_trim_owner_recipes()
	receipt = int(page.list_revision); cursor = int(page.get("next_cursor",0))
	pending = {}; delay = -1; changed.emit()

func more() -> void:
	if cursor != 0 and search_delay < 0: read(cursor)

func accept_owner_facts(page: Dictionary, sent: Dictionary) -> void:
	if busy() or kind != 1 or receipt == 0 or int(sent.get("expected_list_revision",0)) != receipt: return
	if int(sent.get("id",-1)) != int(area.id) or sent.get("query_bytes") != query_bytes: return
	if str(sent.get("query","")) != query or int(sent.get("sort",-1)) != sort or bool(sent.get("sort_descending")) != descending: return
	if int(page.get("operation",-1)) != C.AreaOperation.CandidateList or int(page.get("list_revision",0)) != receipt: return
	for key in ["candidate_kind","query","sort","sort_descending"]:
		if page.get(key) != sent.get(key): return
	if page.get("query_bytes") != sent.get("query_bytes"): return
	var first := int(sent.get("cursor",-1))
	var values: Array = page.get("candidates",[])
	var limit := int(sent.get("candidate_limit",0))
	if values.size() > (128 if limit == 0 else limit): return
	if first < 0 or first >= rows.size() or values.is_empty(): return
	var count := mini(values.size(),rows.size()-first)
	# Validate the entire overlap before changing any row. Never append or sort
	# on a fact refresh: DF retains the open selector's membership and order.
	for index in count:
		if int(values[index].get("id",-1)) != int(rows[first+index].id): return
	for index in count: rows[first+index] = values[index].duplicate(true)
	_trim_owner_recipes()
	facts_changed.emit()

func retain_owner_recipes(first: int) -> void:
	if kind != 1: return
	var start := maxi(0,first-9)
	if start == recipe_first: return
	recipe_first = start
	if _trim_owner_recipes(): facts_changed.emit()

func _trim_owner_recipes() -> bool:
	if kind != 1: return false
	var trimmed := false
	for index in rows.size():
		if index >= recipe_first and index < recipe_first+OWNER_RECIPE_ROWS: continue
		if not rows[index].has("sheet_icon"): continue
		# Page receipts are owned elsewhere too. Replace the row; never mutate
		# their snapshot or a view's prior facts while releasing heavy recipes.
		var row: Dictionary = rows[index].duplicate()
		row.erase("sheet_icon"); rows[index] = row; trimmed = true
	return trimmed

func reject(reason: String) -> void:
	pending = {}; delay = -1; search_delay = -1; failed = true; mutating = false
	changed.emit(); failed_page.emit(reason)

func can_remove_owner() -> bool:
	# Native selector context dispatch0x3a7c70: Bedroom/Office/DiningHall,
	# but no Tomb clear row. These are semantic civzone_type values.
	return kind == 1 and bool(area.get("owner_allowed",false)) and int(area.get("zone_type",-1)) in [80,92,93]

func assign_owner(id: int) -> void:
	if busy() or kind != 1 or not bool(area.get("owner_allowed",false)): return
	if id == -1 and not can_remove_owner(): return
	var found := id == -1
	for row in rows:
		if int(row.id) == id: found = true
	if not found or (id >= 0 and id == int(area.get("owner_id",-1))): return
	mutating = true; changed.emit()
	request_ready.emit({"action":C.ManagementAction.AreaUpdate,"id":int(area.id),"kind":1,
		"expected_revision":int(area.revision),"owner_id":id})

func toggle_animal(entity: int, id: int) -> void:
	if busy() or kind != 2 or id < 0: return
	if entity not in [C.AreaCandidateEntity.Unit,C.AreaCandidateEntity.Item]: return
	for row in rows:
		if int(row.id) != id or int(row.get("entity",C.AreaCandidateEntity.Unknown)) != entity: continue
		var request := {"action":C.ManagementAction.AreaUpdate,"operation":C.AreaOperation.AssignUnits,
			"id":int(area.id),"kind":1,"expected_revision":int(area.revision),
			"assign":0 if bool(row.get("assigned",false)) else 1}
		request["item_id" if entity == C.AreaCandidateEntity.Item else "unit_id"] = id
		mutating = true; changed.emit()
		request_ready.emit(request)
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
