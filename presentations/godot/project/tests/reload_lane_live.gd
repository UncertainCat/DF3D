extends SceneTree
const Service = preload("res://scripts/semantic_action_service.gd")
const Contract = preload("res://scripts/management_contract.gd")
var world
var service
var directory: String

func _initialize() -> void:
	call_deferred("run")

func finish(status: String, reason: String) -> void:
	var f := FileAccess.open(directory + "/result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"status":status,"reason":reason})); f.close()
	print("RELOAD_LIVE ", status, " ", reason)
	quit(0 if status == "passed" else (77 if status == "incomplete" else 1))

func run() -> void:
	directory = OS.get_environment("DF3D_RELOAD_LANE")
	if directory.is_empty():
		push_error("Run through tools/smoke/reload_lane_test.ps1")
		quit(77); return
	world = Df3dWorld.new(); root.add_child(world)
	if not world.attach(): finish("incomplete", "initial bridge attach failed"); return
	service = Service.new(); service.configure(world); root.add_child(service)
	# The handshake owns the pause in submissions. Poll the service explicitly
	# only outside it, so recovery cannot send its automatic catalog claim early.
	service.set_process(false)
	var initial_deadline := Time.get_ticks_msec() + 60000
	while not world.terrain_loaded() or not world.poll_management().get("transport_alive", false):
		world.poll()
		if Time.get_ticks_msec() >= initial_deadline: finish("incomplete", "initial mirror unavailable"); return
		await create_timer(0.02).timeout
	for round_index in range(1, 3):
		world.poll()
		# Each new model connection requires a fresh Catalog before other domains.
		var seed: int = service.submit("construction", {"action":0}, Callable())
		var seed_deadline := Time.get_ticks_msec() + 60000
		while service.result(seed).is_empty() and Time.get_ticks_msec() < seed_deadline:
			world.poll(); service.poll()
			await create_timer(0.02).timeout
		if int(service.result(seed).get("status", 0)) != Contract.ManagementStatus.Ok:
			finish("failed", "fresh catalog claim failed"); return
		var previous: Dictionary = world.poll_session()
		var old_epoch := int(previous.get("fortress_epoch", 0))
		var ticket: int = service.submit("work_orders", {"action":27}, Callable())
		service.poll()
		if ticket <= 0 or not service._requests.has(ticket): finish("failed", "pre-reload ticket not queued"); return
		var seq := int(service._requests[ticket].sequence)
		if seq <= 0: finish("failed", "pre-reload request not dispatched"); return
		var file := FileAccess.open(directory + "/verify.tmp", FileAccess.WRITE)
		file.store_string(str(round_index)); file.close()
		if DirAccess.rename_absolute(directory + "/verify.tmp", directory + "/verify.txt") != OK:
			finish("failed", "reload handshake rename failed"); return
		var deadline := Time.get_ticks_msec() + 960000
		var ack: Dictionary = {}
		while ack.is_empty():
			world.poll(); world.poll_session(); world.poll_management()
			for state in ["failed", "incomplete", "ack"]:
				var path := directory + "/%s-%d" % [state, round_index]
				if not FileAccess.file_exists(path): continue
				var response: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
				if state != "ack": finish(state, "reload: " + str(response.reason)); return
				ack = response
			if Time.get_ticks_msec() >= deadline: finish("incomplete", "reload acknowledgement timeout"); return
			await create_timer(0.02).timeout
		var epoch := int(str(ack.epoch))
		if epoch == old_epoch or (epoch >> 32) != int(ack.pid): finish("failed", "reload process/epoch mismatch"); return
		if ((old_epoch >> 32) == int(ack.pid)) != (ack.get("route", "restart") == "inprocess"):
			finish("failed", "reload route changed process ownership unexpectedly"); return
		deadline = Time.get_ticks_msec() + 60000
		var reattached := false
		while Time.get_ticks_msec() < deadline:
			world.poll()
			var session: Dictionary = world.poll_session()
			var management: Dictionary = world.poll_management()
			if int(management.get("world_epoch", 0)) == epoch:
				if int(management.get("request_seq", 0)) == seq:
					finish("failed", "old request sequence appeared after reload"); return
				if int(session.get("fortress_epoch", 0)) == epoch and session.get("paused", false):
					reattached = true; break
			await create_timer(0.02).timeout
		if not reattached: finish("incomplete", "reload: presentation did not reattach"); return
		service.poll()
		var outcome: Dictionary = service.result(ticket)
		if outcome.is_empty() or service._active != 0 or not service._queue.is_empty():
			finish("failed", "reload left an active or queued old ticket"); return
		if int(outcome.get("status", 0)) in [Contract.ManagementStatus.Idle, Contract.ManagementStatus.Pending]:
			finish("failed", "pre-reload ticket has no terminal/unknown outcome"); return
		print("RELOAD_ROUND_PASS round=", round_index, " epoch=", epoch, " outcome=", outcome.get("outcome", "terminal"))
	finish("passed", "two save-free reloads verified")
