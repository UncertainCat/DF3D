extends RefCounted
# Presentation ownership only. Entry, access and staff effects use semantic intents.
signal changed
const C = preload("res://scripts/management_contract.gd")
enum Phase { Closed, ReadingEntry, Entering, Ready, Refreshing, Rejected, Stale, Unknown, Unavailable, Editing }
var phase := Phase.Closed
var snapshot: Dictionary = {}
var identity: Dictionary = {}
var ticket := 0
var generation := 0
var service

func configure(source) -> void:
	close()
	if service != null and service.session_changed.is_connected(_session_changed):
		service.session_changed.disconnect(_session_changed)
	service = source
	service.session_changed.connect(_session_changed)

func close() -> void:
	generation += 1
	var previous := ticket
	ticket = 0; identity = {}; snapshot = {}; phase = Phase.Closed
	if service != null and previous != 0: service.detach(previous)
	changed.emit()

func _session_changed() -> void:
	close(); phase = Phase.Unavailable; changed.emit()

func open(target: Dictionary) -> void:
	close()
	for key in ["site_id","id"]:
		if typeof(target.get(key)) != TYPE_INT or int(target[key]) < 0 or int(target[key]) > 2147483647:
			phase = Phase.Rejected; changed.emit(); return
	if service == null:
		phase = Phase.Unavailable; changed.emit(); return
	identity = {"site_id":target.site_id,"id":target.id}
	phase = Phase.ReadingEntry
	_send(_read_intent())

func refresh() -> void:
	if phase != Phase.Ready or ticket != 0: return
	phase = Phase.Refreshing
	_send(_read_intent())

func set_access(mode: int) -> void:
	if phase != Phase.Ready or ticket != 0 or mode not in [0,1,2,3]: return
	if mode == 3 and int(snapshot.get("kind",0)) not in [2,4]: return
	var intent := _read_intent()
	intent.action = C.ManagementAction.AreaUpdate; intent.operation = C.AreaOperation.LocationAccess
	intent.expected_revision = snapshot.revision; intent.value = mode
	phase = Phase.Editing
	_send(intent)

func set_staff(occupation_id: int, unit_id: int, candidates_revision: int) -> void:
	if phase != Phase.Ready or ticket != 0 or candidates_revision <= 0 or unit_id < -1 or unit_id > 2147483647: return
	var target: Dictionary = {}
	for row in snapshot.get("staff",{}).get("rows",[]):
		if int(row.get("source",-1)) == 0 and int(row.get("occupation_id",-1)) == occupation_id:
			target = row; break
	if target.is_empty() or int(target.get("role",-1)) not in [0,1,2,5,7,8,9,10]: return
	if unit_id == -1 and int(target.get("unit_id",-1)) == -1 and int(target.get("histfig_id",-1)) == -1: return
	var intent := _read_intent()
	intent.action = C.ManagementAction.AreaUpdate; intent.operation = C.AreaOperation.LocationStaffEdit
	intent.expected_revision = snapshot.revision; intent.expected_list_revision = candidates_revision
	intent.occupation_id = occupation_id; intent.unit_id = unit_id
	phase = Phase.Editing
	_send(intent)

func _read_intent() -> Dictionary:
	return {"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LocationDetails,
		"kind":C.AreaKind.Zone,"location_site_id":identity.site_id,"location_id":identity.id}

func _send(intent: Dictionary) -> void:
	var owner := generation
	ticket = service.submit("areas",intent,func(received,result,sent):
		if owner == generation and received == ticket: _receive(result,sent))
	if ticket == 0: phase = Phase.Unavailable; snapshot = {}
	changed.emit()

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket = 0
	var area: Dictionary = result.get("area",{})
	var entry := int(sent.operation) == C.AreaOperation.LocationOpen
	var edit := int(sent.operation) in [C.AreaOperation.LocationAccess,C.AreaOperation.LocationStaffEdit]
	if (result.get("outcome","") == "unknown" or int(area.get("location_entry_outcome",0)) == C.LocationEntryOutcome.Unknown
		or int(area.get("location_edit_outcome",0)) == C.LocationEditOutcome.Unknown):
		phase = Phase.Unknown; snapshot = {}; changed.emit(); return
	if int(result.get("status",C.ManagementStatus.Rejected)) != C.ManagementStatus.Ok:
		phase = Phase.Stale if ((entry and int(area.get("location_entry_outcome",0)) == C.LocationEntryOutcome.Stale)
			or (edit and int(area.get("location_edit_outcome",0)) == C.LocationEditOutcome.Stale)) else Phase.Rejected
		snapshot = {}; changed.emit(); return
	var details: Dictionary = area.get("location_details",{})
	if (int(area.get("operation",-1)) != int(sent.operation)
		or int(result.get("action",-1)) != int(sent.action)
		or int(details.get("site_id",-1)) != int(identity.site_id)
		or int(details.get("id",-1)) != int(identity.id)
		or typeof(details.get("revision")) != TYPE_INT or int(details.revision) <= 0
		or int(details.get("kind",0)) not in [1,2,3,4,5]
		or (entry and int(area.get("location_entry_outcome",0)) != C.LocationEntryOutcome.Completed)
		or (edit and int(area.get("location_edit_outcome",0)) != C.LocationEditOutcome.Completed)):
		phase = Phase.Rejected; snapshot = {}; changed.emit(); return
	if phase == Phase.ReadingEntry:
		var intent := _read_intent()
		intent.action = C.ManagementAction.AreaUpdate; intent.operation = C.AreaOperation.LocationOpen
		intent.expected_revision = details.revision
		phase = Phase.Entering
		_send(intent)
		return
	snapshot = details.duplicate(true); phase = Phase.Ready; changed.emit()
