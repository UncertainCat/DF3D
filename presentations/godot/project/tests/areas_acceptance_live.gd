extends SceneTree
const Contract = preload("res://scripts/management_contract.gd")
const S = Contract.ManagementStatus
var world
var directory: String
var reasons: Array[String] = []
var failed := false
var stopped := false
var step := "startup"
var handshake := 0
var fixture: Dictionary = {}
var retirements := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> bool:
	if not value:
		failed = true
		stopped = true
		reasons.append("step " + step + ": " + message)
		push_error(reasons.back())
	return value

func incomplete(message: String, stop: bool = false) -> void:
	reasons.append("step " + step + ": " + message)
	stopped = stopped or stop
	print("AREAS_INCOMPLETE ", reasons.back())

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(directory + "/" + path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func native(op: String, args: Dictionary = {}) -> Dictionary:
	if stopped: return {}
	handshake += 1
	var request := args.duplicate()
	request.op = op
	write_json("request-%d.json" % handshake, request)
	var file := FileAccess.open(directory + "/verify.tmp", FileAccess.WRITE)
	file.store_string(str(handshake))
	file.close()
	if not check(DirAccess.rename_absolute(directory + "/verify.tmp", directory + "/verify.txt") == OK, "verify handshake rename failed"): return {}
	var deadline := Time.get_ticks_msec() + 45000
	while not FileAccess.file_exists(directory + "/ack-%d" % handshake):
		if Time.get_ticks_msec() >= deadline:
			incomplete("native handshake wait cap hit; no command replay", true)
			return {}
		world.poll()
		await create_timer(0.02).timeout
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/response-%d.json" % handshake))
	if result.status == "incomplete": incomplete(result.reason)
	elif not check(result.status == "passed", str(result.get("reason", op))): return {}
	return result

# Bridge-bound intents use this helper. Each intent is sent exactly once;
# a lost/unknown outcome ends the run and is never retried.
func request(data: Dictionary, refusal: String = "") -> Dictionary:
	if stopped: return {}
	world.poll()
	var seq: int = world.area_request(data)
	if not check(seq > 0, "request not sent: " + world.last_error()): return {}
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var state: Dictionary = world.poll_management()
		if int(state.get("request_seq", 0)) == seq and int(state.get("status", S.Idle)) not in [S.Idle, S.Pending]:
			print("AREA_RECEIPT step=", step, " seq=", seq, " ", state)
			if refusal.is_empty():
				if not check(int(state.status) == S.Ok, str(state.get("message", "request failed"))): return {}
			else:
				if not check(int(state.status) == S.Rejected and str(state.get("message", "")) == refusal, "expected refusal: " + refusal): return {}
			return state.get("area", {})
		await create_timer(0.01).timeout
	incomplete("receipt wait cap hit; outcome unknown, no replay", true)
	return {}

func request_pause(want_paused: bool) -> bool:
	world.poll()
	var seq: int = world.send_set_pause(want_paused)
	if not check(seq > 0, "pause command not sent: " + world.last_error()): return false
	var deadline := Time.get_ticks_msec() + 30000
	var accepted := false
	while Time.get_ticks_msec() < deadline:
		world.poll()
		for receipt in world.drain_command_results():
			if int(receipt.seq) == seq:
				if not check(int(receipt.status) == 0 and receipt.message == ("paused" if want_paused else "unpaused"), "pause command refused: " + str(receipt.message)): return false
				accepted = true
		var session: Dictionary = world.poll_session()
		if accepted and session.get("fortress_valid", false) and session.get("paused", not want_paused) == want_paused: return true
		await create_timer(0.02).timeout
	incomplete("pause receipt/readback wait cap hit; no replay", true)
	return false

func inspect(id: int, kind: int = 0) -> Dictionary:
	var reply := await request({"action":9, "kind":kind, "id":id})
	if stopped: return {}
	if not check(reply.get("areas", []).size() == 1, "inspect must return one area"): return {}
	return reply.areas[0]

func edit(id: int, kind: int, fields: Dictionary) -> Dictionary:
	var current := await inspect(id, kind)
	if stopped: return {}
	var data := fields.duplicate(true)
	data.action = 11; data.kind = kind; data.id = id; data.expected_revision = current.revision
	return await request(data)

func pages(data: Dictionary, field: String) -> Dictionary:
	var query := data.duplicate(true)
	var all: Array = []
	var deadline := Time.get_ticks_msec() + 90000
	var revision := 0
	while not stopped:
		var page := await request(query)
		if stopped: return {}
		if int(page.build_done) < int(page.build_total) or int(page.list_revision) == 0:
			if Time.get_ticks_msec() >= deadline:
				incomplete("list preparation wait cap hit", true); return {}
			await create_timer(0.25).timeout
			continue
		if revision == 0: revision = int(page.list_revision)
		if not check(int(page.list_revision) == revision, "list revision changed during paging"): return {}
		all.append_array(page.get(field, []))
		if int(page.next_cursor) == 0:
			page[field] = all; return page
		query.cursor = int(page.next_cursor); query.expected_list_revision = revision
	return {}

func refusal(data: Dictionary, message: String) -> void:
	await native("guard_before")
	await request(data, message)
	await native("guard_after")

func zone(key: String) -> int:
	if fixture.zones.has(key): return int(fixture.zones[key])
	incomplete("missing " + key + " zone")
	return -1

func settings_and_presets() -> void:
	step = "1 settings"
	var pile := int(fixture.pile)
	if pile < 0: incomplete("missing fixture stockpile"); return
	# Wood has one native leaf list. Compare every page, row, label and state
	# against a separate native raw/settings enumeration, including ordering.
	await pages({"action":9, "id":pile, "operation":1}, "settings")
	var wood := await pages({"action":9, "id":pile, "operation":1, "list_key":"wood"}, "settings")
	if stopped: return
	await native("wood", {"id":pile, "rows":wood.settings})
	if wood.settings.is_empty(): incomplete("no captioned wood settings rows")
	else:
		var key: String = wood.settings[0].key
		await edit(pile, 0, {"operation":2, "scope":1, "value":1, "list_key":"wood", "row_key":key})
		await native("wood", {"id":pile, "value":1, "row_key":key})
	for scope in [2, 3, 4]:
		for value in [1, 2]:
			await edit(pile, 0, {"operation":2, "scope":scope, "value":value, "list_key":"wood"})
			await native("wood", {"id":pile, "value":value})
			if stopped: return
	step = "2 presets and toggles"
	for preset in [1, 15, 19]:
		await edit(pile, 0, {"operation":3, "preset":preset})
		await native("preset", {"id":pile, "preset":preset, "category":"wood" if preset == 15 else ""})
		if stopped: return
	for value in [0, 1]:
		await edit(pile, 0, {"operation":13, "organic":value, "inorganic":value})
		await native("snapshot", {"id":pile, "expected":{"organic":value, "inorganic":value}})

func names_and_stale() -> void:
	step = "3 names"
	var pile := int(fixture.pile)
	if pile < 0: incomplete("missing fixture stockpile"); return
	for label in ["DF3D renamed pile", ""]:
		await edit(pile, 0, {"operation":4, "name":label})
		var observed := await native("snapshot", {"id":pile, "expected":{"custom_name":label}})
		var current := await inspect(pile)
		if stopped: return
		check(current.name == observed.area.name, "name differs from native getName")
	var before := await inspect(pile)
	if stopped: return
	await refusal({"action":11, "id":pile, "operation":4, "expected_revision":before.revision, "name":"unrepresentable 🐉"}, "Name contains characters DF cannot store")
	step = "9 stale revisions"
	var wood := await pages({"action":9, "id":pile, "operation":1, "list_key":"wood"}, "settings")
	before = await inspect(pile)
	if stopped: return
	await native("stale_edit", {"id":pile})
	await refusal({"action":11, "id":pile, "operation":4, "expected_revision":before.revision, "name":"must not apply"}, "Area changed; inspect again")
	await refusal({"action":9, "id":pile, "operation":1, "list_key":"wood", "expected_list_revision":wood.list_revision}, "List changed; refresh")

func paint() -> void:
	step = "4 paint"
	if not fixture.has("origin"): incomplete("missing free paint footprint"); return
	var p: Dictionary = fixture.origin
	var spans: Array = []
	for y in range(20): spans.append({"x":int(p.x), "y":int(p.y) + y, "length":20})
	var first := await request({"action":10, "operation":5, "paint_mode":1, "paint_z":int(p.z), "spans":spans})
	if stopped: return
	if not check(first.areas.size() == 1, "Create+Paint area missing"): return
	var a: Dictionary = first.areas[0]
	await native("snapshot", {"id":int(a.id), "expected":{"tile_count":400}})
	# Two independent Accept operations, each replacing the complete footprint.
	# The second adds 200 and erases 200 cells in one revision-checked request.
	for parity in [0,1]:
		var desired: Array = []; var expected: Array = []
		for y in range(20):
			for x in range(20):
				var on: bool = (x+y)%2 == int(parity)
				expected.append(1 if on else 0)
				if on: desired.append({"x":int(p.x)+x,"y":int(p.y)+y,"length":1})
		var changed := await request({"action":11,"id":int(a.id),"operation":5,"expected_revision":a.revision,
			"paint_mode":3,"paint_z":int(p.z),"spans":desired})
		if stopped: return
		a = changed.areas[0]; retirements += 1
		await native("snapshot",{"id":int(a.id),"expected":{"tile_count":200,"extents":expected}})
	var erase := await request({"action":11, "id":int(a.id), "operation":5, "expected_revision":a.revision,
		"paint_mode":2, "paint_z":int(p.z), "spans":[{"x":int(p.x), "y":int(p.y)+19, "length":20}]})
	if stopped: return
	a = erase.areas[0]; retirements += 1
	await native("snapshot", {"id":int(a.id), "expected":{"tile_count":190}})
	await refusal({"action":11, "id":int(a.id), "operation":5, "expected_revision":a.revision,
		"paint_mode":2, "paint_z":int(p.z), "spans":spans}, "Erase would remove the whole area; use Remove")
	await refusal({"action":11, "id":int(a.id), "operation":5, "expected_revision":a.revision,
		"paint_mode":1, "paint_z":int(p.z)+1, "spans":[spans[0]]}, "Paint must stay on the area's z level")
	await request({"action":12, "id":int(a.id), "expected_revision":a.revision})
	await native("removed", {"id":int(a.id)})

func locations() -> void:
	step = "5 locations"
	var id := zone("MeetingHall")
	if id < 0: return
	await pages({"action":9, "kind":1, "id":id, "operation":6}, "locations")
	if int(fixture.tavern) >= 0:
		await edit(id, 1, {"operation":7, "location_id":int(fixture.tavern)})
		await native("location", {"id":id, "location_id":int(fixture.tavern)})
	else: incomplete("no tavern prerequisite")
	for fields in [{"operation":8, "location_kind":2, "deity_kind":1}, {"operation":8, "location_kind":4, "profession":0}]:
		await edit(id, 1, fields)
		var observed := await inspect(id, 1)
		if stopped: return
		check(int(observed.location_id) >= 0, "created location absent")
		await native("location", {"id":id, "location_id":int(observed.location_id),"location_kind":int(observed.location_kind)})
	await edit(id, 1, {"operation":7, "location_id":-1})
	await native("location", {"id":id, "location_id":-1})

func candidates_and_zones() -> void:
	step = "6 candidates"
	for entry in [["Bedroom", 1], ["Pen", 2], ["Barracks", 3]]:
		var id := zone(entry[0])
		if id < 0: continue
		for sort in range(4):
			for descending in [false, true]:
				var reply := await pages({"action":14, "kind":1, "id":id, "operation":14,
					"candidate_kind":entry[1], "sort":sort, "sort_descending":descending}, "candidates")
				if stopped: return
				await native("candidates", {"id":id, "kind":entry[1], "sort":sort, "descending":descending, "rows":reply.candidates})
	step = "7 zone settings and assignments"
	for entry in [["Pond", "pond_mode", [1,2]], ["ArcheryRange", "facing", [1,2,3,4]],
		["Tomb", "tomb_citizens", [0,1]], ["Tomb", "tomb_pets", [0,1]],
		["PlantGathering", "gather_trees", [0,1]], ["PlantGathering", "gather_shrubs", [0,1]]]:
		var id := zone(entry[0])
		if id < 0: continue
		for value in entry[2]:
			var fields: Dictionary = {}; fields[entry[1]] = value
			await edit(id, 1, {"operation":9, "zone_settings":fields})
			await native("zone_settings", {"id":id, "expected":fields})
			if stopped: return
	var bedroom := zone("Bedroom")
	if bedroom >= 0:
		var current := await inspect(bedroom, 1)
		if stopped: return
		await refusal({"action":11, "kind":1, "id":bedroom, "operation":9, "expected_revision":current.revision,
			"zone_settings":{"pond_mode":1}}, "Setting pond_mode does not apply to this zone type")
		if int(fixture.owner) >= 0:
			for owner in [int(fixture.owner), -1]:
				await edit(bedroom, 1, {"owner_id":owner})
				var owner_area := await inspect(bedroom,1)
				if stopped: return
				await native("snapshot", {"id":bedroom, "expected":{"owner_id":owner,
					"owner_profession":str(owner_area.owner_profession),"owner_sex":int(owner_area.owner_sex)}})
				if stopped: return
	var pen := zone("Pen")
	if pen >= 0:
		for key in ["grazer", "caged"]:
			var unit := int(fixture[key])
			if unit < 0: incomplete("missing " + key + " for assignment effects"); continue
			await native("assignment_before", {"unit_id":unit})
			for value in [1,0]:
				await edit(pen, 1, {"operation":11, "unit_id":unit, "assign":value})
				await native("assignment", {"id":pen, "unit_id":unit, "assign":value == 1})
				if stopped: return
			retirements += 1
	var barracks := zone("Barracks")
	if barracks >= 0 and int(fixture.squad) >= 0:
		for use in [15,2,0]:
			await edit(barracks, 1, {"operation":12, "squad_id":int(fixture.squad), "squad_use":use})
			await native("squad", {"id":barracks, "squad_id":int(fixture.squad), "use":use})
			if stopped: return
		retirements += 2
	else: incomplete("barracks/squad prerequisite missing")

func workshop_links() -> void:
	step = "8 workshop links"
	var pile := int(fixture.pile)
	var workshop := int(fixture.workshop)
	if pile < 0 or workshop < 0: incomplete("workshop/stockpile prerequisite missing"); return
	for give in [true, false]:
		for unlink in [false, true]:
			var current := await inspect(pile)
			if stopped: return

			await request({"action":13, "kind":2, "id":workshop, "operation":15, "link_id":pile,
				"give":give, "unlink":unlink, "expected_revision":current.revision})
			await native("link", {"id":workshop, "pile_id":pile, "give":give, "linked":not unlink})
			await pages({"action":9, "id":pile, "operation":10}, "links")
			if stopped: return

func created_zone_defaults() -> void:
	step = "7 zone creation defaults"
	if not fixture.has("origin"): incomplete("missing free zone footprint"); return
	var catalog := await request({"action":7})
	if stopped: return
	check(catalog.choices.size() == 18, "expected eighteen supported native zone types")
	var p: Dictionary = fixture.origin
	for choice in catalog.choices:
		var made := await request({"action":10, "kind":1, "zone_type":int(choice.id),
			"origin":Vector3i(int(p.x)+21, int(p.y)+4, int(p.z)), "width":2, "height":2})
		if stopped: return
		if not check(made.areas.size() == 1, "new zone absent"): return
		var area: Dictionary = made.areas[0]
		await native("snapshot", {"id":int(area.id), "expected":{"zone_type":int(choice.id), "active":true, "tile_count":4}})
		var defaults: Dictionary = {"Pond":{"pond_mode":1}, "ArcheryRange":{"facing":2},
			"Tomb":{"tomb_citizens":1, "tomb_pets":0}, "PlantGathering":{"gather_trees":1, "gather_shrubs":1}}
		if defaults.has(choice.name): await native("zone_settings", {"id":int(area.id), "expected":defaults[choice.name]})
		await request({"action":12, "kind":1, "id":int(area.id), "expected_revision":area.revision})
		await native("removed", {"id":int(area.id)})
		if stopped: return

func wait_ticks() -> void:
	step = "simulation after edits"
	await native("wait_start")
	if stopped or not await request_pause(false): return
	while not stopped:
		await create_timer(0.25).timeout
		var observed := await native("wait_poll")
		if not observed.get("waiting", false): break
	# Always attempt to pause, including an interrupted or incomplete wait.
	await request_pause(true)

func reload_fortress() -> void:
	step = "11 reload"
	if int(fixture.pile) < 0: incomplete("missing fixture pile for restart check"); return
	await native("status")
	if stopped: return
	var previous: Dictionary = world.poll_session()
	var previous_epoch := int(previous.get("fortress_epoch", 0))
	# Send one read-only settings intent. Its outcome may be terminal or unknown;
	# the handshake never sends it again, including after producer replacement.
	var seq: int = world.area_request({"action":9, "id":int(fixture.pile), "operation":1, "list_key":"wood"})
	if not check(seq > 0, "pre-reload settings request not sent"): return
	handshake += 1
	write_json("request-%d.json" % handshake, {"op":"reload"})
	var file := FileAccess.open(directory + "/verify.tmp", FileAccess.WRITE)
	file.store_string(str(handshake)); file.close()
	if not check(DirAccess.rename_absolute(directory + "/verify.tmp", directory + "/verify.txt") == OK, "reload handshake rename failed"): return
	var deadline := Time.get_ticks_msec() + 690000
	var ack: Dictionary = {}
	var outcome := "unknown"
	while ack.is_empty():
		world.poll(); world.poll_session()
		var observed: Dictionary = world.poll_management()
		if int(observed.get("world_epoch", 0)) == previous_epoch and int(observed.get("request_seq", 0)) == seq and int(observed.get("status", S.Idle)) in [S.Ok, S.Rejected]: outcome = "terminal"
		for state in ["failed", "incomplete", "ack"]:
			var path := directory + "/%s-%d" % [state, handshake]
			if not FileAccess.file_exists(path): continue
			var reply: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			if state == "failed": check(false, "reload: " + str(reply.reason)); return
			if state == "incomplete": incomplete("reload: " + str(reply.reason), true); return
			ack = reply
		if Time.get_ticks_msec() >= deadline: incomplete("reload handshake timeout; no replay", true); return
		await create_timer(0.02).timeout
	var epoch := int(str(ack.epoch))
	if not check(epoch != previous_epoch and (epoch >> 32) == int(ack.pid), "reload epoch/process identity"): return
	deadline = Time.get_ticks_msec() + 60000
	var ready := false
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var session: Dictionary = world.poll_session()
		var state: Dictionary = world.poll_management()
		if int(state.get("world_epoch", 0)) == epoch:
			if not check(int(state.get("request_seq", 0)) != seq, "old sequence survived restart"): return
			if int(session.get("fortress_epoch", 0)) == epoch and session.get("paused", false): ready = true; break
		await create_timer(0.02).timeout
	if not ready: incomplete("reload: presentation did not reattach", true); return
	print("RELOAD_TICKET_OUTCOME ", outcome)
	await seed_catalog()
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	if stopped: return
	if int(fixture.pile) < 0: incomplete("restart fixture could not provision a stockpile"); return
	var first := await request({"action":9, "id":int(fixture.pile), "operation":1, "list_key":"wood"})
	if stopped: return
	if not check(int(first.build_phase) == 1 and int(first.build_done) == 0, "settings did not restart from 0/total"): return
	var status := await native("status")
	if stopped: return
	check(int(status.holding) == 0, "holding array survived restart")
	print("RELOAD_DISCLOSURE process restart verified; same-process helper reload/holding persistence remains offline evidence")

func seed_catalog() -> void:
	if stopped: return
	world.poll()
	var seq: int = world.management_request("construction", {"action":Contract.ManagementAction.Catalog})
	if not check(seq > 0, "catalog seed not sent: " + world.last_error()): return
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var state: Dictionary = world.poll_management()
		if int(state.get("request_seq", 0)) == seq and int(state.get("status", S.Idle)) not in [S.Idle, S.Pending]:
			print("CATALOG_SEED_RECEIPT seq=", seq, " status=", state.get("status"), " action=", state.get("action"))
			check(int(state.status) == S.Ok and int(state.get("action", -1)) == Contract.ManagementAction.Catalog, "catalog seed failed: " + str(state.get("message", "not ready")))
			return
		await create_timer(0.01).timeout
	incomplete("catalog seed wait cap hit; catalog never reported ready", true)

func exercise() -> void:
	await seed_catalog()
	if stopped: return
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	for key in fixture.missing:
		incomplete(str(key) + ": " + str(fixture.missing[key]))
	var initial := await native("status")
	await settings_and_presets()
	await names_and_stale()
	await paint()
	await locations()
	await candidates_and_zones()
	await created_zone_defaults()
	await workshop_links()
	if stopped: return
	step = "10 retirement and builder status"
	var after := await native("status")
	if stopped: return
	check(int(after.holding) >= int(initial.holding) + retirements, "native retirement storage did not retain removed allocations")
	await wait_ticks()
	await reload_fortress()
	step = "12 departures"
	await native("departures")
	step = "final"
	await native("final")


func run() -> void:
	directory = OS.get_environment("DF3D_AREAS_ACCEPTANCE")
	if directory.is_empty():
		push_error("Run through tools/smoke/areas_acceptance.ps1 with prepared clone input")
		quit(77)
		return
	world = Df3dWorld.new()
	root.add_child(world)
	if check(world.attach(), "bridge attach failed"):
		var deadline := Time.get_ticks_msec() + 30000
		while not world.terrain_loaded() and Time.get_ticks_msec() < deadline:
			world.poll()
			await create_timer(0.01).timeout
		if not world.terrain_loaded(): incomplete("presented world wait cap hit", true)
		deadline = Time.get_ticks_msec() + 30000
		var management_ready := false
		while not stopped and Time.get_ticks_msec() < deadline:
			world.poll()
			var management: Dictionary = world.poll_management()
			if management.get("transport_alive", false):
				management_ready = true
				break
			await create_timer(0.01).timeout
		if not stopped and not management_ready: incomplete("management transport wait cap hit", true)
		if not stopped: await exercise()
	var status := "failed" if failed else ("incomplete" if not reasons.is_empty() else "passed")
	write_json("result.json", {"status":status, "reasons":reasons})
	print("AREAS_ACCEPTANCE ", status, " ", reasons)
	quit(1 if failed else (77 if status == "incomplete" else 0))
