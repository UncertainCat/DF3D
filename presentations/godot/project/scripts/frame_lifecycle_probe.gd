extends Node
# Deep-only CPU wall-clock boundaries, NOT GPU completion or CPU sampling.
# RenderingServer signals bracket viewport updates. The gaps may include waits.
var recorder
var _phase := 0
var _last := 0
var _late := 0
var unexpected_boundaries := 0
var process_boundaries := 0
var draw_boundaries := 0
var foreign_thread_boundaries := 0
var _sync_enabled := OS.get_environment("DF3D_SYNC_PROBE") == "1"
var _cpu_enabled := OS.get_environment("DF3D_CPU_BOUNDARIES") == "1"
var _late_cpu := {}
var _pre_cpu := {}
var _cpu_gaps := {"late_to_pre_draw": [], "pre_draw_to_process": []}

func _cpu_gap(name: String, start: int, finish: int, before: Dictionary, after: Dictionary) -> void:
	if before.is_empty() or after.is_empty(): return
	var wall := (finish - start) / 1000.0
	if wall < 10.0: return
	var cpu := -1.0 if before.thread_cpu_ms < 0 or after.thread_cpu_ms < before.thread_cpu_ms else float(after.thread_cpu_ms - before.thread_cpu_ms)
	var cycles: int = -1 if before.thread_cycles < 0 or after.thread_cycles < before.thread_cycles else after.thread_cycles - before.thread_cycles
	var rows: Array = _cpu_gaps[name]
	rows.append({"start_us": start, "end_us": finish, "wall_ms": wall, "thread_cpu_ms": cpu, "thread_cycles": cycles})
	rows.sort_custom(func(a, b): return a.wall_ms > b.wall_ms)
	if rows.size() > 32: rows.resize(32)
var _sync := {"calls": 0, "wall_ms": 0.0, "main_cpu_ms": 0.0,
	"render_cpu_ms": 0.0, "main_cpu_samples": 0, "render_cpu_samples": 0,
	"distinct_render_thread_samples": 0, "same_thread_samples": 0}

func _on_main_thread() -> bool:
	if OS.get_thread_caller_id() == OS.get_main_thread_id(): return true
	call_deferred("_foreign_boundary")
	return false

func _foreign_boundary() -> void:
	foreign_thread_boundaries += 1
	_phase = 0

func _ready() -> void:
	process_priority = 2147483647
	get_tree().process_frame.connect(_process_boundary)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)

func _exit_tree() -> void:
	get_tree().process_frame.disconnect(_process_boundary)
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_post_draw)

func _process_boundary() -> void:
	if not _on_main_thread(): return
	var now := Time.get_ticks_usec()
	if _cpu_enabled and _phase == 2:
		_cpu_gap("pre_draw_to_process", _last, now, _pre_cpu, get_parent().profiling_cpu_clock())
	if _phase == 2: recorder.record("engine.pre_draw_to_process", _last, now - _last)
	elif _phase != 0: unexpected_boundaries += 1
	_last = now
	_phase = 1
	_late = 0
	process_boundaries += 1

func _process(_delta: float) -> void:
	if _phase != 1: return
	_late = Time.get_ticks_usec()
	if _cpu_enabled: _late_cpu = get_parent().profiling_cpu_clock()
	recorder.record("engine.process_to_late_node", _last, _late - _last)
	if _sync_enabled:
		var sample: Dictionary = get_parent().profiling_render_sync()
		if not sample.is_empty():
			_sync.calls += 1
			_sync.wall_ms += sample.wall_ms
			if sample.render_thread_id != 0:
				if sample.render_thread_id == recorder._thread_id: _sync.same_thread_samples += 1
				else: _sync.distinct_render_thread_samples += 1
			if sample.main_cpu_ms >= 0.0:
				_sync.main_cpu_ms += sample.main_cpu_ms
				_sync.main_cpu_samples += 1
			if sample.render_cpu_ms >= 0.0:
				_sync.render_cpu_ms += sample.render_cpu_ms
				_sync.render_cpu_samples += 1

func _pre_draw() -> void:
	if not _on_main_thread(): return
	var now := Time.get_ticks_usec()
	if _cpu_enabled:
		_pre_cpu = get_parent().profiling_cpu_clock()
		if _phase == 1 and _late >= _last: _cpu_gap("late_to_pre_draw", _late, now, _late_cpu, _pre_cpu)
	if _phase == 1: recorder.record("engine.process_to_pre_draw", _last, now - _last)
	else: unexpected_boundaries += 1
	if _phase == 1 and _late >= _last:
		recorder.record("engine.late_node_to_pre_draw", _late, now - _late)
	_last = now
	_phase = 2

func _post_draw() -> void:
	if not _on_main_thread(): return
	# Delivery may lag behind the next process/pre-draw pair with a separate
	# renderer. It cannot safely identify the matching rendered frame.
	recorder.record("engine.post_draw_signal", Time.get_ticks_usec(), 0)
	draw_boundaries += 1

func stats() -> Dictionary:
	return {"process_boundaries": process_boundaries, "draw_boundaries": draw_boundaries,
		"cpu_boundary_gaps": _cpu_gaps.duplicate(true),
		"sync_probe": _sync.duplicate(),
		"foreign_thread_boundaries": foreign_thread_boundaries,
		"unexpected_boundaries": unexpected_boundaries,
		"meaning": "Process/pre-draw CPU boundaries; post-draw delivery is an unpaired marker"}
