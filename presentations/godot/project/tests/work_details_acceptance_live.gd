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

var fixture: Dictionary
var custom := -1
var holding := -1
var count_before := 0
var lane_deadline_ms := 0

func budget_ok() -> bool:
	if Time.get_ticks_msec() < lane_deadline_ms: return true
	incomplete("lane wait cap hit; remaining steps not run", true)
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
	print("WORK_DETAILS_INCOMPLETE ", reasons.back())

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(directory + "/" + path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func native(op: String, args: Dictionary = {}) -> Dictionary:
	var cleanup := op in ["guard_after", "wait_finish", "final"]
	if stopped and not cleanup: return {}
	if not cleanup and not budget_ok(): return {}
	handshake += 1
	var request := args.duplicate()
	request.op = op
	request.step = step
	write_json("request-%d.json" % handshake, request)
	var file := FileAccess.open(directory + "/verify.tmp", FileAccess.WRITE)
	file.store_string(str(handshake))
	file.close()
	if not check(DirAccess.rename_absolute(directory + "/verify.tmp", directory + "/verify.txt") == OK, "verify handshake rename failed"): return {}
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
	if stopped or not budget_ok(): return {}
	if int(data.get("action", 0)) == 65:
		var focus := await native("focus")
		if focus.get("status", "") != "passed": return {"skipped":true}
	world.poll()
	var seq: int = world.management_request("citizens", data)
	if not check(seq > 0, "request not sent: " + world.last_error()): return {}
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if not budget_ok(): return {}
		world.poll()
		var state: Dictionary = world.poll_management()
		if int(state.get("request_seq", 0)) == seq and int(state.get("status", S.Idle)) not in [S.Idle, S.Pending]:
			print("WORK_DETAIL_RECEIPT step=", step, " seq=", seq, " ", state)
			if refusal.is_empty():
				if not check(int(state.status) == S.Ok, str(state.get("message", "request failed"))): return {}
			else:
				if not check(int(state.status) == S.Rejected and str(state.get("message", "")) == refusal, "expected refusal: " + refusal): return {}
			return state.get("citizen", {})
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

func pages(action: int, field: String) -> Dictionary:
	# Exercise encoder defaults explicitly: empty fields are absent, -1 is unset.
	var query := {"action":action, "unit_id":-1, "detail_index":-1,
		"member":-1, "mode":-1, "only_assigned":-1, "edit":0,
		"expected_revision":0, "expected_list_revision":0, "cursor":0,
		"name":"", "labors":[], "query":""}
	var rows: Array = []
	var seen: Array = []
	var last: Dictionary = {}
	while not stopped:
		var page := await request(query)
		if stopped: return {}
		last = page
		rows.append_array(page[field])
		var cursor := int(page.next_cursor)
		if cursor == 0: break
		if not check(not seen.has(cursor), "repeated page cursor"): return {}
		seen.append(cursor)
		query.cursor = cursor
		if action == 30: query.expected_list_revision = int(page.detail_list_revision)
	last[field] = rows
	return last

func inspect(index: int) -> Dictionary:
	var page := await request({"action":31, "detail_index":index})
	if stopped: return {}
	if not check(page.details.size() == 1, "detail inspect shape"): return {}
	return page.details[0]

func mutate(index: int, action: int, fields: Dictionary = {}, refusal: String = "") -> Dictionary:
	if not refusal.is_empty() and not fixture.guard_available:
		incomplete("no tile anchor for refusal guard: " + refusal)
		return {"skipped":true}
	var row := await inspect(index)
	if stopped: return {}
	var data := fields.duplicate()
	data.action = action
	data.detail_index = index
	data.expected_revision = int(row.revision)
	if not refusal.is_empty(): await native("guard_before")
	var page := await request(data, refusal)
	if not refusal.is_empty(): await native("guard_after")
	return page

func drain(index: int, running: bool = false) -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while not stopped:
		var page := await request({"action":31, "detail_index":index})
		if stopped: break
		if not check(str(page.recalc_error).is_empty(), str(page.recalc_error)): break
		if int(page.recalc_done) == int(page.recalc_total): break
		if running:
			var sample := await native("wait_poll")
			await native("status")
			if sample.get("status", "") != "passed":
				stopped = true
				break
		if Time.get_ticks_msec() >= deadline:
			incomplete("recalculation wait cap hit", true)
			break
		await create_timer(0.25).timeout

func step_one() -> void:
	var page := await pages(30, "details")
	if stopped: return
	count_before = page.details.size()
	# Revisions stay int64 in the model command path, never in JSON readback files.
	var rows: Array = []
	for detail in page.details:
		var row: Dictionary = detail.duplicate()
		row.erase("revision")
		rows.append(row)
	await native("builtins", {"rows":rows})
	var status := await native("status")
	if stopped: return
	holding = int(status.counters.holding)

func step_two() -> void:
	var list := await request({"action":30})
	if stopped: return
	var page := await request({"action":64, "expected_revision":int(list.detail_list_revision)})
	if stopped: return
	custom = int(page.selected_detail)
	if not check(custom >= 0, "Add selected detail"): return
	await native("created", {"detail_index":custom})
	var name40 := "ABCDEFGHI1ABCDEFGHI2ABCDEFGHI3ABCDEFGHI4"
	await mutate(custom, 66, {"edit":1, "name":name40})
	await native("detail", {"detail_index":custom, "expected":{"name":name40}})
	await mutate(custom, 66, {"edit":1, "name":name40 + "X"}, "Work-detail names are limited to 40 characters")
	await mutate(custom, 66, {"edit":1, "name":""})
	await native("detail", {"detail_index":custom, "expected":{"name":""}})
	# Empty and omitted labor vectors both mean clear; only native recalculation writes unit labors.
	await mutate(custom, 66, {"edit":2, "labors":[]})
	await drain(custom)
	await native("detail", {"detail_index":custom, "expected":{"labors":[]}})
	await mutate(custom, 66, {"edit":2, "labors":[int(fixture.carpentry)]})
	await drain(custom)
	await native("detail", {"detail_index":custom, "expected":{"labors":[int(fixture.carpentry)]}})
	if int(fixture.member) >= 0:
		await mutate(custom, 32, {"unit_id":int(fixture.member), "member":1})
		await native("detail", {"detail_index":custom, "expected":{"assigned_units":[int(fixture.member)]}})

func step_three() -> void:
	var index := int(fixture.miners)
	if index < 0: return
	var row := await inspect(index)
	if stopped: return
	if not row.labors.has(0):
		incomplete("MINERS has no MINE bit to preserve in this save")
		return
	var picker: Array = []
	for id in row.labors:
		if int(id) not in [0, 10, 44]: picker.append(int(id))
	if not picker.has(int(fixture.carpentry)): picker.append(int(fixture.carpentry))
	picker.sort()
	var expected := picker.duplicate()
	for id in row.labors:
		if int(id) in [0, 10, 44]: expected.append(int(id))
	expected.sort()
	await mutate(index, 66, {"edit":2, "labors":picker})
	await drain(index)
	await native("detail", {"detail_index":index, "expected":{"labors":expected, "name":row.name}})
	await mutate(index, 66, {"edit":2, "labors":[0]}, "Labor 0 is not in the native labor picker")
	await mutate(index, 65, {}, "Use Reset to default for built-in work details")
	await mutate(index, 66, {"edit":3})
	await drain(index)
	await native("detail", {"detail_index":index, "expected":{"labors":[0], "name":row.name, "icon":row.icon, "mode":row.mode, "assigned_units":row.assigned_units}})

func step_four() -> void:
	var id := int(fixture.scope)
	if id < 0: return
	await native("scope_before")
	for flag in [1, 0]:
		var page := await request({"action":29, "unit_id":id})
		if stopped: return
		if not check(page.citizens.size() == 1, "citizen inspect shape"): return
		await request({"action":67, "unit_id":id, "only_assigned":flag, "expected_revision":int(page.citizens[0].revision)})
		await native("scope", {"only_assigned":flag})

func step_five() -> void:
	var page := await pages(28, "citizens")
	if stopped: return
	var ids: Array = []
	for row in page.citizens: ids.append(int(row.id))
	await native("roster", {"ids":ids})

func step_six() -> void:
	var index := int(fixture.mode_detail)
	if index < 0: return
	var row := await inspect(index)
	if stopped: return
	if not check(int(row.mode) == 1, "mode must start at Everybody"): return
	var start := await native("wait_start")
	if stopped or start.get("status", "") != "passed": return
	if not await request_pause(false):
		await request_pause(true)
		return
	await request({"action":33, "detail_index":index, "mode":3, "expected_revision":int(row.revision)})
	await drain(index, true)
	# Pause even after failed receipts or exhausted wait caps.
	await request_pause(true)
	await native("wait_finish")
	await native("status")
	await native("detail", {"detail_index":index, "expected":{"mode":3}})

func step_seven() -> void:
	if custom < 0: return
	if not fixture.guard_available:
		incomplete("no tile anchor for refusal guards")
		return
	var row := await inspect(custom)
	var list := await request({"action":30})
	if stopped: return
	await native("rename_out_of_band", {"detail_index":custom})
	await native("guard_before")
	await request({"action":66, "detail_index":custom, "edit":1, "name":"stale", "expected_revision":int(row.revision)}, "Work-detail contents changed; refresh before editing")
	await native("guard_after")
	await native("guard_before")
	# Cursor 16 is the second-page boundary even when the saved list is shorter.
	await request({"action":30, "cursor":16, "expected_list_revision":int(list.detail_list_revision)}, "List changed; refresh")
	await native("guard_after")

func step_eight() -> void:
	if custom < 0: return
	var receipt := await mutate(custom, 65)
	if receipt.get("skipped", false): return
	if stopped: return
	var status := await native("status")
	if stopped: return
	if not check(int(status.counters.holding) == holding + 1, "holding must increase by one"): return
	await native("deleted", {"count":count_before})

func exercise() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	for missing in fixture.missing:
		reasons.append("step %s: %s" % [int(missing.step), missing.reason])
	await seed_catalog()
	for number in range(1, 9):
		if stopped: break
		step = str(number)
		match number:
			1: await step_one()
			2: await step_two()
			3: await step_three()
			4: await step_four()
			5: await step_five()
			6: await step_six()
			7: await step_seven()
			8: await step_eight()
	step = "9"
	incomplete(FileAccess.get_file_as_string(directory + "/reload.txt").strip_edges())
	step = "final"
	await native("final")

func run() -> void:
	directory = OS.get_environment("DF3D_WORK_DETAILS_ACCEPTANCE")
	if directory.is_empty():
		push_error("Run through tools/smoke/work_details_acceptance.ps1 with prepared clone input")
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
		var ready := false
		while not stopped and Time.get_ticks_msec() < deadline:
			world.poll()
			if world.poll_management().get("transport_alive", false):
				ready = true
				break
			await create_timer(0.01).timeout
		if not stopped and not ready: incomplete("management transport wait cap hit", true)
		if not stopped: await exercise()
	var status := "failed" if failed else ("incomplete" if not reasons.is_empty() else "passed")
	write_json("result.json", {"status":status, "reasons":reasons})
	print("WORK_DETAILS_ACCEPTANCE ", status, " ", reasons)
	quit(1 if failed else (77 if status == "incomplete" else 0))
