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
	print("WORK_ORDERS_INCOMPLETE ", reasons.back())

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
	var seq: int = world.work_order_request(data)
	if not check(seq > 0, "request not sent: " + world.last_error()): return {}
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var state: Dictionary = world.poll_management()
		if int(state.get("request_seq", 0)) == seq and int(state.get("status", S.Idle)) not in [S.Idle, S.Pending]:
			print("WORK_ORDER_RECEIPT step=", step, " seq=", seq, " ", state)
			if refusal.is_empty():
				if not check(int(state.status) == S.Ok, str(state.get("message", "request failed"))): return {}
			else:
				if not check(int(state.status) == S.Rejected and str(state.get("message", "")) == refusal, "expected refusal: " + refusal): return {}
			return state.get("work_order", {})
		await create_timer(0.01).timeout
	incomplete("receipt wait cap hit; outcome unknown, no replay", true)
	return {}

func inspect(id: int) -> Dictionary:
	var page := await request({"action":21, "id":id})
	if stopped: return {}
	if not check(page.orders.size() == 1, "inspect must return one order"): return {}
	return page.orders[0]

func reload_fortress() -> void:
	var before := await native("status")
	if stopped: return
	var previous: Dictionary = world.poll_session()
	var previous_epoch := int(previous.get("fortress_epoch", 0))
	# Send one read-only materials intent. Its outcome may be terminal or unknown;
	# the handshake never sends it again, including after producer replacement.
	var seq: int = world.work_order_request({"action":26, "candidate_kind":4})
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
	await seed_catalog()
	if stopped: return
	var first := await request({"action":26, "candidate_kind":4})
	if stopped: return
	if not check(int(first.build_phase) == 1 and int(first.build_done) == 0, "materials did not restart from 0/total"): return
	var status := await native("status")
	if stopped: return
	if inprocess:
		if not check(int(before.holding) > 0, "retained-DLL check requires retired native objects"): return
		check(int(status.holding) == int(before.holding), "epoch reset changed DLL-lifetime holding count")
		print("RELOAD_INPROCESS holding=", status.holding, " materials restarted at 0/total")
		print("RELOAD_DISCLOSURE exact World changed/refreshed-catalog refusal remains offline-only")
	else:
		check(int(status.holding) == 0, "holding array survived restart")
		print("RELOAD_DISCLOSURE in-process reset, World changed/refreshed-catalog refusal and holding-still-N remain offline-only")

func edit(action: int, id: int, fields: Dictionary) -> Dictionary:
	var order := await inspect(id)
	if stopped: return {}
	var data := fields.duplicate()
	data.action = action
	data.id = id
	data.expected_revision = order.revision
	return await request(data)

func pages(data: Dictionary, field: String, observe_materials: bool = false) -> Dictionary:
	var rows: Array = []
	var phases: Array = []
	var cursors: Array = []
	var query := data.duplicate()
	var first: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 120000
	var next_status_sample := 0
	while not stopped:
		if Time.get_ticks_msec() >= deadline:
			incomplete(field + " builder/page wait cap hit", true)
			return {}
		var page := await request(query)
		if stopped: return {}
		var phase := int(page.build_phase)
		if phases.is_empty() or phases.back() != phase: phases.append(phase)
		if observe_materials and phase != 0 and Time.get_ticks_msec() >= next_status_sample:
			await native("status")
			next_status_sample = Time.get_ticks_msec() + 1000
			if stopped: return {}
		if phase != 0:
			await create_timer(0.25).timeout
			continue
		if first.is_empty(): first = page.duplicate()
		if not check(not cursors.has(int(query.get("cursor", 0))), "repeated page cursor"): return {}
		cursors.append(int(query.get("cursor", 0)))
		rows.append_array(page[field])
		if int(page.next_cursor) == 0: break
		if not check(int(page.next_cursor) != int(query.get("cursor", 0)), "page cursor did not advance"): return {}
		query.cursor = int(page.next_cursor)
		query.expected_list_revision = int(page.list_revision)
	if observe_materials:
		print("MATERIAL_BUILD_PHASES ", phases)
		if not (phases.front() == 1 and phases.find(2) > 0 and phases.back() == 0):
			incomplete("250 ms sampling did not observe materials read -> sort -> done")
	if not check(rows.size() == int(first.total), field + " total does not match paged rows"): return {}
	first[field] = rows
	return first

func create_order(recipe: String) -> Dictionary:
	var page := await request({"action":22, "recipe":recipe, "remaining":10})
	if stopped: return {}
	if not check(page.orders.size() == 1, "create missing order"): return {}
	var order: Dictionary = page.orders[0]
	if not check(order.total == 10 and order.remaining == 10 and order.frequency == 0 and not order.validated, "create defaults"): return {}
	await native("create", {"id":order.id})
	return order

# Same semantic command and session readback used by session controls.
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

func wait_native(kind: String, id: int) -> bool:
	var start := await native("wait_start", {"kind":kind, "id":id})
	if start.get("status", "") != "passed": return false
	if stopped or not await request_pause(false): return false
	var passed := false
	while not stopped:
		await create_timer(0.25).timeout
		var result := await native("wait_poll")
		if stopped: break
		if not result.get("waiting", false):
			passed = result.status == "passed"
			break
	# Re-pause through SetPause before any mutation/dispatch assertions.
	if not await request_pause(true): return false
	if stopped: return false
	await native("wait_finish", {"passed":passed})
	return passed and not stopped

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
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	step = "1"
	# The model gates every domain on a fresh construction Catalog receipt, as the
	# semantic action service does on (re)connect; seed it once before paging.
	await seed_catalog()
	if stopped: return
	var catalog := await pages({"action":27}, "tasks")
	if stopped: return
	if not check(not catalog.tasks.is_empty() and not catalog.groups.is_empty(), "catalog task/group rows absent"): return
	var recipe := ""
	for task in catalog.tasks:
		if int(task.job_type) == int(fixture.get("preferred_job", -2)):
			recipe = task.key
			break
	if recipe.is_empty():
		incomplete("no bed task available for job dispatch", true)
		return
	var primary := await create_order(recipe)
	var dependent := await create_order(recipe)
	if stopped: return
	var id := int(primary.id)
	var dependent_id := int(dependent.id)
	step = "2"
	var types := await pages({"action":26, "candidate_kind":3}, "types")
	if stopped: return
	if not check(types.types.size() > 128, "Type paging not exercised"): return
	var materials := await pages({"action":26, "candidate_kind":4}, "materials", true)
	if stopped: return
	if not check(materials.materials.size() > 128 and catalog.tasks.size() > 128, "task/material paging not exercised"): return
	var first := await request({"action":20})
	if stopped: return
	# Ensure a real continuation page even in a nearly empty disposable fort.
	while int(first.next_cursor) == 0 and int(first.total) < 17:
		var filler := await create_order(recipe)
		if stopped: return
		await edit(25, int(filler.id), {"condition_kind":0, "compare":0, "threshold":2147483647, "item_type":-1, "traits":[]})
		first = await request({"action":20})
		if stopped: return
	if not check(int(first.next_cursor) > 0, "order list has no continuation"): return
	var spare := await create_order(recipe)
	if stopped: return
	await edit(25, int(spare.id), {"condition_kind":0, "compare":0, "threshold":2147483647, "item_type":-1, "traits":[]})
	await request({"action":20, "cursor":int(first.next_cursor), "expected_list_revision":int(first.list_revision)}, "List changed; refresh")
	if stopped: return
	step = "3"
	var traits := await pages({"action":26, "candidate_kind":5}, "traits")
	if stopped: return
	var totals := {"types":types.types.size(), "materials":materials.materials.size(), "traits":traits.traits.size()}
	write_json("picker-totals.json", {"actual":totals, "expected":{"types":745, "materials":28326, "traits":238}})
	if totals != {"types":745, "materials":28326, "traits":238}:
		incomplete("picker totals differ from region5 evidence: " + str(totals))
	if not check(not traits.traits.is_empty(), "trait rows absent"): return
	var material: Dictionary = {}
	for row in materials.materials:
		if int(row.mat_type) >= 0:
			material = row
			break
	if not check(not material.is_empty(), "material rows absent"): return
	var trait_key: String = traits.traits[0].key
	await edit(25, id, {"condition_kind":0, "compare":0, "threshold":0, "item_type":-1, "mat_type":int(material.mat_type), "mat_index":int(material.mat_index), "traits":[trait_key]})
	if stopped: return
	var order := await inspect(id)
	if stopped: return
	var condition: Dictionary = order.conditions[0]
	if not check(order.frequency == 1 and condition.mat_type == material.mat_type and condition.mat_index == material.mat_index and condition.traits == [trait_key] and condition.estimated, "item condition material/traits/estimate/Daily mismatch"): return
	await native("item", {"id":id, "mat_type":int(material.mat_type), "mat_index":int(material.mat_index), "traits":[trait_key]})
	await edit(25, id, {"condition_kind":0, "condition_index":0, "remove_condition":true})
	await native("removed", {"id":id, "kind":0})
	if stopped: return
	step = "4"
	await edit(25, dependent_id, {"condition_kind":1, "target_order":id, "dependency":1})
	order = await inspect(dependent_id)
	if stopped: return
	await native("dependency", {"id":dependent_id, "target":id, "satisfied":order.conditions[0].satisfied})
	if stopped: return
	if not check(not order.conditions[0].estimated and int(order.conditions[0].satisfaction) == 2, "order condition must use native satisfaction"): return
	await edit(25, dependent_id, {"condition_kind":1, "condition_index":0, "remove_condition":true})
	await native("removed", {"id":dependent_id, "kind":1})
	# Keep the dependent editable while time advances and prove item conditions survive deletion.
	await edit(25, dependent_id, {"condition_kind":0, "compare":0, "threshold":2147483647, "item_type":-1, "traits":[]})
	await edit(25, dependent_id, {"condition_kind":1, "target_order":id, "dependency":1})
	if stopped: return
	step = "5"
	var has_jobs := await wait_native("validated", id)
	if has_jobs: has_jobs = await wait_native("jobs", id)
	if stopped: return
	if has_jobs:
		var move_listing := await pages({"action":20}, "orders")
		order = await inspect(id)
		if stopped: return
		var move_direction := -1 if int(order.position) > 0 else 1
		var neighbor: Dictionary = move_listing.orders[int(order.position) + move_direction]
		await native("move_before", {"id":id})
		await request({"action":23, "id":id, "expected_revision":int(order.revision), "move":move_direction, "expected_neighbor":int(neighbor.id), "expected_list_revision":int(move_listing.list_revision)})
		await native("move_after", {"direction":move_direction})
	if stopped: return
	step = "6"
	var listing := await pages({"action":20}, "orders")
	order = await inspect(id)
	if stopped: return
	var direction := -1 if int(order.position) > 0 else 1
	await native("guard_before")
	# Own id is deliberately not the observed neighbor; list/order revisions are current.
	await request({"action":23, "id":id, "expected_revision":int(order.revision), "move":direction, "expected_neighbor":id, "expected_list_revision":int(listing.list_revision)}, "Neighbor changed; inspect again")
	await native("guard_after")
	if stopped: return
	step = "7"
	# A fresh DF3D order ensures the refusal tests nil inputs, not the active-order gate.
	spare = await create_order(recipe)
	if stopped: return
	await native("guard_before")
	if stopped: return
	step = "7-local"
	var invalid := {"action":23, "id":int(spare.id), "expected_revision":int(spare.revision), "input_index":0}
	var not_sent: int = world.work_order_request(invalid)
	if not check(not_sent == 0 and world.last_error() == "invalid exclusive work order input edit", "expected local not_sent: invalid exclusive work order input edit"): return
	await native("guard_after")
	await native("guard_before")
	step = "7-bridge"
	invalid.mat_type = int(material.mat_type)
	invalid.mat_index = int(material.mat_index)
	await request(invalid, "Order has no editable material input")
	await native("guard_after")
	step = "7"
	var edited := false
	for native_id in fixture.native_ids:
		order = await inspect(int(native_id))
		if stopped: return
		for input in order.inputs:
			if not input.editable: continue
			# Pick an actual material different from the current setting.
			var choice: Dictionary = material
			for row in materials.materials:
				if int(row.mat_type) >= 0 and (row.mat_type != input.mat_type or row.mat_index != input.mat_index):
					choice = row
					break
			var fields := {"input_index":int(input.index), "mat_type":int(choice.mat_type), "mat_index":int(choice.mat_index)}
			await edit(23, int(native_id), fields)
			fields.id = int(native_id)
			await native("details", fields)
			edited = true
			break
		if edited: break
	if not edited: incomplete("no editable native order with inputs")
	if stopped: return
	step = "9"
	if has_jobs:
		# Re-check: all operations since the wait were performed paused.
		order = await inspect(id)
		if stopped: return
		if not check(not order.generated_jobs.is_empty(), "jobs disappeared while paused"): return
		await native("delete_before", {"id":id, "dependent":dependent_id})
		var before := await native("status")
		await request({"action":24, "id":id, "expected_revision":int(order.revision)})
		await native("delete_after", {"dependent":dependent_id})
		var after := await native("status")
		if stopped: return
		if not check(int(after.holding) == int(before.holding) + 2, "delete must hold order plus dependent condition"): return
		await wait_native("completed", id)
	else:
		incomplete("delete-with-jobs and completion lack dispatched-job prerequisite")
	if stopped: return
	step = "10"
	# Deliberately replay a known successful edit with its old receipt, never an unknown outcome.
	order = await inspect(dependent_id)
	if stopped: return
	var stale := {"action":23, "id":dependent_id, "expected_revision":int(order.revision), "remaining":11}
	await request(stale)
	await native("guard_before")
	await request(stale, "Work order changed; inspect again before editing")
	await native("guard_after")
	if stopped: return
	step = "8"
	await reload_fortress()
	if stopped: return
	step = "11"
	# Page again so the export is itself evidence of the model catalog transport.
	catalog = await pages({"action":27}, "tasks")
	if stopped: return
	var file := FileAccess.open(directory + "/tasks.tsv", FileAccess.WRITE)
	for task in catalog.tasks:
		file.store_line("%s\t%d\t%s\t%d\t%d\t%d\t%d" % [task.name, task.job_type, task.reaction, task.item_type, task.item_subtype, task.mat_type, task.mat_index])
	file.close()
	await native("catalog")
	step = "final"
	await native("final")

func run() -> void:
	directory = OS.get_environment("DF3D_WORK_ORDERS_ACCEPTANCE")
	if directory.is_empty():
		push_error("Run through tools/smoke/work_orders_acceptance.ps1 with prepared clone input")
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
	print("WORK_ORDERS_ACCEPTANCE ", status, " ", reasons)
	quit(1 if failed else (77 if status == "incomplete" else 0))
