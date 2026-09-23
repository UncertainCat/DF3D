extends SceneTree
## Protected live test only. One world object must survive a real unload/reload.
var world
var directory: String
var target: Dictionary
var evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func write_json(name: String, value: Variant) -> void:
	var f := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(value, "  "))
	f.close()

func handshake(stage: String) -> bool:
	write_json("request.json", {"stage": stage})
	var deadline := Time.get_ticks_msec() + 30000
	while not FileAccess.file_exists(directory.path_join("ack-" + stage)):
		if Time.get_ticks_msec() > deadline:
			fail("Native fixture handshake timed out: " + stage)
			return false
		world.poll()
		await create_timer(0.02).timeout
	return true

func ready() -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	world.set_top_z(int(target.tile.z))
	while Time.get_ticks_msec() < deadline:
		world.poll()
		if world.terrain_loaded() and world.live_synchronized() and int(target.unit_id) in world.unit_ids():
			return true
		await create_timer(0.02).timeout
	fail("Recorded session world did not synchronize")
	return false

func designation(priority: int) -> bool:
	var p: Dictionary = target.tile
	var seq: int = world.designate_dig(Rect2i(int(p.x), int(p.y), 1, 1), int(p.z), 0, priority, true, 0, -1)
	var accepted := false
	var deadline := Time.get_ticks_msec() + 20000
	while seq > 0 and Time.get_ticks_msec() < deadline:
		world.poll()
		for receipt in world.drain_command_results():
			if int(receipt.seq) == seq:
				if int(receipt.status) != 0:
					fail("Designation rejected: " + str(receipt))
					return false
				accepted = true
		if accepted:
			for entry in world.designation_tiles(int(p.z)):
				if entry.tile == Vector3i(int(p.x), int(p.y), int(p.z)) and int(entry.priority) == priority and entry.marker:
					return true
		await create_timer(0.02).timeout
	fail("Designation receipt/readback missing")
	return false

func session_result(seq: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 240000
	while seq > 0 and Time.get_ticks_msec() < deadline:
		world.poll()
		var state: Dictionary = world.poll_session()
		if int(state.get("request_seq", 0)) == seq and int(state.get("request_status", 0)) in [2, 3]:
			if int(state.request_status) == 2:
				return state
			fail("Session request failed: " + str(state.get("message")))
			return {}
		await create_timer(0.05).timeout
	fail("Session request timed out")
	return {}

func run() -> void:
	directory = OS.get_environment("DF3D_RECORDED_SESSION")
	if directory.is_empty():
		fail("Protected capture directory required")
		return
	target = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("target.json")))
	world = Df3dWorld.new()
	root.add_child(world)
	if not world.attach():
		fail("Bridge attach failed")
		return
	if not await ready(): return
	var state: Dictionary = world.poll_session()
	evidence = {"initial_save": state.get("active_save_id"), "epoch_before": str(state.get("fortress_epoch")), "generation_before": world.session_generation()}
	if not await handshake("start-before"): return
	if not await designation(2): return
	if not await handshake("stop-before"): return
	state = await session_result(world.save_fortress(true, ""))
	if state.is_empty(): return
	evidence["return_save"] = state.get("saved_save_id", "")
	write_json("lifecycle.json", evidence) # Preserve generated save identity even if a later assertion fails.
	world.poll()
	evidence["generation_menu"] = world.session_generation()
	evidence["menu_units"] = world.unit_count()
	if int(state.get("phase", -1)) != 1 or world.unit_count() != 0 or evidence.generation_menu == evidence.generation_before:
		fail("Unload retained old world or did not reach menu")
		return
	state = await session_result(world.load_fortress(str(evidence.return_save)))
	if state.is_empty(): return
	if not await ready(): return
	evidence["epoch_after"] = str(state.get("fortress_epoch"))
	evidence["generation_after"] = world.session_generation()
	if state.get("active_save_id") != evidence.return_save or evidence.epoch_before == evidence.epoch_after or evidence.epoch_after == "0":
		fail("Reload did not establish a distinct epoch for the exact saved fortress")
		return
	if evidence.generation_after == evidence.generation_menu:
		fail("Reload did not establish a new local generation")
		return
	if not await handshake("start-after"): return
	if not await designation(3): return
	if not await handshake("stop-after"): return
	evidence["same_unit_id_reused"] = int(target.unit_id) in world.unit_ids()
	evidence["completed"] = true
	write_json("lifecycle.json", evidence)
	print("RECORDED_SESSION_LIVE_PASS")
	quit(0)
