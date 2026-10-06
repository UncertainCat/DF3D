extends RefCounted
# Local selector ownership. Native names/skills remain observed data, never prose
# supplied by this controller. The owning staff workflow submits edits via Details.
signal changed
const C = preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Refreshing, Rejected, Unavailable }
var phase := Phase.Closed
var identity: Dictionary = {}
var rows: Array = []
var revision := 0
var ticket := 0
var generation := 0
var service
var _pending_rows: Array = []
var _seen: Dictionary = {}
var _seen_sources: Dictionary = {}
var _revision := 0
var _total := 0

func configure(source) -> void:
	close()
	if service != null and service.session_changed.is_connected(_session_changed):
		service.session_changed.disconnect(_session_changed)
	service = source
	service.session_changed.connect(_session_changed)

func close() -> void:
	generation += 1
	var previous := ticket
	ticket = 0; identity = {}; rows = []; revision = 0; _clear_pending()
	phase = Phase.Closed
	if service != null and previous != 0: service.detach(previous)
	changed.emit()

func _session_changed() -> void:
	close(); phase = Phase.Unavailable; changed.emit()

func _clear_pending() -> void:
	_pending_rows = []; _seen = {}; _seen_sources = {}; _revision = 0; _total = 0

func open(target: Dictionary) -> void:
	close()
	for key in ["site_id","location_id","occupation_id","role"]:
		if typeof(target.get(key)) != TYPE_INT or int(target[key]) < 0 or int(target[key]) > 2147483647:
			_reject(); return
	if int(target.role) not in [0,1,2,5,7,8,9,10]:
		_reject(); return
	if service == null:
		phase = Phase.Unavailable; changed.emit(); return
	identity = {"site_id":target.site_id,"location_id":target.location_id,"occupation_id":target.occupation_id,"role":target.role}
	phase = Phase.Reading
	_read(0)

func refresh() -> void:
	if phase != Phase.Ready or ticket != 0: return
	_clear_pending(); phase = Phase.Refreshing
	_read(0)

func _read(cursor: int) -> void:
	var owner := generation
	var intent := {"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LocationStaffCandidates,
		"kind":C.AreaKind.Zone,"location_site_id":identity.site_id,"location_id":identity.location_id,
		"occupation_id":identity.occupation_id,"cursor":cursor,"expected_list_revision":_revision}
	ticket = service.submit("areas",intent,func(received,result,sent):
		if generation == owner and ticket == received: _receive(result,sent))
	if ticket == 0:
		_clear_pending(); rows = []; revision = 0; phase = Phase.Unavailable
	changed.emit()

func _reject() -> void:
	ticket = 0; rows = []; revision = 0; _clear_pending()
	phase = Phase.Rejected; changed.emit()

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket = 0
	if result.get("outcome","") == "unknown":
		_clear_pending(); rows = []; revision = 0; phase = Phase.Unavailable; changed.emit(); return
	if int(result.get("status",C.ManagementStatus.Rejected)) != C.ManagementStatus.Ok:
		_reject(); return
	var area: Dictionary = result.get("area",{})
	var page: Dictionary = area.get("location_staff_candidates",{})
	if int(result.get("action",-1)) != int(sent.action) or int(area.get("operation",-1)) != int(sent.operation):
		_reject(); return
	for key in ["site_id","location_id","occupation_id","role"]:
		if typeof(page.get(key)) != TYPE_INT or page[key] != identity[key]:
			_reject(); return
	for key in ["revision","cursor","next_cursor","total"]:
		if typeof(page.get(key)) != TYPE_INT:
			_reject(); return
	var cursor: int = page.cursor
	var total: int = page.total
	var next_cursor: int = page.next_cursor
	if page.revision <= 0 or cursor != int(sent.cursor) or cursor != _pending_rows.size() or cursor % 128 != 0 or total < cursor or total > 2147483647:
		_reject(); return
	if typeof(page.get("rows")) != TYPE_ARRAY:
		_reject(); return
	var batch: Array = page.rows
	var count := mini(128,total-cursor)
	if batch.size() != count or (cursor != 0 and count == 0) or next_cursor != (cursor+count if cursor+count < total else 0):
		_reject(); return
	if cursor == 0:
		_revision = page.revision; _total = total
	elif page.revision != _revision or total != _total:
		_reject(); return
	var previous_score: int = 2147483647 if _pending_rows.is_empty() else int(_pending_rows[-1].score)
	var previous_source: int = -1 if _pending_rows.is_empty() else int(_pending_rows[-1].source_index)
	for row in batch:
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("unit_id")) != TYPE_INT or int(row.unit_id) < 0 or _seen.has(row.unit_id):
			_reject(); return
		if typeof(row.get("score")) != TYPE_INT or int(row.score) < 0 or int(row.score) > previous_score:
			_reject(); return
		if typeof(row.get("base_name"))!=TYPE_STRING or typeof(row.get("profession_name"))!=TYPE_STRING or typeof(row.get("legendary"))!=TYPE_BOOL:
			_reject(); return
		if typeof(row.get("profession_color"))!=TYPE_INT or row.profession_color<0 or row.profession_color>15:
			_reject(); return
		for key in ["source_index","profession_order","status_order"]:
			if typeof(row.get(key))!=TYPE_INT or row[key]<0 or row[key]>2147483647:
				_reject();return
		if row.source_index>=total or _seen_sources.has(row.source_index):
			_reject();return
		for key in ["name_sort_key","profession_sort_key"]:
			if typeof(row.get(key))!=TYPE_PACKED_BYTE_ARRAY or row[key].size()>2048:
				_reject();return
		if row.score==previous_score and row.source_index<=previous_source:
			_reject();return
		previous_source=row.source_index
		_seen_sources[row.source_index]=true
		_seen[row.unit_id] = true; previous_score = int(row.score)
	_pending_rows.append_array(batch.duplicate(true))
	# Native scroll/filter behavior requires the whole list. No partial list is
	# selectable, and no continuation can silently adopt a different revision.
	if next_cursor != 0:
		_read(next_cursor); return
	rows = _pending_rows; revision = _revision; _clear_pending()
	phase = Phase.Ready; changed.emit()
