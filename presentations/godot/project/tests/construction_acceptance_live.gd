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
var lane_deadline_ms: int = 0

# JSON numbers are floats. Normalize once so Array.has() can match the integer
# identities retained by the lane, including its completed-wall exclusion.
static func building_ids(verification: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for id in verification.get("ids", []): ids.append(int(id))
	return ids

func lane_budget_ok() -> bool:
	if Time.get_ticks_msec() < lane_deadline_ms: return true
	incomplete("shared lane budget exhausted; no command replay", true)
	return false

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
	print("CONSTRUCTION_INCOMPLETE ", reasons.back())

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(directory + "/" + path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func native(op: String, args: Dictionary = {}) -> Dictionary:
	var cleanup: bool = op in ["guard_after", "wait_finish", "final"]
	if stopped and not cleanup: return {}
	if not cleanup and not lane_budget_ok(): return {}
	handshake += 1
	var request := args.duplicate()
	request.op = op
	write_json("request-%d.json" % handshake, request)
	var file := FileAccess.open(directory + "/verify.tmp", FileAccess.WRITE)
	file.store_string(str(handshake))
	file.close()
	if not check(DirAccess.rename_absolute(directory + "/verify.tmp", directory + "/verify.txt") == OK, "verify handshake rename failed"): return {}
	# Guard/status plus verifier each allow 30 s; include handshake overhead.
	# Finish an issued handshake before cleanup; the lane reserves 300 s.
	var deadline := Time.get_ticks_msec() + 90000
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
	if stopped or not lane_budget_ok(): return {}
	world.poll()
	var seq: int = world.management_request("construction", data)
	if seq <= 0:
		check(not refusal.is_empty() and world.last_error() == refusal, "request not sent: " + world.last_error())
		return {}
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if not lane_budget_ok(): return {}
		world.poll()
		var state: Dictionary = world.poll_management()
		if int(state.get("request_seq", 0)) == seq and int(state.get("status", S.Idle)) not in [S.Idle, S.Pending]:
			print("CONSTRUCTION_RECEIPT step=", step, " seq=", seq, " ", state)
			if refusal.is_empty():
				if not check(int(state.status) == S.Ok, str(state.get("message", "request failed"))): return {}
			elif not check(int(state.status) == S.Rejected and str(state.get("message", "")) == refusal, "expected exact refusal: " + refusal): return {}
			return state
		await create_timer(0.01).timeout
	incomplete("receipt wait cap hit; outcome unknown, no replay", true)
	return {}

func request_pause(want_paused: bool) -> bool:
	world.poll()
	var seq: int = world.send_set_pause(want_paused)
	if not check(seq > 0, "pause command not sent: " + world.last_error()): return false
	var deadline := Time.get_ticks_msec() + 30000
	var accepted := false
	var session: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		world.poll()
		for receipt in world.drain_command_results():
			print("CONSTRUCTION_PAUSE_RECEIPT wanted=", want_paused, " seq=", seq, " receipt=", receipt)
			if int(receipt.seq) == seq:
				if not check(int(receipt.status) == 0 and receipt.message == ("paused" if want_paused else "unpaused"), "pause command refused: " + str(receipt.message)): return false
				accepted = true
		session = world.poll_session()
		if accepted and session.get("fortress_valid", false) and session.get("paused", not want_paused) == want_paused: return true
		await create_timer(0.02).timeout
	print("CONSTRUCTION_PAUSE_TIMEOUT accepted=", accepted, " wanted=", want_paused,
		" phase=", session.get("phase"), " fortress_valid=", session.get("fortress_valid"),
		" paused=", session.get("paused"), " error=", world.last_error())
	incomplete("pause receipt/readback wait cap hit; no replay", true)
	return false


var catalog: Dictionary = {}
var placed: Array = []
var observed: Dictionary = {}
var observed_material_rows: Array = []
var fixture: Dictionary

func point(value: Dictionary) -> Vector3i:
	return Vector3i(int(value.x), int(value.y), int(value.z))

func native_point(value: Vector3i) -> Dictionary:
	return {"x":value.x, "y":value.y, "z":value.z}

func guarded(data: Dictionary, message: String) -> void:
	await native("guard_before")
	if stopped: return
	await request(data, message)
	# Run the after guard even when the receipt assertion failed.
	var was_stopped := stopped
	stopped = false
	await native("guard_after")
	stopped = stopped or was_stopped

func materials(key: String, filter_index: int, origin: Vector3i, observe: bool = false) -> Dictionary:
	var query := {"action":63, "definition":key, "filter":filter_index, "origin":origin}
	var rows: Array = []
	var seen: Array = []
	var first: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 120000
	while not stopped:
		if Time.get_ticks_msec() >= deadline:
			incomplete(key + " materials wait cap hit")
			return {}
		var state := await request(query)
		if stopped: return {}
		var c: Dictionary = state.construction
		if observe: await native("status")
		if int(c.build_phase) != 0:
			# Phase 3 is terminal. Never poll it into an automatic retry.
			if int(c.build_phase) == 3:
				incomplete("materials builder error: " + str(state.message))
				return {}
			await create_timer(0.25).timeout
			continue
		if first.is_empty(): first = c.duplicate(true)
		var cursor := int(query.get("cursor", 0))
		if not check(not seen.has(cursor), "materials cursor repeated"): return {}
		seen.append(cursor)
		rows.append_array(c.materials)
		if int(state.next_cursor) == 0: break
		query.cursor = int(state.next_cursor)
		query.expected_list_revision = int(c.list_revision)
	if stopped: return {}
	if not check(rows.size() == int(first.total), "materials page total"): return {}
	first.materials = rows
	return first

func selection_rows(key: String, origin: Vector3i, filters: Array, weapon_count: int = -1) -> Array:
	var selections: Array = []
	for filter_row in filters:
		var page := await materials(key, int(filter_row.index), origin)
		if page.is_empty(): return []
		var needed := int(filter_row.quantity)
		if key == "Trap:WeaponTrap" and int(filter_row.index) == 1 and weapon_count >= 0: needed = weapon_count
		for row in page.materials:
			if needed == 0: break
			var count := mini(needed, int(row.count))
			selections.append({"filter":int(filter_row.index), "item_type":int(row.item_type), "item_subtype":int(row.item_subtype), "mat_type":int(row.mat_type), "mat_index":int(row.mat_index), "count":count, "expected_list_revision":int(page.list_revision)})
			needed -= count
		if needed > 0:
			incomplete(key + " lacks stock for filter " + str(filter_row.index))
			return []
	if selections.size() > 16:
		incomplete(key + " requires more than 16 material groups")
		return []
	return selections

func place(key: String, site_name: String, direction: int = 0, retracting: bool = false, dimensions: Vector3i = Vector3i.ZERO, weapon_count: int = -1, explicit_origin: Dictionary = {}, roller_speed: int = 0, track_stop: Dictionary = {}, pressure_plate: Dictionary = {}) -> Dictionary:
	if stopped: return {}
	if not catalog.has(key) or not catalog[key].supported:
		incomplete(key + " unavailable in catalog")
		return {}
	if explicit_origin.is_empty() and (not fixture.sites.has(site_name) or fixture.incomplete.has(site_name)):
		incomplete(site_name + ": " + str(fixture.incomplete.get(site_name, "site missing")))
		return {}
	for filter_row in catalog[key].filters:
		var identity := str(int(filter_row.item_type))
		if fixture.get("unavailable_types", {}).has(identity):
			incomplete(key + ": " + str(fixture.unavailable_types[identity]))
			return {}
	var origin := point(explicit_origin if not explicit_origin.is_empty() else fixture.sites[site_name])
	var size := dimensions
	if size == Vector3i.ZERO:
		for fp in catalog[key].footprints:
			if int(fp.direction) == (4 if retracting else direction): size = Vector3i(int(fp.width), int(fp.height), 1)
	if not check(size != Vector3i.ZERO, "catalog footprint missing"): return {}
	var query := {"action":1, "definition":key, "origin":origin, "width":size.x, "height":size.y, "depth":size.z, "direction":direction, "retracting":retracting}
	if key == "Rollers": query.roller_speed = roller_speed
	if key == "Trap:TrackStop": query.track_stop = track_stop.duplicate()
	if key == "Trap:PressurePlate": query.pressure_plate = pressure_plate.duplicate()
	var preview := await request(query)
	if stopped: return {}
	if not check(preview.get("placement_valid",false),"successful Preview did not mark placement valid"): return {}
	var c: Dictionary = preview.construction
	var mask: Array = Array(c.valid_mask)
	if int(catalog[key].area_mode) >= 3:
		await native("mask", {"origin":native_point(origin), "width":size.x, "height":size.y, "depth":size.z, "mask":mask})
	if key == "Construction:Stairs":
		if not check(Array(c.pieces) == [1, 3, 2], "three-level pieces must be up/updown/down"): return {}
	var selections := await selection_rows(key, origin, c.filters, weapon_count)
	if stopped or (selections.is_empty() and int(preview.required) > 0): return {}
	query.action = 2
	query.selections = selections
	query.expected_list_revision = int(selections[0].expected_list_revision) if not selections.is_empty() else 0
	var receipt := await request(query)
	if stopped: return {}
	c = receipt.construction
	var args := {"definition":key, "origin":native_point(origin), "width":size.x, "height":size.y, "depth":size.z, "direction":direction, "retracting":retracting, "mode":int(catalog[key].area_mode), "mask":mask, "placed":int(c.placed), "skipped":int(c.skipped)}
	if weapon_count >= 0: args.weapon_count = weapon_count
	if key == "Rollers": args.roller_speed = roller_speed if roller_speed > 0 else 50000
	if key == "Trap:TrackStop": args.track_stop = track_stop.duplicate()
	if key == "Trap:PressurePlate": args.pressure_plate = pressure_plate.duplicate()
	var verified := await native("placed", args)
	if stopped: return {}
	var ids := building_ids(verified)
	for id in ids:
		placed.append({"id":id, "key":key, "origin":origin})
		await native("exists", {"id":id, "origin":native_point(origin), "phase":"after placement"})
	return {"receipt":receipt, "origin":origin, "ids":ids, "width":size.x, "height":size.y}

# Release a sequential fixture site through semantic commands. A marked-for-
# removal building is insufficient: every tile must actually be free before
# the next placement, and an unknown outcome stops rather than being replayed.
func release_site(placement: Dictionary) -> void:
	if stopped or placement.is_empty(): return
	for id in placement.ids:
		var inspection := await request({"action":3, "building_id":int(id)})
		if stopped: return
		await request({"action":4, "building_id":int(id), "definition":inspection.construction.building_key})
		if stopped: return
		await native("removed", {"id":int(id)})
	var released := await native("site_clear", {"origin":native_point(placement.origin), "width":int(placement.width), "height":int(placement.height)})
	if stopped: return
	if not released.get("clear", false):
		incomplete("sequential site still occupied after removal", true)
		return
	for i in range(placed.size() - 1, -1, -1):
		if placement.ids.has(placed[i].id): placed.remove_at(i)


func collect_keys(value: Variant, keys: Array) -> void:
	if value is Array:
		for child in value: collect_keys(child, keys)
	elif value is Dictionary:
		for field in ["key", "catalog_key", "definition"]:
			if value.get(field) is String and not value[field].is_empty(): keys.append(value[field])
		for child in value.values():
			if child is Array or child is Dictionary: collect_keys(child, keys)

func catalog_pages() -> void:
	var query := {"action":0}
	var seen: Array = []
	var total := -1
	while not stopped:
		var state := await request(query)
		if stopped: return
		total = int(state.construction.total)
		if not check(not seen.has(int(query.get("cursor", 0))), "catalog cursor repeated"): return
		seen.append(int(query.get("cursor", 0)))
		if int(query.get("cursor",0)) == 0:
			var examples: Array = state.construction.get("pressure_creatures",[])
			if not check(examples.size()==200,"pressure example metadata missing"): return
			await native("pressure_examples",{"rows":examples})
			if stopped: return
			print("PRESSURE_EXAMPLES_TRANSPORT_PASS rows=",examples.size())
		for row in state.catalog:
			if not check(not catalog.has(row.key), "duplicate catalog key"): return
			catalog[row.key] = row
			if not row.supported:
				var fixed_reasons := {"Windmill":"Windmill placement rule not captured", "Construction:Track":"Track semantic services unavailable"}
				if fixed_reasons.has(row.key): check(row.reason == fixed_reasons[row.key], "catalog refusal mismatch " + row.key)
				if not check(row.reason in ["Building has no recipe", "Recipe has more than 8 inputs", "Placed from the stockpile and zone menus", "Magma placement rule not captured", "Windmill placement rule not captured", "Pressure plate options not captured", "Track stop options not captured", "Track semantic services unavailable", "Not permitted for this civilization", "Native placement check rejected this site"], "unknown unsupported reason: " + row.reason): return
		if int(state.next_cursor) == 0: break
		query.cursor = int(state.next_cursor)
		query.expected_list_revision = int(state.construction.list_revision)
	check(catalog.size() == total, "catalog page total")
	var keys: Array = []
	var menu := "res://panels/build_menu.json"
	if FileAccess.file_exists(menu):
		collect_keys(JSON.parse_string(FileAccess.get_file_as_string(menu)), keys)
		check(not keys.is_empty(), "build_menu.json has no catalog keys")
	else:
		print("build_menu.json missing; using allowed 03-U spec leaf keys")
		keys = ["TradeDepot", "Workshop:Ashery", "Workshop:Bowyers", "Workshop:Carpenters", "Workshop:Craftsdwarfs", "Workshop:Jewelers", "Workshop:MagmaForge", "Workshop:Mechanics", "Workshop:MetalsmithsForge", "Workshop:Siege", "Workshop:Masons", "Workshop:Leatherworks", "Workshop:Loom", "Workshop:Clothiers", "Workshop:Dyers", "FarmPlot", "Workshop:Still", "Workshop:Butchers", "Workshop:Tanners", "Workshop:Fishery", "Workshop:Kitchen", "Workshop:Farmers", "Workshop:Quern", "Workshop:Kennels", "NestBox", "Hive", "Furnace:GlassFurnace", "Furnace:Kiln", "Furnace:MagmaGlassFurnace", "Furnace:MagmaKiln", "Furnace:MagmaSmelter", "Furnace:Smelter", "Furnace:WoodFurnace", "Bed", "Chair", "Table", "Box", "Cabinet", "Coffin", "Slab", "Statue", "TractionBench", "Bookcase", "DisplayFurniture", "OfferingPlace", "Instrument", "Door", "Hatch", "Construction:Wall", "Construction:Floor", "Construction:Ramp", "Construction:Stairs", "Bridge", "RoadPaved", "RoadDirt", "Construction:Fortification", "GrateWall", "GrateFloor", "BarsVertical", "BarsFloor", "WindowGlass", "WindowGem", "Support", "Construction:Track", "Trap:TrackStop", "Trap:Lever", "Well", "Floodgate", "ScrewPump", "WaterWheel", "Windmill", "GearAssembly", "AxleHorizontal", "AxleVertical", "Workshop:Millstone", "Rollers", "Chain", "Cage", "AnimalTrap", "Trap:PressurePlate", "Trap:StoneFallTrap", "Trap:WeaponTrap", "Trap:CageTrap", "Weapon", "ArcheryTarget", "Weaponrack", "Armorstand", "SiegeEngine:Ballista", "SiegeEngine:Catapult", "SiegeEngine:BoltThrower"]
		# ReinforcedWall is enum-backed (family/subtype_key), not a raw name.
		var reinforced_key := ""
		for row in catalog.values():
			if row.family == "Construction" and row.subtype_key == "ReinforcedWall": reinforced_key = str(row.key)
		if not check(not reinforced_key.is_empty(), "catalog missing Construction/ReinforcedWall leaf"): return
		keys.append(reinforced_key)
		# Only custom workshop leaves use catalog native_name.
		for label in ["Screw Press", "Soap Maker's Workshop"]:
			var found := false
			for row in catalog.values():
				if str(row.native_name).to_lower() == label.to_lower(): keys.append(row.key); found = true
			if not found: incomplete("03-U raw-defined leaf unavailable: " + label)
	for key in keys: check(catalog.has(key), "catalog missing menu key " + str(key))

func wait_wall(origin: Vector3i) -> bool:
	var start := await native("wait_start", {"origin":native_point(origin)})
	if not start.get("waiting", false): return false
	if stopped or not await request_pause(false): return false
	var complete := false
	while not stopped:
		await create_timer(0.25).timeout
		var result := await native("wait_poll")
		if not result.get("waiting", false):
			complete = result.get("status", "") == "passed"
			break
	# Re-pause after every wait, including an interrupted handshake.
	var was_stopped := stopped
	stopped = false
	await request_pause(true)
	await native("wait_finish")
	stopped = stopped or was_stopped
	return complete and not stopped

func material_tuples(rows: Variant) -> Array:
	if not rows is Array: return []
	var tuples: Array = []
	for row in rows:
		if not row is Dictionary: return []
		var tuple: Array = []
		for field in ["item_type", "item_subtype", "mat_type", "mat_index", "count"]:
			if not row.has(field) or not str(row[field]).is_valid_int(): return []
			tuple.append(int(row[field]))
		tuples.append(tuple)
	return tuples

func compare_dump(repo: String, relative: String, finding: Dictionary) -> String:
	var path := repo.path_join(relative)
	if not FileAccess.file_exists(path):
		var folder := "e5" if str(finding.line).begins_with("e5/") else "e4"
		path = repo.path_join("build/evidence/native/" + folder).path_join(relative)
	if not FileAccess.file_exists(path): return "incomplete: evidence missing; " + finding.line
	var rows: Variant = []
	if path.get_extension().to_lower() == "json":
		rows = JSON.parse_string(FileAccess.get_file_as_string(path))
		if rows is Dictionary: rows = rows.get("materials", [])
	else:
		var file := FileAccess.open(path, FileAccess.READ)
		var delimiter := "\t" if path.get_extension().to_lower() == "tsv" else ","
		var headers := file.get_csv_line(delimiter)
		while not file.eof_reached():
			var values := file.get_csv_line(delimiter)
			if values.size() != headers.size(): continue
			var row := {}
			for i in range(headers.size()): row[headers[i]] = values[i]
			rows.append(row)
		file.close()
	var expected := material_tuples(rows)
	var actual := material_tuples(observed_material_rows)
	if expected.is_empty(): return "incomplete: evidence missing (material identity/count rows absent); " + finding.line
	if actual.is_empty(): return "incomplete: live material rows unavailable; " + finding.line
	return ("match " if actual == expected else "mismatch ") + finding.line + " (material identities/counts/order)"

func departure_report() -> void:
	var repo := FileAccess.get_file_as_string(directory + "/repo.txt").strip_edges()
	var evidence: Array = []
	for folder in ["e4", "e5"]:
		var path: String = repo + "/build/evidence/native/" + folder + "/findings.md"
		if not FileAccess.file_exists(path): continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in range(lines.size()): evidence.append({"line":folder + "/findings.md:" + str(i + 1) + " " + lines[i], "text":lines[i]})
	var needles := {"D1":"Needs open space", "D2":"sorted by distance", "D3":"two-level drag", "D4":"Invalid tiles inside are skipped", "D5":"Weapon and spike counts", "D6":"8 facings", "D7":"Bridge and paved road", "D8":"acts immediately"}
	var rows: Array = []
	for n in range(1, 10):
		var id := "D" + str(n)
		var text := id + ": incomplete: evidence missing"
		for finding in evidence:
			if needles.has(id) and str(finding.text).contains(needles[id]):
				text = id + ": " + (("match " if observed[id] else "mismatch ") if observed.has(id) else "incomplete: live comparison unavailable; ") + finding.line
				var partial: Dictionary = {
					"D1":"partial: native Needs open space captured; well refusal wording not exercised; ",
					"D3":"partial: two-level drag not exercised; three-level placement=" + ("verified" if observed.get("D3", false) else "unavailable") + "; ",
					"D4":"partial: native short groups keep panel open, DF3D rejects incomplete selections; ",
					"D5":"partial: spike counts not exercised; weapon-count comparison=" + ("match" if observed.get("D5", false) else "unavailable") + "; ",
					"D8":"partial: immediacy comparison=" + ("match" if observed.get("D8", false) else "unavailable") + "; refusal wording parity not established; "}
				if partial.has(id): text = id + ": " + str(partial[id]) + str(finding.line)
				break
		rows.append({"id":id, "text":text})
	# Preserve unresolved subquestions; do not turn one answered part into full parity.
	rows.append({"id":"uncaptured", "text":"D2 metric/reference tile, D3 three-level middle/rebuild, D7 farm footprint, D8 refusal wording: incomplete: evidence missing"})
	for finding in evidence:
		if str(finding.text).contains("Track stop: dump"):
			rows.append({"id":"D5_track_stop", "text":"D5: " + ("all25 profiles read back from native buildings" if observed.get("track_stop_profiles",0)==25 else "incomplete: TrackStop profile matrix") + "; " + finding.line})
		if str(finding.text).contains("Pressure plate: Resets"):
			rows.append({"id":"D5_options", "text":"D5: " + ("12 PressurePlate profiles read back from native buildings; controls and trigger effects incomplete" if observed.get("pressure_plate_profiles",0)==12 else "incomplete: PressurePlate profile matrix") + "; " + finding.line})
		if str(finding.text).contains("5 speeds"):
			var speeds: Array = observed.get("roller_speeds", [])
			var speed_result := "match: all five requested speeds read back from native buildings" if speeds == [10000,20000,30000,40000,50000] else "incomplete: all five native speed readbacks not established"
			rows.append({"id":"D6_speed", "text":"D6: " + speed_result + "; " + finding.line})
	# Discover named native dumps at run time. Compare only explicit material
	# identities/counts/order; absent columns do not imply any native answer.
	var dump_found := false
	var pattern := RegEx.new()
	pattern.compile("`([^`]+\\.(?:json|tsv|csv))`")
	for finding in evidence:
		for matched in pattern.search_all(str(finding.text)):
			if not str(finding.text).to_lower().contains("material"): continue
			dump_found = true
			rows.append({"id":"materials_dump", "text":compare_dump(repo, matched.get_string(1), finding)})
	if not dump_found: rows.append({"id":"materials_dump", "text":"incomplete: evidence missing (no materials dump named in findings)"})
	write_json("departures.json", rows)

func reload_fortress() -> void:
	if stopped: return
	if not fixture.sites.has("depot"):
		incomplete("reload material site unavailable"); return
	var previous: Dictionary = world.poll_session()
	var previous_epoch := int(previous.get("fortress_epoch", 0))
	# Send one read-only materials intent. Its outcome may be terminal or unknown;
	# the handshake never sends it again, including after producer replacement.
	var origin := point(fixture.sites.depot)
	var seq: int = world.management_request("construction", {"action":63, "definition":"TradeDepot", "filter":0, "origin":origin})
	if not check(seq > 0, "pre-reload materials request not sent"): return
	handshake += 1
	write_json("request-%d.json" % handshake, {"op":"reload"})
	var file := FileAccess.open(directory + "/verify.tmp", FileAccess.WRITE)
	file.store_string(str(handshake)); file.close()
	if not check(DirAccess.rename_absolute(directory + "/verify.tmp", directory + "/verify.txt") == OK, "reload handshake rename failed"): return
	var deadline := Time.get_ticks_msec() + 960000
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
	var inprocess: bool = ack.get("route", "restart") == "inprocess"
	if not check(((previous_epoch >> 32) == int(ack.pid)) == inprocess, "reload route/process mismatch"): return
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
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	catalog.clear(); placed.clear()
	await catalog_pages()
	if stopped: return
	var first := await request({"action":63, "definition":"TradeDepot", "filter":0, "origin":point(fixture.sites.depot)})
	if stopped: return
	check(int(first.construction.build_phase) == 1 and int(first.construction.build_done) == 0, "materials did not restart from 0/total")
	if inprocess:
		print("RELOAD_INPROCESS construction materials restarted at 0/total with retained DLL")
		print("RELOAD_DISCLOSURE exact World changed reply and mid-Place reload remain offline-only")
	else:
		print("RELOAD_DISCLOSURE World changed reply and mid-Place reload remain offline-only; live reload replaces the producer")

func exercise() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	if fixture.incomplete.has("all"):
		incomplete(str(fixture.incomplete.all))
		return
	step = "1"
	await catalog_pages()
	if stopped: return
	step = "2"
	if fixture.sites.has("depot"):
		var origin := point(fixture.sites.depot)
		await native("guard_before")
		var page := await materials("TradeDepot", 0, origin, true)
		if not page.is_empty():
			observed_material_rows = page.materials.duplicate(true)
			await native("materials", {"definition":"TradeDepot", "filter":0, "origin":native_point(origin), "rows":page.materials})
			observed.D2 = not stopped and fixture.get("binned", []).size() > 0
		await native("guard_after")
		if not page.is_empty():
			step = "7 stale revision"
			var stale := int(page.list_revision) ^ 1
			if stale == 0: stale = 2
			await guarded({"action":63, "definition":"TradeDepot", "filter":0, "origin":origin, "expected_list_revision":stale}, "List changed; refresh")
	else: incomplete("Trade depot material site unavailable")
	if stopped: return
	step = "3"
	await place("Well", "well")
	for direction in range(4):
		var pump := await place("ScrewPump", "pump" + str(direction), direction)
		await release_site(pump)
	await place("WaterWheel", "wheel")
	for speed in [10000,20000,30000,40000,50000]:
		var roller := await place("Rollers", "pump0", 0, false, Vector3i.ONE, -1, {}, speed)
		if stopped: return
		if not check(not roller.is_empty(), "Roller speed placement prerequisite missing"): return
		print("ROLLER_SPEED_NATIVE_PASS speed=", speed, " ids=", roller.ids)
		if not observed.has("roller_speeds"): observed.roller_speeds = []
		observed.roller_speeds.append(speed)
		await release_site(roller)
	await place("FarmPlot", "farm", 0, false, Vector3i(3, 3, 1))
	for dump in 5:
		for friction in [10,50,500,10000,50000]:
			var profile := {"friction":friction,"dump_direction":dump}
			var stop := await place("Trap:TrackStop", "pump0",0,false,Vector3i.ONE,-1,{},0,profile)
			if stopped: return
			if not check(not stop.is_empty(),"TrackStop profile placement unavailable"): return
			observed.track_stop_profiles = int(observed.get("track_stop_profiles",0))+1
			print("TRACK_STOP_NATIVE_PASS profile=",profile," ids=",stop.ids)
			await release_site(stop)
	# Native defaults/ranges: fixtures/construction/pressure_plate.json.
	var pressure_default := {"units":false,"water":false,"magma":false,"citizens":false,"resets":true,"track":false,
		"unit_min":5000,"unit_max":200000,"water_min":1,"water_max":7,"magma_min":1,"magma_max":7,"track_min":1,"track_max":2000}
	var pressure_profiles: Array[Dictionary] = [pressure_default]
	for flag in ["units","water","magma","citizens","resets","track"]:
		var profile: Dictionary = pressure_default.duplicate()
		profile[flag] = not profile[flag]
		pressure_profiles.append(profile)
	for changes in [{"units":true,"water":true,"magma":true,"citizens":true,"resets":false,"track":true},
		{"units":true,"unit_min":200000,"unit_max":200999}, {"units":true,"unit_min":1000,"unit_max":1999},
		{"water":true,"water_min":0,"water_max":0,"magma":true,"magma_min":0,"magma_max":0,"track":true,"track_min":1,"track_max":1},
		{"track":true,"track_min":2000,"track_max":2000}]:
		var profile: Dictionary = pressure_default.duplicate()
		profile.merge(changes,true)
		pressure_profiles.append(profile)
	for profile in pressure_profiles:
		var plate := await place("Trap:PressurePlate","pump0",0,false,Vector3i.ONE,-1,{},0,{},profile)
		if stopped: return
		if not check(not plate.is_empty(),"PressurePlate profile placement unavailable"): return
		observed.pressure_plate_profiles = int(observed.get("pressure_plate_profiles",0))+1
		print("PRESSURE_PLATE_NATIVE_PASS profile=",profile," ids=",plate.ids)
		await release_site(plate)
	await place("Bridge", "bridge", 2, false, Vector3i(3, 3, 1))
	await place("Bridge", "retracting", 0, true, Vector3i(3, 3, 1))
	var facings := 0
	for family in ["Ballista", "Catapult"]:
		for direction in range(8):
			var siege := await place("SiegeEngine:" + family, family.to_lower() + str(direction), direction)
			if not siege.is_empty(): facings += 1
			await release_site(siege)
	if facings == 16: observed.D6 = true
	var press := ""
	for row in catalog.values():
		if str(row.native_name).to_lower() == "screw press": press = row.key
	if press.is_empty(): incomplete("Screw Press custom raw absent")
	else:
		var press_placement := await place(press, "press")
		if not press_placement.is_empty():
			if not check(press_placement.ids.size() == 1 and int(press_placement.receipt.construction.first_building) == int(press_placement.ids[0]), "custom workshop receipt/native ID mismatch"): return
			for id in press_placement.ids:
				await native("exists", {"id":int(id), "origin":native_point(press_placement.origin), "phase":"step 3 after placement"})
				var inspection := await request({"action":3, "building_id":int(id)})
				if stopped: return
				if not check(int(inspection.building_id) == int(id) and inspection.construction.building_key == press, "placed custom workshop identity mismatch"): return
	step = "3 traps"
	var traps := 0
	for count in [1, 10]:
		var trap := await place("Trap:WeaponTrap", "trap" + str(count), 0, false, Vector3i.ZERO, count)
		if not trap.is_empty(): traps += 1
		await release_site(trap)
	if traps == 2: observed.D5 = true
	for count in [0, 11]:
		var site := "trap" + str(count)
		if not fixture.sites.has(site): incomplete(site + " site missing"); continue
		var origin := point(fixture.sites[site])
		var row: Dictionary = catalog["Trap:WeaponTrap"]
		var query := {"action":1, "definition":"Trap:WeaponTrap", "origin":origin, "width":int(row.width), "height":int(row.height)}
		var preview := await request(query)
		if stopped: return
		var selections := await selection_rows("Trap:WeaponTrap", origin, preview.construction.filters, count)
		if selections.is_empty(): continue
		query.action = 2; query.selections = selections; query.expected_list_revision = int(selections[0].expected_list_revision)
		await guarded(query, "Weapon count must be between 1 and 10")
	if stopped: return
	step = "4"
	if fixture.has("obstacle") and fixture.obstacle != null:
		var o: Dictionary = fixture.obstacle
		step = "4 partial footprint"
		for key in ["Bridge", "RoadPaved"]:
			await guarded({"action":1, "definition":key, "origin":point(o), "width":2, "height":1}, "Building present")
		if not stopped: observed.D7 = true
		step = "4 wall drag"
		var drag := await place("Construction:Wall", "wall", 0, false, Vector3i(int(o.width), 1, 1), -1, o)
		if not drag.is_empty(): observed.D4 = true
	else: incomplete("occupied tile prerequisite absent")
	step = "5"
	if fixture.sites.has("stairs"):
		await guarded({"action":1, "definition":"Construction:Stairs", "origin":point(fixture.sites.stairs)}, "Must span multiple elevations")
		if not (await place("Construction:Stairs", "stairs", 0, false, Vector3i(1, 1, 3))).is_empty(): observed.D3 = true
	else: incomplete("three loaded stair levels unavailable")
	if stopped: return
	step = "7 stale key"
	if placed.is_empty(): incomplete("no placed building for stale-key refusal")
	else:
		var row: Dictionary = placed[0]
		var inspection := await request({"action":3, "building_id":int(row.id)})
		if stopped: return
		await guarded({"action":4, "building_id":int(row.id), "definition":"Chair" if inspection.construction.building_key != "Chair" else "Table"}, "Building changed; inspect again")
	for row in placed:
		await native("exists", {"id":int(row.id), "origin":native_point(row.origin), "phase":"before step 6"})
	if stopped: return
	step = "6"
	var wall := await place("Construction:Wall", "wall")
	# Cancel every queued object, then finish one separate wall for action 6.
	for row in placed:
		if not wall.is_empty() and wall.ids.has(row.id): continue
		var inspection := await request({"action":3, "building_id":int(row.id)})
		if stopped: return
		await request({"action":4, "building_id":int(row.id), "definition":inspection.construction.building_key})
		await native("removed", {"id":int(row.id)})
	if not wall.is_empty() and await wait_wall(wall.origin):
		await request({"action":6, "origin":wall.origin})
		await native("removed_construction", {"origin":native_point(wall.origin)})
	else: incomplete("RemoveConstruction requires a completed wall")
	step = "8"
	await reload_fortress()
	if stopped: return
	step = "final"
	await native("final")

func run() -> void:
	directory = OS.get_environment("DF3D_CONSTRUCTION_ACCEPTANCE")
	if directory.is_empty():
		push_error("Run through tools/smoke/construction_acceptance.ps1 with prepared clone input")
		quit(77)
		return
	lane_deadline_ms = Time.get_ticks_msec() + int(FileAccess.get_file_as_string(directory + "/budget-ms.txt"))
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
	departure_report()
	var status := "failed" if failed else ("incomplete" if not reasons.is_empty() else "passed")
	write_json("result.json", {"status":status, "reasons":reasons})
	print("CONSTRUCTION_ACCEPTANCE ", status, " ", reasons)
	quit(1 if failed else (77 if status == "incomplete" else 0))
