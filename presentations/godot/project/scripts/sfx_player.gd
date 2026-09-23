extends Node3D
# A bounded voice pool and asynchronous compressed-stream cache. Event policy
# lives elsewhere. Silent captures still record accepted cues for offline muxing.
signal cue_started(event: Dictionary)
const Catalog = preload("res://scripts/sfx_catalog.gd")
const MAX_VOICES := 16
const MAX_PENDING := 32
const MAX_STREAMS := 96
const MAX_LATENCY_MS := 250
var playback := false
var catalog_ready := false
var catalog: Dictionary = {}
var announcements: Dictionary = {}
var counters := {"requested": 0, "played": 0, "missing": 0, "dropped": 0, "loads": 0}
var _worker: Thread
var _indexing := false
var _loading := ""
var _streams: Dictionary = {}
var _lru: Array[String] = []
var _pending: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _global_voices: Array[AudioStreamPlayer] = []
var _priorities: Array[int] = []
var _voice_ends: Array[float] = []
var _listener: AudioListener3D
var _generation := 0
var _focus := Vector3.ZERO
var _camera_basis := Basis.IDENTITY

func configure(install: String, audible: bool) -> void:
	playback = audible
	_worker = Thread.new()
	_indexing = true
	if _worker.start(func(): return Catalog.scan(install)) != OK:
		_worker = null
		_indexing = false
		catalog_ready = true
	_priorities.resize(MAX_VOICES)
	_priorities.fill(0)
	_voice_ends.resize(MAX_VOICES)
	_voice_ends.fill(0.0)
	if not playback: return
	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.make_current()
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "SFX"
		voice.max_distance = 48
		voice.unit_size = 10
		voice.max_db = 0
		add_child(voice)
		_voices.append(voice)
		var global_voice := AudioStreamPlayer.new()
		global_voice.bus = "SFX"
		add_child(global_voice)
		_global_voices.append(global_voice)

func set_listener(focus: Vector3, camera_basis: Basis) -> void:
	_focus = focus
	_camera_basis = camera_basis
	if _listener != null:
		_listener.global_transform = Transform3D(camera_basis, focus + Vector3.UP * 3)

func request(cue: String, position := Vector3.ZERO, spatial := true, seed_value := 0, priority := 1, gain_db := -8.0, metadata: Dictionary = {}) -> bool:
	counters.requested += 1
	if not catalog_ready or not catalog.has(cue):
		counters.missing += 1
		return false
	var paths: Array = catalog[cue]
	var path: String = paths[posmod(seed_value, paths.size())]
	var event := {"cue": cue, "path": path, "position": position, "spatial": spatial,
		"priority": priority, "variant_seed": seed_value, "gain_db": gain_db, "metadata": metadata.duplicate(),
		"requested_ms": Time.get_ticks_msec(), "generation": _generation}
	var distance := position.distance_to(_focus + Vector3.UP * 3)
	event.mix_gain_db = gain_db + (linear_to_db(minf(1.0, 10.0 / maxf(distance, 0.01))) if spatial else 0.0)
	event.mix_pan = clampf((position - _focus).dot(_camera_basis.x) / maxf(distance, 1.0), -1.0, 1.0) if spatial else 0.0
	if _streams.has(path):
		_touch(path)
		return _play(event, _streams[path])
	if _pending.size() >= MAX_PENDING:
		counters.dropped += 1
		return false
	_pending.append(event)
	return true

func reset_session() -> void:
	_generation += 1
	_pending.clear()
	_voice_ends.fill(0.0)
	for voice in _voices: voice.stop()
	for voice in _global_voices: voice.stop()

func _touch(path: String) -> void:
	_lru.erase(path)
	_lru.append(path)

func _play(event: Dictionary, stream: AudioStream) -> bool:
	if stream == null or event.generation != _generation:
		counters.dropped += 1
		return false
	var now := Time.get_ticks_usec() / 1000000.0
	var slot := -1
	for i in MAX_VOICES:
		if _voice_ends[i] <= now:
			slot = i
			break
	if slot < 0:
		for i in MAX_VOICES:
			if _priorities[i] < event.priority: slot = i; break
	if slot < 0:
		counters.dropped += 1
		return false
	_priorities[slot] = event.priority
	_voice_ends[slot] = now + stream.get_length()
	event.voice_slot = slot
	event.duration = stream.get_length()
	if playback:
		_voices[slot].stop()
		_global_voices[slot].stop()
		var voice = _voices[slot] if event.spatial else _global_voices[slot]
		voice.stream = stream
		voice.volume_db = event.gain_db
		if event.spatial: voice.global_position = event.position
		voice.play()
	counters.played += 1
	cue_started.emit(event)
	return true

func _process(_delta: float) -> void:
	if _worker != null and not _worker.is_alive():
		var value = _worker.wait_to_finish()
		_worker = null
		if _indexing:
			catalog = value.cues
			announcements = value.announcements
			_indexing = false
			catalog_ready = true
		else:
			_streams[_loading] = value # Cache failures too; no repeated decoding.
			_touch(_loading)
			while _lru.size() > MAX_STREAMS: _streams.erase(_lru.pop_front())
			_loading = ""
	if _indexing or _pending.is_empty(): return
	var retained: Array[Dictionary] = []
	for event in _pending:
		if event.generation != _generation or Time.get_ticks_msec() - event.requested_ms > MAX_LATENCY_MS:
			counters.dropped += 1
		elif _streams.has(event.path):
			_touch(event.path)
			_play(event, _streams[event.path])
		else: retained.append(event)
	_pending = retained
	if _worker == null and not _pending.is_empty():
		_loading = _pending[0].path
		var path := _loading
		_worker = Thread.new()
		counters.loads += 1
		if _worker.start(func(): return AudioStreamOggVorbis.load_from_file(path)) != OK:
			_worker = null
			_streams[path] = null

func _exit_tree() -> void:
	if _worker != null: _worker.wait_to_finish()
