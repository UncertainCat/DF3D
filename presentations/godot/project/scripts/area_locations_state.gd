extends RefCounted
signal request_ready(request: Dictionary)
signal changed
signal failed_page(message: String)
signal selection_finished
const C = preload("res://scripts/management_contract.gd")
var area: Dictionary = {}
var rows: Array = []
var pending: Dictionary = {}
var receipt := 0
var cursor := 0
var delay := -1.0
var failed := false
var mutating := false
var catalog_kind := 0
var catalog_rows: Array = []
var catalog_revision := 0
var catalog_cursor := 0
var catalog_total := 0

func clear() -> void:
	area = {}; rows = []; pending = {}; receipt = 0; cursor = 0
	delay = -1; failed = false; mutating = false
	catalog_kind = 0; catalog_rows = []; catalog_revision = 0; catalog_cursor = 0; catalog_total = 0; changed.emit()

func open(value: Dictionary) -> void:
	clear(); area = value.duplicate(true)
	if int(area.get("kind",-1)) != 1 or int(area.get("revision",0)) <= 0:
		reject(""); return
	read()

func busy() -> bool:
	return area.is_empty() or failed or mutating or not pending.is_empty()

func read(next_cursor := 0) -> void:
	if busy() or catalog_kind != 0: return
	pending = {"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LocationList,
		"id":int(area.id),"kind":1,"cursor":next_cursor}
	if next_cursor != 0: pending.expected_list_revision = receipt
	delay = -1; changed.emit(); request_ready.emit(pending.duplicate(true))

func accept(page: Dictionary, sent: Dictionary) -> void:
	if pending.is_empty() or sent != pending: return
	if int(sent.operation) == C.AreaOperation.LocationChoices:
		var catalog: Dictionary = page.get("location_catalog",{})
		if int(catalog.get("kind",0)) != catalog_kind or int(catalog.get("revision",0)) <= 0 or int(catalog.get("cursor",-1)) != int(sent.cursor):
			reject(""); return
		if int(sent.cursor) != 0 and int(catalog.revision) != catalog_revision:
			reject(""); return
		if int(sent.cursor) == 0: catalog_rows = []
		catalog_rows.append_array(catalog.get("religions" if catalog_kind == 2 else "guilds",[]))
		catalog_revision = int(catalog.revision); catalog_cursor = int(catalog.get("next_cursor",0)); catalog_total = int(catalog.get("total",0))
		pending = {}; delay = -1
		if catalog_cursor != 0: read_catalog(catalog_cursor)
		else: changed.emit()
		return
	if int(page.get("list_revision",0)) == 0 or int(page.get("build_done",0)) < int(page.get("build_total",0)):
		delay = 0.25; return
	if int(sent.cursor) != 0 and int(page.list_revision) != receipt:
		reject(""); return
	if int(sent.cursor) == 0: rows = []
	rows.append_array(page.get("locations",[]))
	receipt = int(page.list_revision); cursor = int(page.get("next_cursor",0))
	pending = {}; delay = -1
	# Native scroll geometry uses the complete location list. Continue the
	# immutable receipt before enabling selection; do not present a partial
	# page as the end of the native list.
	if cursor != 0: read(cursor)
	else: changed.emit()

func poll(delta: float) -> void:
	if delay < 0 or pending.is_empty(): return
	delay -= maxf(0,delta)
	if delay <= 0.000001:
		delay = -1; request_ready.emit(pending.duplicate(true))

func more() -> void:
	if not busy() and cursor != 0: read(cursor)

func reject(reason: String) -> void:
	pending = {}; delay = -1; failed = true; mutating = false
	changed.emit(); failed_page.emit(reason)

func assign(id: int) -> void:
	if busy() or catalog_kind != 0: return
	var found := id == -1
	for row in rows:
		if int(row.id) == id: found = true
	if not found: return
	if id == int(area.get("location_id",-1)):
		# Native154554: choosing the current location closes the selector,
		# without changing membership, site identity or location value.
		if id >= 0: selection_finished.emit()
		return
	mutate({"operation":C.AreaOperation.LocationSet,"location_id":id})

func create(kind: int) -> void:
	if busy() or catalog_kind != 0 or kind not in [1,2,3,4,5]: return
	if kind in [2,4]:
		catalog_kind = kind; catalog_rows = []; catalog_revision = 0; catalog_cursor = 0; catalog_total = 0
		read_catalog(); return
	mutate({"operation":C.AreaOperation.LocationCreate,"location_kind":kind})

func read_catalog(next_cursor := 0) -> void:
	if busy() or catalog_kind not in [2,4]: return
	pending = {"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LocationChoices,
		"kind":1,"location_kind":catalog_kind,"cursor":next_cursor}
	if next_cursor != 0: pending.expected_list_revision = catalog_revision
	changed.emit(); request_ready.emit(pending.duplicate(true))

func back_catalog() -> void:
	pending = {}; delay = -1; failed = false; mutating = false
	catalog_kind = 0; catalog_rows = []; catalog_revision = 0; catalog_cursor = 0; catalog_total = 0; changed.emit()

func choose_catalog(index: int) -> void:
	if busy() or catalog_cursor != 0 or catalog_revision <= 0 or index < 0 or index >= catalog_rows.size(): return
	var row: Dictionary = catalog_rows[index]
	var fields := {"operation":C.AreaOperation.LocationCreate,"location_kind":catalog_kind}
	if catalog_kind == 2:
		fields.deity_kind = int(row.kind); fields.deity_id = int(row.id)
	elif catalog_kind == 4: fields.profession = int(row.profession)
	else: return
	mutate(fields)

func mutate(fields: Dictionary) -> void:
	if busy(): return
	var request := {"action":C.ManagementAction.AreaUpdate,"id":int(area.id),"kind":1,
		"expected_revision":int(area.revision)}
	request.merge(fields); mutating = true; changed.emit(); request_ready.emit(request)
