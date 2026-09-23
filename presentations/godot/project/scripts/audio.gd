extends Node
# Layer 4 only. No imported/shipped audio: resolve files in the verified install.
signal changed
const TRACKS = [
	["Another Year", "another_year/AY_Full.ogg"],
	["Craftsdwarfship", "craftsdwarfship/CS_Full.ogg"],
	["Drink & Industry", "drink_&_industry/DI_Full.ogg"],
	["Expansive Cavern", "expansive_cavern/EC_Full.ogg"],
	["First Year", "first_year/FY_Full.ogg"],
	["Hill Dwarf", "hill_dwarf/HD_Full.ogg"],
	["Koganusan", "koganusan/KG_Full.ogg"],
	["Mountainhome", "mountainhome/MH_Full.ogg"],
	["Strike the Earth!", "strike_the_earth!/STE_Full.ogg"],
	["Winter Entombs You", "winter_entombs_you/WEY_Full.ogg"]]
const CUES = {
	"click": "clicks/generic-small/click-001.ogg",
	"select": "tab/tab-001.ogg",
	"cancel": "whoosh/whoosh-001.ogg",
	"accepted": "clicks/confirm/click-001.ogg",
	"rejected": "clicks/generic/click-002.ogg"}
var config_path := "user://audio.cfg"
var persist_settings := true
var enabled := false
var muted := false
var music_paused := false
var volumes := {"Master": 0.65, "Music": 0.45, "UI": 0.65, "SFX": 0.65}
var playlist: Array = []
var _fortress_playlist: Array = []
var _title_playlist: Array = []
var _menu := false
var current_path := ""
var now_playing := "Music unavailable"
var music: AudioStreamPlayer
var ui_player: AudioStreamPlayer
var _cues: Dictionary = {}
var sfx: Node3D
var _worker: Thread
var _loading: Array = []
var _fade: Tween
var _switching := false
var _rng := RandomNumberGenerator.new()

static func silent_run() -> bool:
	return DisplayServer.get_name() == "headless" or OS.get_environment("DF3D_SCREENSHOT") != "" or OS.get_environment("DF3D_AUDIO_SILENT") == "1"

func _ready() -> void:
	_rng.randomize()
	for bus in ["Music", "UI", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	music.finished.connect(next_track)
	ui_player = AudioStreamPlayer.new()
	ui_player.bus = "UI"
	ui_player.max_polyphony = 4
	add_child(ui_player)

func start(install_root: String, test_dummy := false, menu := false) -> void:
	# Tests can exercise actual decoding/playback only with a silent driver.
	enabled = not silent_run() or (test_dummy and AudioServer.get_driver_name() == "Dummy")
	persist_settings = persist_settings and not silent_run()
	if sfx == null:
		sfx = preload("res://scripts/sfx_player.gd").new()
		add_child(sfx)
		sfx.configure(install_root, enabled)
	if not enabled:
		now_playing = "Audio silent for automated preview"
		return
	_load_settings()
	for track in TRACKS:
		var path: String = install_root.path_join("data/sound/tracks").path_join(track[1])
		if FileAccess.file_exists(path): playlist.append([track[0], path])
	if playlist.is_empty():
		var fallback := install_root.path_join("data/sound/song_game.ogg")
		if FileAccess.file_exists(fallback): playlist.append(["Dwarf Fortress", fallback])
	for cue in CUES:
		var path := install_root.path_join("data/sound/audio/ui").path_join(CUES[cue])
		if FileAccess.file_exists(path):
			var stream := AudioStreamOggVorbis.load_from_file(path)
			if stream != null: _cues[cue] = stream
	_fortress_playlist = playlist.duplicate()
	var title_path := install_root.path_join("data/sound/song_title.ogg")
	if FileAccess.file_exists(title_path): _title_playlist = [["Dwarf Fortress — Title", title_path]]
	_menu = menu
	if menu and not _title_playlist.is_empty(): playlist = _title_playlist.duplicate()
	next_track()

func set_menu(value: bool) -> void:
	if _menu == value: return
	_menu = value
	if value and sfx != null: sfx.reset_session()
	playlist = (_title_playlist if value and not _title_playlist.is_empty() else _fortress_playlist).duplicate()
	if enabled: next_track()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if persist_settings and config.load(config_path) == OK:
		muted = bool(config.get_value("audio", "muted", false))
		for bus in volumes:
			var value = config.get_value("audio", bus, volumes[bus])
			if (value is float or value is int) and is_finite(float(value)):
				volumes[bus] = clampf(float(value), 0, 1)
	_apply_settings()

func _apply_settings() -> void:
	for bus in volumes:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(volumes[bus], 0.00001)))
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), volumes[bus] <= 0 or (bus == "Master" and muted))

func _save_settings() -> void:
	if not persist_settings: return
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	for bus in volumes: config.set_value("audio", bus, volumes[bus])
	config.save(config_path)

func set_volume(bus: String, value: float) -> void:
	if not volumes.has(bus) or not is_finite(value): return
	volumes[bus] = clampf(value, 0, 1)
	_apply_settings()
	_save_settings()

func set_muted(value: bool) -> void:
	muted = value
	_apply_settings()
	_save_settings()
	changed.emit()

func pause_music(value: bool) -> void:
	music_paused = value
	music.stream_paused = value
	changed.emit()

func cue(kind: String) -> void:
	if not enabled or not _cues.has(kind): return
	ui_player.stream = _cues[kind]
	ui_player.play()

func next_track() -> void:
	if not enabled or _switching: return
	if _fade != null and _fade.is_valid(): _fade.kill()
	if playlist.is_empty():
		now_playing = "No playable music found in this DF install"
		changed.emit()
		return
	_switching = true
	if music.playing and not music_paused:
		_fade = create_tween()
		_fade.tween_property(music, "volume_db", -60.0, 0.5)
		_fade.tween_callback(_begin_load)
	else:
		_begin_load()

func _begin_load() -> void:
	music.stop()
	music.stream = null # only one long compressed track resident at a time
	var candidates := playlist.filter(func(track): return track[1] != current_path)
	if candidates.is_empty(): candidates = playlist
	_loading = candidates[_rng.randi_range(0, candidates.size() - 1)]
	now_playing = "Loading %s..." % _loading[0]
	changed.emit()
	_worker = Thread.new()
	var path: String = _loading[1]
	if _worker.start(func(): return AudioStreamOggVorbis.load_from_file(path)) != OK:
		_worker = null
		_switching = false
		now_playing = "Music unavailable: could not start audio loader"
		changed.emit()

func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive(): return
	var stream = _worker.wait_to_finish()
	_worker = null
	_switching = false
	if not playlist.has(_loading):
		next_track()
		return
	if stream == null:
		playlist.erase(_loading) # bounded failure, never retry a broken file each frame
		next_track()
		return
	current_path = _loading[1]
	now_playing = _loading[0]
	music.stream = stream
	music.volume_db = -60
	music.play()
	music.stream_paused = music_paused
	_fade = create_tween()
	_fade.tween_property(music, "volume_db", 0.0, 0.8)
	changed.emit()

func _exit_tree() -> void:
	if _worker != null: _worker.wait_to_finish()
