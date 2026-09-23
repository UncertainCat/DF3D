extends SceneTree
const Player = preload("res://scripts/sfx_player.gd")
var failures := 0
func check(value: bool, message: String):
	if not value: failures += 1; push_error(message)
func _initialize(): call_deferred("run")
func wait_ready(player):
	var deadline := Time.get_ticks_msec() + 10000
	while not player.catalog_ready and Time.get_ticks_msec() < deadline: await process_frame
	check(player.catalog_ready, "Catalog scan completes")
func run():
	var install := OS.get_environment("DF3D_DF_PATH")
	var player := Player.new()
	root.add_child(player)
	player.configure(install, false)
	await wait_ready(player)
	check(player.catalog.has("combat/melee/metal/hit"), "Installed melee variants indexed")
	check(player.catalog["combat/melee/metal/hit"].size() == 4, "Hit and swing kept separate")
	check(player.catalog.has("actions/dig"), "General action assets indexed")
	check(player.announcements.get("MADE_ARTIFACT") == "announcement/artifact_created", "Native announcement mapping parsed")
	var accepted: Array[Dictionary] = []
	player.cue_started.connect(func(event): accepted.append(event))
	check(player.request("combat/melee/metal/hit", Vector3.ONE, true, 2), "Silent evidence records valid cue")
	check(not player.request("missing"), "Missing asset skipped")
	var silent_deadline := Time.get_ticks_msec() + 2000
	while accepted.is_empty() and Time.get_ticks_msec() < silent_deadline: await process_frame
	check(accepted.size() == 1 and accepted[0].position == Vector3.ONE, "Cue evidence retains position")
	check(player.counters.loads == 1 and accepted[0].has("voice_slot"), "Silent capture shares decode and voice admission")
	for i in 40: player.request("combat/melee/metal/hit", Vector3.ZERO, false, 2)
	check(accepted.size() == 16 and player.counters.dropped > 0, "Silent capture has same bounded polyphony")
	player.queue_free()
	await process_frame
	await process_frame
	check(AudioServer.get_driver_name() == "Dummy", "Playback test uses Dummy driver")
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
	player = Player.new()
	root.add_child(player)
	player.configure(install, true)
	await wait_ready(player)
	player.request("combat/melee/metal/hit", Vector3.ZERO, false)
	var deadline := Time.get_ticks_msec() + 2000
	while player.counters.played == 0 and Time.get_ticks_msec() < deadline: await process_frame
	check(player.counters.played == 1 and player.counters.loads == 1, "Async decode reaches mixer")
	var before: int = player.counters.loads
	for i in 40: player.request("combat/melee/metal/hit", Vector3.ZERO, false)
	check(player.counters.loads == before, "Repeated events reuse stream")
	check(player.counters.dropped > 0, "Polyphony bounded")
	player.request("actions/dig")
	player.reset_session()
	check(player._pending.is_empty(), "Session reset drops delayed audio")
	check(player._voices.all(func(v): return not v.playing) and player._global_voices.all(func(v): return not v.playing), "Session reset stops old voices")
	player.queue_free()
	await process_frame
	await process_frame
	print("SFX_TEST_PASS" if failures == 0 else "SFX_TEST_FAIL")
	quit(0 if failures == 0 else 1)
