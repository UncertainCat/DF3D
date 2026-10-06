extends RefCounted
# Pointer-free page receipts and navigation; the controller owns request tickets.
signal request_ready(request: Dictionary)
signal changed
signal failed_page(message: String)
const C = preload("res://scripts/management_contract.gd")
# AreaInfo.categories / legacy AreaUpdate flag order, independent of display order.
const CATEGORY_FLAGS = ["animals","food","furniture","corpses","refuse","stone","ammo","coins","bars_blocks","gems","finished_goods","leather","cloth","wood","weapons","armor","sheet"]
var area: Dictionary = {}
var rows: Array = [[],[],[]]
var receipts: Array = [{},{},{}]
var category := ""
var subcategory := ""
var leaf := ""
var query := ""
var search_text := ""
var search_delay := -1.0
var pending: Dictionary = {}
var pending_column := 0
var delay := -1.0
var failed := false
var mutating := false
var refresh_delay := 1.0
var refresh_required := false
var refreshing := false
var refresh_rows: Array = [[],[],[]]
var restore_counts: Array = [0,0,0]

func clear() -> void:
	area = {}; rows = [[],[],[]]; receipts = [{},{},{}]
	category = ""; subcategory = ""; leaf = ""; query = ""
	search_text = ""; search_delay = -1
	pending = {}; delay = -1; failed = false; mutating = false
	refresh_delay = 1.0
	refresh_required = false
	refreshing = false; refresh_rows = [[],[],[]]; restore_counts = [0,0,0]
	changed.emit()

func open(value: Dictionary, keep_navigation := false) -> void:
	var old_category := category if keep_navigation else ""
	var old_subcategory := subcategory if keep_navigation else ""
	var old_query := search_text if keep_navigation else ""
	if keep_navigation and int(value.get("id",-1)) == int(area.get("id",-2)):
		# Keep disabled rows in place until each refreshed column has regained its
		# loaded depth. Never temporarily shrink a scrolled list to its first page.
		restore_counts = [rows[0].size(),rows[1].size(),rows[2].size() if old_query == query else 0]
		refresh_rows = [[],[],[]]; refreshing = true
		pending = {}; delay = -1; search_delay = -1; failed = false; mutating = false
		refresh_required = false; refresh_delay = 1.0
	else:
		clear()
	area = value.duplicate(true)
	category = old_category; subcategory = old_subcategory; query = old_query
	search_text = old_query
	if not keep_navigation:
		# Native Custom opens Ammo/Type and activates Ammo even when every flag
		# was disabled. Background refreshes must never perform this mutation.
		category = "ammo"
		if activate_category(): return
	read(0, "")

func activate_category() -> bool:
	var flag_index := CATEGORY_FLAGS.find(category)
	if flag_index < 0:
		reject(); return true
	var bit := 1 << flag_index
	if (int(area.get("categories",0)) & bit) != 0: return false
	mutating = true
	changed.emit()
	request_ready.emit({"action":C.ManagementAction.AreaUpdate,"operation":0,
		"id":int(area.id),"kind":0,"expected_revision":int(area.revision),
		"changed_categories":bit,"categories":bit})
	return true

func reset_sublist() -> void:
	# Applied only after an accepted native global All/None. This is a navigation
	# reset, so do not restore the old sublist's rows or loaded page depth.
	subcategory = ""; leaf = ""
	rows[1] = []; rows[2] = []; receipts[1] = {}; receipts[2] = {}

func busy() -> bool:
	return not pending.is_empty() or search_delay >= 0 or mutating or failed or area.is_empty()

func read(column: int, key: String, cursor := 0) -> void:
	if area.is_empty(): return
	pending_column = column
	pending = {"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.SettingsPage,
		"id":int(area.id),"kind":0,"expected_revision":int(area.revision),"list_key":key,
		"query":query if column == 2 else "","cursor":cursor}
	if column == 1 and key in ["coins","corpses","wood"]: pending.query = query
	if cursor != 0: pending.expected_list_revision = int(receipts[column].get("list_revision",0))
	delay = -1
	changed.emit(); request_ready.emit(pending.duplicate(true))

func poll(delta: float) -> void:
	if search_delay >= 0:
		search_delay = maxf(0,search_delay - maxf(0,delta))
		if search_delay <= 0.000001 and pending.is_empty() and not mutating and not failed:
			search_delay = -1
			if search_text != query:
				query = search_text; rows[2] = []; receipts[2] = {}; read(2,leaf)
			else: changed.emit()
			return
	if not busy():
		refresh_delay -= maxf(0,delta)
		if refresh_delay <= 0:
			refresh_delay = 1.0
			pending = {"action":C.ManagementAction.AreaInspect,"operation":0,"id":int(area.id),"kind":0}
			request_ready.emit(pending.duplicate(true))
		return
	if delay < 0 or pending.is_empty(): return
	delay -= maxf(0,delta)
	if delay <= 0.000001:
		delay = -1
		request_ready.emit(pending.duplicate(true))

func reject(reason := "") -> void:
	pending = {}; delay = -1; search_delay = -1; mutating = false; failed = true
	changed.emit()
	if not reason.is_empty(): failed_page.emit(reason)

func accept_inspection(value: Dictionary, sent: Dictionary) -> void:
	if pending.is_empty() or sent != pending or int(sent.get("operation",-1)) != 0: return
	if int(value.get("id",-1)) != int(area.id):
		reject(); return
	pending = {}; refresh_delay = 1.0
	if refresh_required or int(value.get("revision",0)) != int(area.revision):
		open(value,true)
	else:
		changed.emit()

func recover_read(sent: Dictionary) -> bool:
	if mutating or pending.is_empty() or sent != pending or int(sent.get("operation",-1)) != C.AreaOperation.SettingsPage: return false
	# Only a terminal stale read reaches this path. Inspect current identity first;
	# never retry a mutation or reuse its old precondition. Back off during churn.
	refresh_required = true
	pending = {"action":C.ManagementAction.AreaInspect,"operation":0,"id":int(area.id),"kind":0}
	delay = 0.25
	changed.emit()
	return true

func accept(page: Dictionary, sent: Dictionary) -> void:
	if pending.is_empty() or sent != pending: return
	# A new local query supersedes an in-flight leaf read. Let its ticket finish,
	# but never display its old rows or continue polling that obsolete builder.
	if pending_column == 2 and str(sent.query) != search_text:
		pending = {}; delay = -1
		changed.emit(); return
	if str(page.get("list_key",pending.list_key)) != str(pending.list_key) or str(page.get("query",pending.query)) != str(pending.query):
		reject("Settings page changed; refresh"); return
	if int(page.get("list_revision",0)) == 0 or int(page.get("build_done",0)) < int(page.get("build_total",0)):
		delay = 0.25
		return
	var column := pending_column
	var key := str(pending.list_key)
	var cursor := int(pending.cursor)
	var values: Array = page.get("settings",[])
	if cursor != 0 and int(page.list_revision) != int(receipts[column].get("list_revision",0)):
		reject("List changed; refresh"); return
	# Direct category leaves (e.g. Wood) belong in column three; never create
	# a synthetic intermediate row. Empty direct lists are identified by the
	# catalog's known hierarchy, not by fabricated items.
	if column == 1 and (key in ["coins","corpses","wood"] or (not values.is_empty() and int(values[0].kind) == 4)):
		column = 2; leaf = key; subcategory = ""
	var destination: Array = refresh_rows if refreshing else rows
	if cursor == 0: destination[column] = []
	destination[column].append_array(values)
	receipts[column] = page.duplicate(true)
	pending = {}; delay = -1
	if refreshing:
		var next_cursor := int(page.get("next_cursor",0))
		if destination[column].size() < int(restore_counts[column]) and next_cursor != 0:
			read(column,key,next_cursor)
			return
		rows[column] = destination[column]
	if column == 0:
		var first := ""
		var found := false
		for row in rows[0]:
			if int(row.kind) != 1: continue
			if first.is_empty(): first = str(row.key)
			if str(row.key) == category: found = true
		category = category if found else first
		if not category.is_empty(): read(1,category)
	elif column == 1:
		var first := ""
		var found := false
		for row in rows[1]:
			if int(row.kind) != 2: continue
			if first.is_empty(): first = str(row.key)
			if str(row.key) == subcategory: found = true
		subcategory = subcategory if found else first
		leaf = subcategory
		# Animals has boolean cage options in column two and a separate direct
		# creature list in column three, with no synthetic navigation row.
		if key == "animals": leaf = "animals/animals"
		if not leaf.is_empty(): read(2,leaf)
	if pending.is_empty(): refreshing = false
	changed.emit()

func select(column: int, row: Dictionary) -> void:
	if busy(): return
	if int(row.kind) in [3,4]:
		edit(column,1,1 if int(row.state) == 2 else 2,str(row.key)); return
	if column == 0:
		category = str(row.key); subcategory = ""; leaf = ""
		rows[1] = []; rows[2] = []; receipts[1] = {}; receipts[2] = {}
		# Native category-label selection enables this flag without filling its
		# filters. Keep this explicit write separate from automatic page reads.
		if not activate_category(): read(1,category)
	elif column == 1:
		subcategory = str(row.key); leaf = subcategory
		rows[2] = []; receipts[2] = {}; read(2,leaf)

func search(value: String) -> void:
	queue_search(value)
	if search_delay >= 0:
		search_delay = 0
		poll(0)

func queue_search(value: String) -> void:
	if mutating or failed or area.is_empty() or leaf.is_empty(): return
	# Native settings search stores/displays uppercase and survives navigation.
	value = value.to_upper()
	if value == search_text and search_delay < 0:
		changed.emit(); return
	search_text = value; search_delay = 0.25
	if pending_column == 2 and delay >= 0:
		# No ticket is outstanding during this builder-poll wait.
		pending = {}; delay = -1
	changed.emit()

func more(column: int) -> void:
	if busy() or receipts[column].is_empty(): return
	var cursor := int(receipts[column].get("next_cursor",0))
	if cursor != 0: read(column,str(receipts[column].list_key),cursor)

func edit(column: int, scope: int, value: int, row_key := "") -> void:
	if busy() or int(area.get("revision",0)) == 0: return
	if column == 2 and leaf.is_empty(): return
	if column == 1 and category.is_empty(): return
	var key: String = ["",category,leaf][column]
	var request := {"action":C.ManagementAction.AreaUpdate,"operation":C.AreaOperation.SettingsSet,
		"id":int(area.id),"kind":0,"expected_revision":int(area.revision),
		"list_key":key,"scope":scope,"value":value}
	if scope == 1: request.row_key = row_key
	if column == 2: request.query = query
	mutating = true; changed.emit(); request_ready.emit(request)
