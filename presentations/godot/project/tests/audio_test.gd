extends SceneTree
const Audio = preload("res://scripts/audio.gd")
const Selection = preload("res://scripts/interaction_state.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func await_load(audio: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while audio._switching and Time.get_ticks_msec() < deadline:
		await create_timer(0.025).timeout
	check(not audio._switching, "bounded async loading completed")

func run() -> void:
	root.size = Vector2i(1600, 900)
	check(AudioServer.get_driver_name() == "Dummy", "audio tests require Dummy driver")
	var state := Selection.new()
	state.submitted(7, "dig")
	check(state.receive([{"seq": 8, "status": 0}]).is_empty(), "unrelated command produces no cue")
	check(state.receive([{"seq": 7, "status": 0, "message": "ok"}, {"seq": 7, "status": 0}]) == [0], "matched result produces exactly one success cue")
	state.submitted(9, "dig")
	check(state.receive([{"seq": 9, "status": 1, "message": "no"}]) == [1], "rejected result distinct")
	var silent := Audio.new()
	root.add_child(silent)
	silent.start("missing")
	check(not silent.enabled and not silent.persist_settings, "headless defaults silent without config mutation")
	var panel := preload("res://scripts/audio_panel.gd").new()
	panel.audio = silent
	root.add_child(panel)
	panel.panel.show()
	await process_frame
	check(root.get_visible_rect().encloses(panel.panel.get_global_rect()), "audio popover stays in viewport")
	check(panel.blocks_camera(), "open popover blocks held movement keys")
	panel.mute.toggled.emit(true)
	check(silent.muted, "mute UI connected")
	panel.pause.pressed.emit()
	check(silent.music_paused, "music pause UI connected")
	panel.free()
	silent.free()
	var audio := Audio.new()
	root.add_child(audio)
	audio.start("missing", true)
	check(audio.playlist.is_empty() and audio.now_playing.contains("No playable"), "missing audio graceful")
	check(not audio._switching, "missing audio no retry loop")
	audio.config_path = "user://df3d_audio_test_temporary.cfg"
	audio.persist_settings = true # explicitly isolated test file, never user settings
	audio.set_volume("Music", 0.2)
	audio.set_muted(true)
	var config := ConfigFile.new()
	check(config.load(audio.config_path) == OK and config.get_value("audio", "Music") == 0.2, "settings written")
	audio.volumes.Music = 0.9
	audio.muted = false
	audio._load_settings()
	check(audio.volumes.Music == 0.2 and audio.muted, "settings roundtrip")
	check(AudioServer.is_bus_mute(0), "master mute applied")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio.config_path))
	audio.persist_settings = false
	audio.set_muted(false)
	audio.set_volume("Music", 0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "zero gain true mute")
	audio.set_volume("Music", 1.5)
	check(audio.volumes.Music == 1, "gain clamp")
	audio.free()
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.assets_root() == "", "root unavailable before validation")
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "licensed install available for runtime decoding")
	audio = Audio.new()
	root.add_child(audio)
	audio.start(world.assets_root(), true)
	await await_load(audio)
	check(audio.playlist.size() == 10, "full fortress tracks only")
	check(audio.music.stream != null and audio.music.stream.get_length() > 60, "full music Ogg decoded")
	await create_timer(0.3).timeout
	check(audio.music.get_playback_position() > 0.05, "music playback advances on Dummy mixer")
	audio.pause_music(true)
	var position: float = audio.music.get_playback_position()
	await create_timer(0.15).timeout
	check(absf(audio.music.get_playback_position() - position) < 0.05, "music pause holds position")
	var old: String = audio.current_path
	audio.next_track()
	await await_load(audio)
	check(audio.current_path != old and audio.music.stream_paused, "skip no repeat, preserves music pause")
	audio.pause_music(false)
	old = audio.current_path
	audio.music.finished.emit()
	await await_load(audio)
	check(audio.current_path != old, "finished advances playlist")
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index("UI"), capture)
	audio.cue("accepted")
	await create_timer(0.4).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in samples: peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	check(peak > 0.00001, "licensed confirmation Ogg produces nonzero PCM through UI bus")
	AudioServer.remove_bus_effect(AudioServer.get_bus_index("UI"), 0)
	audio.set_menu(true)
	await await_load(audio)
	check(audio.current_path.ends_with("song_title.ogg") and audio.playlist.size() == 1, "menu selects installed title music in same player")
	audio.set_menu(false)
	await await_load(audio)
	check(not audio.current_path.ends_with("song_title.ogg") and audio.playlist.size() == 10, "entering fort restores fortress music")
	audio.free()
	world.free()
	# AudioServer retires playback references on its mixer cycle after node teardown.
	await create_timer(0.1).timeout
	if failures == 0: print("audio tests: PASS")
	quit(0 if failures == 0 else 1)
