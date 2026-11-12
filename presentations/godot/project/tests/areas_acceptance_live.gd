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
func request(data: Dictionary, refusal: String = "", expect_rejected := false) -> Dictionary:
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
			if refusal.is_empty() and not expect_rejected:
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
	# Compare the empty fixture and initialized Wood list against DF's row
	# producer. The native builder intentionally skips absent settings entries.
	await pages({"action":9, "id":pile, "operation":1}, "settings")
	var wood := await pages({"action":9, "id":pile, "operation":1, "list_key":"wood"}, "settings")
	if stopped: return
	await native("wood", {"id":pile, "rows":wood.settings})
	await edit(pile,0,{"operation":3,"preset":15})
	await native("preset",{"id":pile,"preset":15,"category":"wood"})
	wood=await pages({"action":9,"id":pile,"operation":1,"list_key":"wood"},"settings")
	await native("wood",{"id":pile,"rows":wood.settings})
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
	# Native painting applies add/erase gestures, never a replacement footprint.
	for parity in [0,1]:
		var desired: Array = []; var removed: Array = []; var expected: Array = []
		for y in range(20):
			for x in range(20):
				var on: bool = (x+y)%2 == int(parity)
				expected.append(1 if on else 0)
				var cell := {"x":int(p.x)+x,"y":int(p.y)+y,"length":1}
				if on: desired.append(cell)
				else: removed.append(cell)
		for gesture in [{"mode":1,"spans":desired},{"mode":2,"spans":removed}]:
			var previous_tiles:int=int(a.tile_count)
			var changed := await request({"action":11,"id":int(a.id),"operation":5,"expected_revision":a.revision,
				"paint_mode":gesture.mode,"paint_z":int(p.z),"spans":gesture.spans})
			if stopped: return
			a = changed.areas[0]
			# A no-op add on the initial full footprint allocates no replacement.
			if int(a.tile_count)!=previous_tiles:retirements += 1
		await native("snapshot",{"id":int(a.id),"expected":{"tile_count":200,"extents":expected}})
	var erase := await request({"action":11, "id":int(a.id), "operation":5, "expected_revision":a.revision,
		"paint_mode":2, "paint_z":int(p.z), "spans":[{"x":int(p.x), "y":int(p.y)+19, "length":20}]})
	if stopped: return
	a = erase.areas[0]; retirements += 1
	await native("snapshot", {"id":int(a.id), "expected":{"tile_count":190}})
	await refusal({"action":11, "id":int(a.id), "operation":5, "expected_revision":a.revision,
		"paint_mode":1, "paint_z":int(p.z)+1, "spans":[spans[0]]}, "Paint must stay on the area's z level")
	var emptied := await request({"action":11,"id":int(a.id),"operation":5,"expected_revision":a.revision,
		"paint_mode":2,"paint_z":int(p.z),"spans":spans})
	if stopped: return
	a = emptied.areas[0]; retirements += 1
	await native("snapshot",{"id":int(a.id),"expected":{"tile_count":0}})
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
		for sort in range(5 if int(entry[1])==1 else 4):
			for descending in [false, true]:
				var reply := await pages({"action":14, "kind":1, "id":id, "operation":14,
					"candidate_kind":entry[1], "sort":sort, "sort_descending":descending}, "candidates")
				if stopped: return
				if int(entry[1])==1:
					var ids:Array=[]
					for row in reply.candidates:ids.append(int(row.id))
					await native("zone_owner_candidates",{"id":id,"ids":ids,"display_rows":reply.candidates,"sort":sort,"descending":descending})
				elif int(entry[1])==2:
					await native("animal_candidates",{"id":id,"rows":reply.candidates,"sort":sort,"descending":descending})
				else:
					await native("candidates", {"id":id, "kind":entry[1], "sort":sort, "descending":descending, "rows":reply.candidates})
				if stopped:return
	await zone_settings_edits()
	if stopped:return
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
	await animal_assignments()
	if stopped: return
	step="native squad assignment effects"
	for test_case in [["Barracks",[1,3,7,15,14,12,8,0,2,0]],["ArcheryRange",[2,0,2,0]]]:
		var target_zone:=zone(str(test_case[0]))
		if target_zone<0 or int(fixture.squad)<0:incomplete("zone/squad prerequisite missing");return
		for use in test_case[1]:
			await native("squad_before",{"id":target_zone,"squad_id":int(fixture.squad)})
			if stopped:return
			await edit(target_zone,1,{"operation":12,"squad_id":int(fixture.squad),"squad_use":use})
			if stopped:return
			await native("squad",{"id":target_zone,"squad_id":int(fixture.squad),"use":use})
			if stopped:return
		await native("squad_finish")
		if stopped:return

func animal_assignments() -> void:
	step = "animal assignment effects"
	var pen := zone("Pen")
	var pond := zone("Pond")
	if not check(pen >= 0 and pond >= 0, "animal zones missing"): return
	var candidates := await pages({"action":14,"kind":1,"id":pen,"operation":14,"candidate_kind":2}, "candidates")
	if stopped: return
	if not check(not candidates.candidates.is_empty(), "animal candidates missing"): return
	await native("animal_candidates",{"id":pen,"rows":candidates.candidates})
	if stopped: return
	await native("animal_restraint_begin",{"unit_id":int(fixture.caged)})
	for variant in 5:
		await native("animal_restraint_material",{"variant":variant})
		var restraint_page := await pages({"action":14,"kind":1,"id":pen,"operation":14,"candidate_kind":2},"candidates")
		if stopped:return
		await native("animal_candidates",{"id":pen,"rows":restraint_page.candidates})
		if stopped:return
	await native("animal_restraint_end",{})
	for candidate in candidates.candidates:
		if not check(candidate.entity == Contract.AreaCandidateEntity.Unit, "unit candidate identity missing"): return
	for key in ["grazer", "caged"]:
		var unit := int(fixture[key])
		if not check(unit >= 0, "animal fixture missing: " + key): return
		await native("assignment_before", {"unit_id":unit})
		await edit(pen,1,{"operation":11,"unit_id":unit,"assign":1})
		await native("assignment",{"id":pen,"unit_id":unit,"assign":true})
		if stopped: return
		var pond_rows := await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2},"candidates")
		if stopped: return
		await native("animal_candidates",{"id":pond,"rows":pond_rows.candidates})
		var eligible := false
		for row in pond_rows.candidates:
			if row.entity == Contract.AreaCandidateEntity.Unit and row.id == unit: eligible = true
		if eligible:
			await edit(pond,1,{"operation":11,"unit_id":unit,"assign":1})
			await native("assignment",{"id":pond,"unit_id":unit,"assign":true})
			await edit(pond,1,{"operation":11,"unit_id":unit,"assign":0})
			await native("assignment",{"id":pond,"unit_id":unit,"assign":false})
		else:
			if not check(key == "grazer","caged transfer fixture must be Pond eligible"): return
			var before := await inspect(pond,1)
			await refusal({"action":11,"kind":1,"id":pond,"operation":11,"unit_id":unit,"assign":1,
				"expected_revision":before.revision},"Invalid area unit assignment")
			await native("assignment",{"id":pen,"unit_id":unit,"assign":true})
			await edit(pen,1,{"operation":11,"unit_id":unit,"assign":0})
			await native("assignment",{"id":pen,"unit_id":unit,"assign":false})
		if stopped: return

func item_assignments() -> void:
	step = "item assignment effects"
	var pond := zone("Pond")
	var item := int(fixture.get("critter",-1))
	if not check(pond>=0 and item>=0,"native critter fixture missing"): return
	var candidates := await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2},"candidates")
	if stopped: return
	await native("animal_candidates",{"id":pond,"rows":candidates.candidates})
	if stopped: return
	var found := false
	for row in candidates.candidates:
		if row.entity == Contract.AreaCandidateEntity.Item and row.id == item: found = true
	if not check(found,"Pond critter item candidate missing"): return
	# Bounded refresh retains typed membership/order and the original receipt.
	for first in candidates.candidates.size():
		var bounded:=await request({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2,
			"candidate_limit":1,"cursor":first,"expected_list_revision":candidates.list_revision})
		if stopped:return
		if not check(bounded.list_revision==candidates.list_revision and bounded.candidates.size()==1,"Animal fact page changed receipt or limit"):return
		var expected:Dictionary=candidates.candidates[first];var actual:Dictionary=bounded.candidates[0]
		if not check(actual.id==expected.id and actual.entity==expected.entity,"Animal fact page changed typed membership"):return
		await native("animal_candidates",{"id":pond,"rows":bounded.candidates,"first":first,"limit":1})
		if stopped:return
	for order in [1,2,3]:
		for descending in [false,true]:
			var ordered := await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2,
				"sort":order,"sort_descending":descending},"candidates")
			if stopped: return
			await native("animal_candidates",{"id":pond,"rows":ordered.candidates,"sort":order,"descending":descending})
			if stopped: return
	for query in ["yak","GRAZER","tame","lovebird","5969","stray","female"]:
		var filtered := await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2,"query":query},"candidates")
		if stopped: return
		await native("animal_candidates",{"id":pond,"rows":filtered.candidates,"query":query})
		if stopped: return
	for bytes in [PackedByteArray(),PackedByteArray([195]),PackedByteArray([195,169]),"GRAZER".to_utf8_buffer(),"lovebird".to_utf8_buffer()]:
		var filtered := await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2,"query_bytes":bytes},"candidates")
		if stopped: return
		if not check(filtered.get("query_bytes")==bytes,"Animal raw query echo differs"):return
		await native("animal_candidates",{"id":pond,"rows":filtered.candidates,"query_bytes":Array(bytes)})
		if stopped:return
	await native("item_assignment_before",{"item_id":item})
	await native("animal_query_name",{"unit_id":int(fixture.caged)})
	var byte_name:=PackedByteArray([195,169]);byte_name.append_array("ByteProbe".to_utf8_buffer())
	var raw_named:=await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2,"query_bytes":byte_name},"candidates")
	if stopped:return
	await native("animal_candidates",{"id":pond,"rows":raw_named.candidates,"query_bytes":Array(byte_name)})
	var raw_found:=false
	for row in raw_named.candidates:
		if int(row.entity)==1 and int(row.id)==int(fixture.caged):raw_found=true
	if not check(raw_found,"Raw animal query did not match native byte name"):return
	var text_named:=await pages({"action":14,"kind":1,"id":pond,"operation":14,"candidate_kind":2,"query":byte_name.get_string_from_utf8()},"candidates")
	if stopped:return
	for row in text_named.candidates:
		if not check(int(row.entity)!=1 or int(row.id)!=int(fixture.caged),"Text animal query reused raw-byte cache"):return
	await native("animal_query_restore",{})
	var source := await inspect(pond,1)
	if stopped: return
	var p: Dictionary = fixture.origin
	var made := await request({"action":10,"kind":1,"zone_type":source.zone_type,
		"origin":Vector3i(int(p.x)+21,int(p.y)+4,int(p.z)),"width":1,"height":1})
	if stopped: return
	var second: int = made.areas[0].id
	var baseline: Dictionary = await inspect(second,1)
	await edit(pond,1,{"operation":11,"item_id":item,"assign":1})
	await native("item_assignment",{"id":pond,"item_id":item,"assign":true})
	if stopped: return
	var assigned := await inspect(pond,1)
	if not check(assigned.assigned_count==source.assigned_count+1 and assigned.revision!=source.revision,"item membership missing from snapshot"): return
	await refusal({"action":11,"kind":1,"id":second,"operation":11,"item_id":item,"assign":0,
		"expected_revision":baseline.revision},"Item assignment changed; inspect again")
	await edit(second,1,{"operation":11,"item_id":item,"assign":1})
	await native("item_assignment",{"id":second,"item_id":item,"assign":true})
	if stopped: return
	await refusal({"action":11,"kind":1,"id":second,"operation":11,"item_id":item,"assign":0,
		"expected_revision":baseline.revision},"Area changed; inspect again")
	var transferred := await inspect(pond,1)
	if not check(transferred.assigned_count==source.assigned_count and transferred.revision!=assigned.revision,"source item transfer not reflected"): return
	await edit(second,1,{"operation":11,"item_id":item,"assign":0})
	await native("item_assignment",{"id":second,"item_id":item,"assign":false})
	if stopped: return
	var cleared := await inspect(second,1)
	check(cleared.assigned_count==baseline.assigned_count,"item clear count differs")
	var refreshed := await pages({"action":14,"kind":1,"id":second,"operation":14,"candidate_kind":2},"candidates")
	if stopped: return
	await native("animal_candidates",{"id":second,"rows":refreshed.candidates})

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

func zone_settings_edits() -> void:
	step = "zone settings"
	for entry in [["Pond", "pond_mode", [1,2]], ["ArcheryRange", "facing", [1,2,3,4]],
		["Tomb", "tomb_citizens", [0,1]], ["Tomb", "tomb_pets", [0,1]],
		["PlantGathering", "gather_trees", [0,1]], ["PlantGathering", "gather_shrubs", [0,1]], ["PlantGathering", "gather_fallen", [0,1]]]:
		var id := zone(entry[0])
		if id < 0: continue
		for value in entry[2]:
			var fields: Dictionary = {}; fields[entry[1]] = value
			await native("zone_settings_guard", {"id":id,"begin":true})
			await edit(id, 1, {"operation":9, "zone_settings":fields})
			if entry[0]=="Pond":fields.check_occupants=true
			await native("zone_settings", {"id":id, "expected":fields})
			await native("zone_settings_guard", {"id":id,"begin":false})
			if stopped: return

	var tomb:=zone("Tomb")
	if tomb>=0 and not stopped:
		await native("tomb_settings_owner",{"id":tomb,"begin":true})
		for key in ["tomb_citizens","tomb_pets"]:
			var current:=await inspect(tomb,1)
			if stopped:return
			var fields: Dictionary={};fields[key]=1-int(current.zone_settings[key])
			await request({"action":11,"kind":1,"id":tomb,"expected_revision":current.revision,"operation":9,"zone_settings":fields},"invalid area edit")
			if stopped:return
		await native("tomb_settings_owner",{"id":tomb,"begin":false})

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
		await native("zone_publication", {"id":int(area.id)})
		var defaults: Dictionary = {"Pen":{"check_occupants":true}, "Pond":{"pond_mode":1,"check_occupants":true}, "ArcheryRange":{"facing":2},
			"Tomb":{"tomb_citizens":1, "tomb_pets":0}, "PlantGathering":{"gather_trees":1, "gather_shrubs":1, "gather_fallen":1}}
		if defaults.has(choice.name): await native("zone_settings", {"id":int(area.id), "expected":defaults[choice.name]})
		await request({"action":12, "kind":1, "id":int(area.id), "expected_revision":area.revision})
		await native("removed", {"id":int(area.id)})
		if stopped: return

func created_archery_directions() -> void:
	step = "native initial archery directions"
	var p: Dictionary = fixture.origin
	var origin := Vector3i(int(p.x)+21,int(p.y)+4,int(p.z))
	var catalog := await request({"action":7})
	if stopped: return
	var kind := -1
	for choice in catalog.choices:
		if choice.name == "ArcheryRange": kind = int(choice.id)
	if not check(kind >= 0, "missing archery type"): return
	# Expected choices are the native-click observations retained in
	# fixtures/areas/native_zone_archery.json, not a second direction algorithm.
	for sample in [["east",1,0,2],["west",-1,0,1],["north",0,-1,3],["south",0,1,4],
		["center",0,0,1],["diagonal",1,1,2],["outside",3,0,2]]:
		step = "initial archery " + str(sample[0])
		await native("archery_prepare", {"target":{"x":origin.x+2+int(sample[1]),"y":origin.y+2+int(sample[2]),"z":origin.z}})
		var made := await request({"action":10,"kind":1,"zone_type":kind,"origin":origin,"width":5,"height":5})
		if stopped: return
		if not check(made.areas.size()==1,"archery creation absent"): return
		var area: Dictionary = made.areas[0]
		check(int(area.zone_settings.facing)==int(sample[3]),"reply direction differs from native")
		await native("zone_settings", {"id":int(area.id),"expected":{"facing":int(sample[3])}})
		await request({"action":12,"kind":1,"id":int(area.id),"expected_revision":area.revision})
		await native("removed", {"id":int(area.id)})
		await native("archery_clear")
		if stopped: return

func created_zone_membership() -> void:
	step = "native zone membership"
	var site := await native("zone_membership_site")
	if stopped: return
	var catalog := await request({"action":7})
	if stopped: return
	var kind := -1
	for choice in catalog.choices:
		if choice.name == "MeetingHall": kind = int(choice.id)
	if not check(kind >= 0,"missing meeting area type"): return
	var made := await request({"action":10,"kind":1,"zone_type":kind,
		"origin":Vector3i(int(site.x),int(site.y),int(site.z)),"width":1,"height":1})
	if stopped: return
	var area: Dictionary = made.areas[0]
	await native("zone_publication", {"id":int(area.id),"member_id":int(site.member_id)})
	for mode in [2,1]:
		var changed := await request({"action":11,"kind":1,"id":int(area.id),"expected_revision":area.revision,
			"operation":5,"paint_mode":mode,"paint_z":int(site.z),"spans":[{"x":int(site.x),"y":int(site.y),"length":1}]})
		if stopped: return
		area = changed.areas[0]
		var observation := await native("zone_publication",{"id":int(area.id)})
		if stopped: return
		if not check(int(observation.members) == (0 if mode == 2 else 1),"repaint membership count"): return
	await request({"action":12,"kind":1,"id":int(area.id),"expected_revision":area.revision})
	await native("removed", {"id":int(area.id)})

func created_zone_location_repaint() -> void:
	step = "native Location repaint refresh"
	var catalog := await request({"action":7})
	if stopped: return
	var kind := -1
	for choice in catalog.choices:
		if str(choice.name)=="MeetingHall": kind=int(choice.id)
	var p: Dictionary=fixture.origin
	var origin:=Vector3i(int(p.x)+25,int(p.y)+4,int(p.z))
	await native("overlap_prepare",{"scenario":"floor","site":{"x":origin.x,"y":origin.y,"z":origin.z}})
	var made:=await request({"action":10,"kind":1,"zone_type":kind,"origin":origin,"width":1,"height":1})
	if stopped:return
	var id:=int(made.areas[0].id)
	await native("zone_location_prepare",{"id":id})
	for mode in [2,1]:
		var current:=await inspect(id,1)
		if stopped:return
		await request({"action":11,"kind":1,"id":id,"expected_revision":current.revision,
			"operation":5,"paint_mode":mode,"paint_z":origin.z,"spans":[{"x":origin.x,"y":origin.y,"length":1}]})
		if stopped:return
		await native("zone_location_result")
	await native("zone_location_clear")
	var current:=await inspect(id,1)
	if stopped:return
	await request({"action":12,"kind":1,"id":id,"expected_revision":current.revision})
	await native("removed",{"id":id})
	await native("overlap_measure",{"require_unchanged":true})
	await native("overlap_clear")

func zone_owner_effects() -> void:
	step = "native zone owner effects"
	var catalog := await request({"action":7})
	if stopped:return
	var kinds := {}
	for choice in catalog.choices:kinds[str(choice.name)]=int(choice.id)
	var p: Dictionary=fixture.origin
	var origin:=Vector3i(int(p.x)+27,int(p.y)+4,int(p.z))
	await request({"action":14,"kind":1},"Unsupported area operation")
	if stopped:return
	var owners:=await native("zone_owner_prepare")
	if stopped:return
	await native("overlap_prepare",{"scenario":"floor","site":{"x":origin.x,"y":origin.y,"z":origin.z}})
	var ids: Array[int]=[]
	for type_name in ["Tomb","Tomb","Bedroom"]:
		var args: Dictionary={"action":10,"kind":1,"zone_type":kinds[type_name],"origin":origin,"width":1,"height":1}
		if type_name=="Bedroom":args.owner_id=int(owners.owner_a)
		var made:=await request(args)
		if stopped:return
		ids.append(int(made.areas[0].id))
	await native("zone_owner_result",{"id":ids[0],"owner":-1,"settings":1,"count_a":0,"count_b":0})
	await native("zone_owner_result",{"id":ids[2],"owner":int(owners.owner_a),"count_a":1,"count_b":1})
	var tomb_extra_owner: int=-1
	for id in ids:
		var candidates:=await pages({"action":14,"operation":14,"kind":1,"id":id,"candidate_kind":1},"candidates")
		if stopped:return
		var candidate_ids: Array=[]
		for candidate in candidates.candidates:candidate_ids.append(int(candidate.id))
		var compared:=await native("zone_owner_candidates",{"id":id,"ids":candidate_ids,"display_rows":candidates.candidates})
		if id==ids[0]:
			tomb_extra_owner=int(compared.nonliving_or_noncitizen)
			var icon_recipes: Array = []
			for candidate in candidates.candidates:
				if int(candidate.id) in [996,998]:
					if not check(candidate.get("sheet_icon") is Dictionary and not candidate.sheet_icon.layers.is_empty(),"inactive/deceased owner recipe missing"):return
					icon_recipes.append({"id":int(candidate.id),"recipe":candidate.sheet_icon})
			if not check(icon_recipes.size()==2,"owner image fixture candidates missing"):return
			write_json("owner-icon-recipes.json",icon_recipes)
	for id in [ids[0],ids[2]]:
		for sort in [1,2,3,4]:
			for descending in [false,true]:
				var candidates:=await pages({"action":14,"operation":14,"kind":1,"id":id,"candidate_kind":1,"sort":sort,"sort_descending":descending},"candidates")
				if stopped:return
				var candidate_ids: Array=[]
				for candidate in candidates.candidates:candidate_ids.append(int(candidate.id))
				await native("zone_owner_candidates",{"id":id,"ids":candidate_ids,"sort":sort,"descending":descending})
	for id in [ids[0],ids[2]]:
		for query in ["miner","MINER","mi","king","mayor",","," ","5981","notfound","er","kubuk","unib","bedroom",""]:
			var candidates:=await pages({"action":14,"operation":14,"kind":1,"id":id,"candidate_kind":1,"query":query},"candidates")
			if stopped:return
			var candidate_ids: Array=[]
			for candidate in candidates.candidates:candidate_ids.append(int(candidate.id))
			await native("zone_owner_candidates",{"id":id,"ids":candidate_ids,"query":query})
	for bytes in [PackedByteArray(),PackedByteArray([195]),PackedByteArray([195,169]),"MINER".to_utf8_buffer(),"x".repeat(33).to_utf8_buffer()]:
		var candidates:=await pages({"action":14,"operation":14,"kind":1,"id":ids[0],"candidate_kind":1,"query_bytes":bytes},"candidates")
		if stopped:return
		if not check(candidates.get("query_bytes")==bytes and candidates.query=="","owner raw query echo differs"):return
		var candidate_ids: Array=[]
		for candidate in candidates.candidates:candidate_ids.append(int(candidate.id))
		await native("zone_owner_candidates",{"id":ids[0],"ids":candidate_ids,"query_bytes":Array(bytes)})
	await native("owner_fact_name",{"unit_id":int(owners.owner_a),"name":"OwnerFactsProbe"})
	var fact_query: Dictionary={"action":14,"operation":14,"kind":1,"id":ids[0],"candidate_kind":1,"query":"OwnerFactsProbe"}
	var fact_initial:=await pages(fact_query,"candidates")
	if stopped:return
	if not check(fact_initial.candidates.size()==1 and int(fact_initial.candidates[0].id)==int(owners.owner_a),"fact probe did not isolate native candidate"):return
	await native("owner_fact_name",{"unit_id":int(owners.owner_a),"name":"OwnerFactsChanged"})
	fact_query.expected_list_revision=int(fact_initial.list_revision)
	var fact_current:=await request(fact_query)
	if stopped:return
	if not check(fact_current.candidates.size()==1 and int(fact_current.candidates[0].id)==int(owners.owner_a) and int(fact_current.list_revision)==int(fact_initial.list_revision),"fact refresh changed retained membership"):return
	if not check(str(fact_current.candidates[0].owner_display.first_line).contains("OwnerFactsChanged"),"retained owner page returned stale native display"):return
	write_json("owner-current-facts.json",{"id":int(owners.owner_a),"revision":int(fact_current.list_revision),"before":fact_initial.candidates[0].owner_display.first_line,"after":fact_current.candidates[0].owner_display.first_line,"membership_retained":true})
	await native("owner_fact_restore")
	var bounded_query := {"action":14,"operation":14,"kind":1,"id":ids[0],"candidate_kind":1}
	var unbounded := await pages(bounded_query,"candidates")
	if stopped:return
	bounded_query.expected_list_revision=int(unbounded.list_revision)
	bounded_query.candidate_limit=18;bounded_query.cursor=5
	var bounded := await request(bounded_query)
	if stopped:return
	if not check(bounded.candidates.size()==18 and int(bounded.next_cursor)==23 and int(bounded.list_revision)==int(unbounded.list_revision),"owner fact page limit changed receipt or cursor"):return
	for index in 18:
		if not check(int(bounded.candidates[index].id)==int(unbounded.candidates[index+5].id),"owner fact page limit changed order"):return
	write_json("owner-bounded-facts.json",{"count":bounded.candidates.size(),"cursor":5,"next_cursor":bounded.next_cursor,"revision":str(bounded.list_revision)})
	# Native reference: assign, replace, transfer, clear bedroom, clear empty bedroom.
	for sample in [[ids[0],int(owners.owner_a),3,1,0],[ids[0],int(owners.owner_b),3,0,1],
		[ids[1],int(owners.owner_b),3,0,1],[ids[2],-1,-1,0,0],[ids[2],-1,-1,0,0]]:
		var current:=await inspect(int(sample[0]),1)
		if stopped:return
		await request({"action":11,"kind":1,"id":int(sample[0]),"owner_id":int(sample[1]),"expected_revision":current.revision})
		if stopped:return
		var expected: Dictionary={"id":int(sample[0]),"owner":int(sample[1]),"count_a":int(sample[3]),"count_b":int(sample[4])}
		if int(sample[2])>=0:expected.settings=int(sample[2])
		await native("zone_owner_result",expected)
		await native("overlap_measure",{"require_unchanged":true})
	await native("zone_owner_result",{"id":ids[0],"owner":-1,"settings":3,"count_a":0,"count_b":0})
	if not check(tomb_extra_owner>=0,"native Tomb candidate outside living citizens required"):return
	var tomb_current:=await inspect(ids[0],1)
	if stopped:return
	await request({"action":11,"kind":1,"id":ids[0],"owner_id":tomb_extra_owner,"expected_revision":tomb_current.revision})
	if stopped:return
	await native("zone_owner_result",{"id":ids[0],"owner":tomb_extra_owner,"settings":3,"count_a":0,"count_b":0})
	# Creation must accept the same native-only candidate and preserve native
	# transfer effects; this candidate was excluded by the old citizen filter.
	var fresh_tomb:=await request({"action":10,"kind":1,"zone_type":kinds.Tomb,"origin":origin,"width":1,"height":1,"owner_id":tomb_extra_owner})
	if stopped:return
	ids.append(int(fresh_tomb.areas[0].id))
	await native("zone_owner_result",{"id":ids[-1],"owner":tomb_extra_owner,"settings":3,"count_a":0,"count_b":0})
	await native("zone_owner_result",{"id":ids[0],"owner":-1,"settings":3,"count_a":0,"count_b":0})

	for id in ids:
		var current:=await inspect(id,1)
		if stopped:return
		await request({"action":12,"kind":1,"id":id,"expected_revision":current.revision})
		if stopped:return
	await native("zone_owner_clear")
	await native("overlap_measure",{"require_unchanged":true})
	await native("overlap_clear")

func created_zone_removal() -> void:
	step = "native zone removal effects"
	var catalog := await request({"action":7})
	if stopped: return
	var zone_type := -1
	for choice in catalog.choices:
		if str(choice.name)=="Bedroom": zone_type=int(choice.id)
	var p: Dictionary = fixture.origin
	var origin := Vector3i(int(p.x)+23,int(p.y)+4,int(p.z))
	await native("overlap_prepare", {"scenario":"floor","site":{"x":origin.x,"y":origin.y,"z":origin.z}})
	var made := await request({"action":10,"kind":1,"zone_type":zone_type,"origin":origin,"width":1,"height":1})
	if stopped: return
	var id := int(made.areas[0].id)
	await native("zone_removal_prepare", {"id":id})
	if stopped: return
	var current := await inspect(id,1)
	if stopped: return
	await request({"action":12,"kind":1,"id":id,"expected_revision":current.revision})
	if stopped: return
	await native("zone_removal_result")
	await native("overlap_measure", {"require_unchanged":true})
	await native("overlap_clear")

func created_zone_overlaps() -> void:
	var catalog := await request({"action":7})
	if stopped: return
	var kinds := {}
	for choice in catalog.choices: kinds[choice.name]=int(choice.id)
	var p: Dictionary = fixture.origin
	var origin := Vector3i(int(p.x)+21,int(p.y)+4,int(p.z))
	for sample in [["floor","MeetingHall",true],["gather","PlantGathering",false],["tomb","Tomb",true],
		["wall","MeetingHall",false],["door","MeetingHall",false]]:
		step = "native overlap " + str(sample[0])
		await native("overlap_prepare", {"scenario":sample[0],"site":{"x":origin.x,"y":origin.y,"z":origin.z}})
		var created: Array = []
		for type in ["Bedroom",str(sample[1])]:
			var made := await request({"action":10,"kind":1,"zone_type":int(kinds[type]),"origin":origin,"width":1,"height":1})
			if stopped: return
			created.append(made.areas[0])
		await native("overlap_result", {"ids":[int(created[0].id),int(created[1].id)],"expected":sample[2]})
		for area in created:
			# The second creation can change the first zone's collision flag/revision.
			var current := await inspect(int(area.id),1)
			if stopped: return
			await request({"action":12,"kind":1,"id":int(area.id),"expected_revision":current.revision})
			await native("removed", {"id":int(area.id)})
		await native("overlap_measure", {"require_unchanged":true})
		await native("overlap_clear")
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
	# Native settings rows complete synchronously; restart must return current
	# fortress facts, not an obsolete incremental-builder progress placeholder.
	if not check(int(first.build_phase)==0 and int(first.build_done)==int(first.build_total),"native settings page incomplete after restart"):return
	await native("wood",{"id":int(fixture.pile),"rows":first.settings})
	if stopped:return
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
	if OS.get_environment("DF3D_ZONE_SETTINGS_AUDIT")=="1":
		await zone_settings_edits()
		if not stopped:await native("final")
		return
	if FileAccess.file_exists(directory + "/zone-animals-only.json"):
		await animal_assignments()
		if not stopped: await item_assignments()
		if not stopped: await native("final")
		return
	if FileAccess.file_exists(directory + "/zone-defaults-only.json"):
		await created_zone_defaults()
		if not stopped: await created_archery_directions()
		if not stopped: await created_zone_membership()
		if not stopped: await created_zone_overlaps()
		if not stopped: await created_zone_removal()
		if not stopped: await zone_owner_effects()
		if not stopped: await created_zone_location_repaint()
		return
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
