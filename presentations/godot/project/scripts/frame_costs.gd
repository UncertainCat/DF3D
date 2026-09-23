extends RefCounted
# Opt-in detailed profiling. An independently configured hitch recorder may
# request coarse timers while detailed profiling remains off.
const MAX_SAMPLES := 4096
const MAX_STAGES := 64
const MAX_EVENTS := 32768
var mode := configured_mode()
var enabled: bool = mode != "off"
var _stages: Dictionary = {}
var _events: Array = []
var _dropped_events := 0
var _evicted_through_us := 0.0
var _trace_count := 0
var _dropped_stages := 0
var _clock_offset := 0.0
var _thread_id := 1
var _lifecycle: Node
var hitches

static func configured_mode() -> String:
	if OS.has_environment("DF3D_PROFILE"):
		var value := OS.get_environment("DF3D_PROFILE")
		return value if value in ["basic", "deep"] else "off"
	return "basic" if OS.get_environment("DF3D_STAGE_PROFILE") == "1" else "off"

func configure(world) -> void:
	if not enabled: return
	# Align Godot's startup-relative clock with the native monotonic trace clock.
	var before := Time.get_ticks_usec()
	var native: float = world.profiling_clock_usec()
	_clock_offset = native - (before + Time.get_ticks_usec()) * 0.5
	if mode == "deep":
		_thread_id = int(world.profiling_trace().thread_id)
		if not is_instance_valid(_lifecycle):
			_lifecycle = preload("res://scripts/frame_lifecycle_probe.gd").new()
			_lifecycle.recorder = self
			world.add_child(_lifecycle)

func start(detailed := false) -> int:
	var coarse_hitches: bool = not detailed and hitches != null and hitches.enabled
	return Time.get_ticks_usec() if coarse_hitches or (enabled and (not detailed or mode == "deep")) else 0

func mark(stage: String, since: int, detailed := false) -> int:
	var coarse_hitches: bool = not detailed and hitches != null and hitches.enabled
	if not coarse_hitches and (not enabled or (detailed and mode != "deep")): return 0
	var now := Time.get_ticks_usec()
	if since > 0:
		if coarse_hitches: hitches.record(stage, since, now - since)
		if enabled and (not detailed or mode == "deep"): record(stage, since, now - since)
	return now

func record(stage: String, timestamp: int, duration: int) -> void:
	if not enabled: return
	if not _stages.has(stage):
		if _stages.size() >= MAX_STAGES:
			_dropped_stages += 1
			return
		_stages[stage] = {"values": [], "count": 0, "total_ms": 0.0, "max_ms": 0.0}
	var entry: Dictionary = _stages[stage]
	var ms := maxf(0.0, duration / 1000.0)
	var values: Array = entry.values
	if values.size() < MAX_SAMPLES: values.append(ms)
	else: values[entry.count % MAX_SAMPLES] = ms
	entry.count += 1
	entry.total_ms += ms
	entry.max_ms = maxf(entry.max_ms, ms)
	if mode == "deep":
		var event := {"name": stage, "cat": "script", "ph": "X", "pid": 1,
			"tid": _thread_id, "ts": timestamp + _clock_offset, "dur": maxi(0, duration)}
		if _events.size() < MAX_EVENTS: _events.append(event)
		else:
			var evicted: Dictionary = _events[_trace_count % MAX_EVENTS]
			_evicted_through_us = maxf(_evicted_through_us, evicted.ts + evicted.dur)
			_events[_trace_count % MAX_EVENTS] = event
			_dropped_events += 1
		_trace_count += 1

func cursor() -> Dictionary:
	var result := {}
	for stage in _stages: result[stage] = _stages[stage].count
	return result

func since(previous: Dictionary) -> Dictionary:
	var result := {}
	for stage in _stages:
		var entry: Dictionary = _stages[stage]
		var first := maxi(int(previous.get(stage, 0)), entry.count - MAX_SAMPLES)
		var values: Array = []
		for index in range(first, entry.count): values.append(entry.values[index % MAX_SAMPLES])
		result[stage] = values
	return result

func summary() -> Dictionary:
	var result := {}
	for stage in _stages:
		var entry: Dictionary = _stages[stage]
		var recent: Array = entry.values.duplicate()
		recent.sort()
		result[stage] = {"count": entry.count, "total_ms": entry.total_ms,
			"mean_ms": entry.total_ms / entry.count, "max_ms": entry.max_ms,
			"recent_p50_ms": recent[int(recent.size() * 0.5)],
			"recent_p95_ms": recent[int(recent.size() * 0.95)],
			"recent_p99_ms": recent[int(recent.size() * 0.99)],
			"retained_samples": entry.values.size(), "discarded_samples": maxi(0, entry.count - MAX_SAMPLES)}
	return {"mode": mode, "stages": result, "dropped_events": _dropped_events,
		"dropped_stage_samples": _dropped_stages, "retained_events": _events.size()}

func write_capture(world, destination := "") -> String:
	if not enabled: return ""
	if destination.is_empty(): destination = OS.get_environment("DF3D_PROFILE_OUT")
	if destination.is_empty(): destination = "user://profiles/capture-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	var prefix := ProjectSettings.globalize_path(destination)
	if DirAccess.make_dir_recursive_absolute(prefix.get_base_dir()) != OK:
		push_warning("Cannot create profiling output directory: " + prefix)
		return ""
	var data := summary()
	data["schema_version"] = 1
	data["engine"] = Engine.get_version_info().string
	data["source"] = world.source_name()
	data["top_z"] = world.get_top_z()
	data["window_depth"] = world.get_window_depth()
	data["native"] = world.presentation_perf_stats()
	if is_instance_valid(_lifecycle): data["frame_lifecycle"] = _lifecycle.stats()
	data["recent_samples_ms"] = since({})
	var file := FileAccess.open(prefix + ".profile.json", FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write profiling capture: " + prefix)
		return ""
	file.store_string(JSON.stringify(data))
	file.close()
	if mode == "deep":
		var trace: Dictionary = world.profiling_trace()
		for index in range(maxi(0, _trace_count - MAX_EVENTS), _trace_count):
			trace.traceEvents.append(_events[index % MAX_EVENTS])
		trace.traceEvents.sort_custom(func(a, b): return a.ts < b.ts if a.ts != b.ts else a.dur > b.dur)
		trace["script_dropped_events"] = _dropped_events
		trace["script_evicted_through_us"] = _evicted_through_us
		trace["displayTimeUnit"] = "ms"
		if is_instance_valid(_lifecycle): trace["frame_lifecycle"] = _lifecycle.stats()
		file = FileAccess.open(prefix + ".trace.json", FileAccess.WRITE)
		if file == null:
			push_warning("Cannot write profiling trace: " + prefix)
			return prefix + ".profile.json"
		file.store_string(JSON.stringify(trace))
		file.close()
	return prefix + ".profile.json"
