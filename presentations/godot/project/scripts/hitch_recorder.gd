extends RefCounted
# Coarse elapsed-wall-time flight recorder. No engine/render-server readbacks.
# Call begin_frame once at the same process boundary, then record only disjoint
# coarse stages. A long boundary interval belongs to the PRECEDING frame.
const MAX_STAGES := 32
const HISTORY := 8
const MAX_REPORTS := 8
# Opt-in: DF3D_HITCHES=1. Off by default so normal play writes no session files.
var enabled := OS.get_environment("DF3D_HITCHES") == "1"
var threshold_us := 50000
var cooldown_us := 2000000
var phase := "startup"
var max_output_bytes := 8 * 1024 * 1024
# Explicit benchmark windows retain top frames independently of report cooldown.
const WORST_LIMIT := 16
const WINDOW_SAMPLE_LIMIT := 250000
var boundary_clock := Callable()
var render_checkpoint := Callable()
var _boundary_samples: Array = []
var _window_phase := ""
var _window_first_frame := 0
var _window_samples := PackedInt64Array()
var _window_overflow := 0
var _worst: Array = []
var _reference: Array = []
var _reference_seen := 0
var _names: Array[String] = []
var _ids: Dictionary = {}
var _starts := PackedInt64Array()
var _ends := PackedInt64Array()
var _late_process := PackedInt64Array()
var _durations := PackedInt64Array()
var _covered := PackedInt64Array()
var _phases := PackedStringArray()
var _work := PackedInt64Array()
var _previous_allocations := 0
var _previous_transforms := 0
var _previous_custom := 0
var _item_work := PackedInt64Array()
var _item_start_allocations := 0
var _item_start_transforms := 0
var _item_start_custom := 0
var _slot := -1
var _frames := 0
var _last_covered_end := 0
var _last_report := -2000000
var _last_report_duration := 0
var _reports: Array = []
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _writer: Thread
var _stopping := false
var _take_refused_warned := false
var _output := ""
var hitches := 0
var peak_frame_us := 0
var frames_ge_100ms := 0
var frames_ge_250ms := 0
var frames_ge_1000ms := 0
var suppressed := 0
var dropped_reports := 0
var dropped_stages := 0
var invalid_intervals := 0
var write_failures := 0
var output_bytes := 0
var disk_dropped_reports := 0

func _init() -> void:
	_boundary_samples.resize(HISTORY)
	_starts.resize(HISTORY)
	_ends.resize(HISTORY)
	_late_process.resize(HISTORY)
	_covered.resize(HISTORY)
	_phases.resize(HISTORY)
	_work.resize(HISTORY * 3)
	_item_work.resize(HISTORY * 3)
	_durations.resize(HISTORY * MAX_STAGES)

func begin_frame(now_us: int, context_phase := "") -> void:
	if not enabled: return
	if _slot >= 0:
		if now_us < _starts[_slot]:
			invalid_intervals += 1
			return
		_ends[_slot] = now_us
		var elapsed := now_us - _starts[_slot]
		if boundary_clock.is_valid():
			_boundary_samples[_slot]["end"] = _clock_sample(now_us)
		if not _window_phase.is_empty() and _frames >= _window_first_frame and _phases[_slot] == _window_phase:
			if _window_samples.size() < WINDOW_SAMPLE_LIMIT: _window_samples.append(elapsed)
			else: _window_overflow += 1
			# Sparse unbiased-by-duration reference frames for comparison with the tail.
			if (_frames - _window_first_frame) % 128 == 0:
				if _reference.size() < 32: _reference.append(_snapshot())
				else: _reference[_reference_seen % 32] = _snapshot()
				_reference_seen += 1
			if _worst.size() < WORST_LIMIT or elapsed > int(_worst.back().elapsed):
				_worst.append({"elapsed": elapsed, "raw": _snapshot()})
				_worst.sort_custom(func(a, b): return a.elapsed > b.elapsed)
				if _worst.size() > WORST_LIMIT: _worst.resize(WORST_LIMIT)
		var new_severe_peak := elapsed > peak_frame_us and elapsed >= 250000
		peak_frame_us = maxi(peak_frame_us, elapsed)
		if elapsed >= 100000: frames_ge_100ms += 1
		if elapsed >= 250000: frames_ge_250ms += 1
		if elapsed >= 1000000: frames_ge_1000ms += 1
		if elapsed >= threshold_us:
			hitches += 1
			if _last_report_duration == 0 or now_us - _last_report >= cooldown_us or elapsed >= _last_report_duration * 2 or new_severe_peak:
				if _enqueue_report():
					_last_report = now_us
					_last_report_duration = elapsed
			else:
				suppressed += 1
	_slot = (_slot + 1) % HISTORY
	_frames += 1
	if not context_phase.is_empty(): phase = context_phase
	_phases[_slot] = phase
	_starts[_slot] = now_us
	_ends[_slot] = 0
	_late_process[_slot] = 0
	if boundary_clock.is_valid(): _boundary_samples[_slot] = {"start": _clock_sample(now_us)}
	_covered[_slot] = 0
	_last_covered_end = now_us
	for i in 3:
		_work[_slot * 3 + i] = 0
		_item_work[_slot * 3 + i] = 0
	for i in MAX_STAGES:
		_durations[_slot * MAX_STAGES + i] = 0

func late_process(now_us: int) -> void:
	if enabled and _slot >= 0 and now_us >= _starts[_slot]:
		_late_process[_slot] = now_us
		if boundary_clock.is_valid():
			_boundary_samples[_slot]["late"] = _clock_sample(now_us)
			if render_checkpoint.is_valid(): _boundary_samples[_slot]["render_request"] = render_checkpoint.call(true)

# Optional nested detail; kept separate from disjoint coarse totals.
func detail_start() -> int:
	return Time.get_ticks_usec() if enabled and boundary_clock.is_valid() and _slot >= 0 else 0

func detail_mark(name: String, start_us: int) -> int:
	if start_us == 0 or not enabled or not boundary_clock.is_valid() or _slot < 0: return 0
	var now := Time.get_ticks_usec()
	var sample: Dictionary = _boundary_samples[_slot]
	if not sample.has("detail_ms"): sample["detail_ms"] = {}
	if sample.detail_ms.size() < 16 or sample.detail_ms.has(name):
		sample.detail_ms[name] = float(sample.detail_ms.get(name, 0.0)) + (now-start_us)/1000.0
	return now

func application_boundary(entering: bool) -> void:
	if not enabled or not boundary_clock.is_valid() or _slot < 0: return
	_boundary_samples[_slot]["application_enter_us" if entering else "application_exit_us"] = Time.get_ticks_usec()

func record_work(allocations: int, transforms: int, custom: int) -> void:
	if not enabled or _slot < 0: return
	_work[_slot * 3] = maxi(0, allocations - _previous_allocations)
	_work[_slot * 3 + 1] = maxi(0, transforms - _previous_transforms)
	_work[_slot * 3 + 2] = maxi(0, custom - _previous_custom)
	_previous_allocations = allocations
	_previous_transforms = transforms
	_previous_custom = custom

func begin_item_work(allocations: int, transforms: int, custom: int) -> void:
	if not enabled: return
	_item_start_allocations = allocations
	_item_start_transforms = transforms
	_item_start_custom = custom

func end_item_work(allocations: int, transforms: int, custom: int) -> void:
	if not enabled or _slot < 0: return
	_item_work[_slot * 3] = maxi(0, allocations - _item_start_allocations)
	_item_work[_slot * 3 + 1] = maxi(0, transforms - _item_start_transforms)
	_item_work[_slot * 3 + 2] = maxi(0, custom - _item_start_custom)

func record(stage: String, start_us: int, duration_us: int) -> void:
	if not enabled or _slot < 0: return
	# Reject nested/overlapping samples, rather than summing parents and children.
	if duration_us < 0 or start_us < _last_covered_end:
		invalid_intervals += 1
		return
	if not _ids.has(stage):
		if _names.size() == MAX_STAGES:
			dropped_stages += 1
			return
		_ids[stage] = _names.size()
		_names.append(stage)
	var index: int = _ids[stage]
	_durations[_slot * MAX_STAGES + index] += duration_us
	_covered[_slot] += duration_us
	_last_covered_end = start_us + duration_us

func _enqueue_report() -> bool:
	_mutex.lock()
	if _reports.size() >= MAX_REPORTS:
		dropped_reports += 1
		_mutex.unlock()
		return false
	var should_wake := _reports.is_empty()
	# Packed arrays are copied only on a hitch. The worker expands/serializes them;
	# subsequent frame writes do not mutate its immutable copies.
	_reports.append(_snapshot(true))
	_mutex.unlock()
	if _writer != null and should_wake: _wake.post()
	return true

func _snapshot(writer_lock_held := false) -> Dictionary:
	return {"starts": _starts.duplicate(), "ends": _ends.duplicate(),
		"late_process": _late_process.duplicate(), "boundaries": _boundary_samples.duplicate(true),
		"work": _work.duplicate(),
		"item_work": _item_work.duplicate(),
		"covered": _covered.duplicate(), "durations": _durations.duplicate(),
		"names": _names.duplicate(), "phases": _phases.duplicate(), "slot": _slot, "frames": _frames,
		"hitches": hitches, "suppressed": suppressed,
		"dropped_reports": dropped_reports, "dropped_stages": dropped_stages,
		"write_failures": write_failures if writer_lock_held else 0, "invalid_intervals": invalid_intervals}

func _clock_sample(now_us: int) -> Dictionary:
	var sample: Dictionary = boundary_clock.call()
	sample["time_us"] = now_us
	return sample

func pre_draw(now_us: int) -> void:
	if not enabled or not boundary_clock.is_valid() or _slot < 0: return
	var sample: Dictionary = _boundary_samples[_slot]
	# Only accept a single correctly ordered boundary; never pair deferred post-draw.
	if sample.has("pre") or not sample.has("late") or now_us < int(sample.late.time_us):
		sample["invalid"] = true
		return
	sample["pre"] = _clock_sample(now_us)
	if render_checkpoint.is_valid():
		var completed: Dictionary = render_checkpoint.call(false)
		var requested: Dictionary = sample.get("render_request", {})
		if not requested.is_empty() and completed.get("sequence", -1) == requested.get("sequence", -2):
			sample["render_queue"] = completed

func start_window(label: String) -> void:
	_window_phase = label if enabled else ""
	_window_first_frame = _frames + 1 # Current frame can contain warmup/export work.
	_window_samples.clear()
	_window_overflow = 0
	_worst.clear()
	_reference.clear()
	_reference_seen = 0

func finish_window() -> Dictionary:
	var result := {"schema_version": 1, "kind": "presentation_worst_frames",
		"phase": _window_phase, "observed_frames": _window_samples.size() + _window_overflow,
		"sample_overflow": _window_overflow, "peak_frame_us": 0, "frames": [], "reference_frames": [],
		"intervals_us": _window_samples.duplicate()}
	for selected in _worst:
		var expanded := expand_report(selected.raw)
		result.frames.append(expanded.frames.back())
	for raw in _reference: result.reference_frames.append(expand_report(raw).frames.back())
	_reference.clear()
	if not _worst.is_empty(): result.peak_frame_us = _worst.front().elapsed
	_window_phase = ""
	_worst.clear()
	_window_samples.clear()
	_window_overflow = 0
	return result

static func _boundary_gap(before: Dictionary, after: Dictionary) -> Dictionary:
	if before.is_empty() or after.is_empty(): return {}
	var wall: int = int(after.time_us) - int(before.time_us)
	if wall < 0: return {}
	var cpu_before := float(before.get("thread_cpu_ms", -1))
	var cpu_after := float(after.get("thread_cpu_ms", -1))
	var cycles_before := int(before.get("thread_cycles", -1))
	var cycles_after := int(after.get("thread_cycles", -1))
	return {"wall_ms": wall / 1000.0,
		"thread_cpu_ms": cpu_after-cpu_before if cpu_before >= 0 and cpu_after >= cpu_before else -1.0,
		"thread_cycles": cycles_after-cycles_before if cycles_before >= 0 and cycles_after >= cycles_before else -1}

static func _lifecycle(raw: Dictionary, slot: int) -> Dictionary:
	if not raw.has("boundaries"): return {}
	var samples: Dictionary = raw.boundaries[slot] if raw.boundaries[slot] is Dictionary else {}
	if samples.is_empty() or samples.get("invalid", false): return {}
	var result := {}
	if samples.has("render_queue"): result["render_queue"] = samples.render_queue
	if samples.has("detail_ms"): result["detail_ms"] = samples.detail_ms
	if samples.has("application_enter_us") and samples.has("application_exit_us"):
		result["main_process_ms"] = (int(samples.application_exit_us)-int(samples.application_enter_us))/1000.0
		if samples.has("start"): result["before_main_process_ms"] = (int(samples.application_enter_us)-int(samples.start.time_us))/1000.0
		if samples.has("late"): result["after_main_process_ms"] = (int(samples.late.time_us)-int(samples.application_exit_us))/1000.0
	for pair in [["start", "late"], ["late", "pre"], ["pre", "end"], ["start", "end"]]:
		var gap := _boundary_gap(samples.get(pair[0], {}), samples.get(pair[1], {}))
		if not gap.is_empty(): result[pair[0]+"_to_"+pair[1]] = gap
	return result

# For deterministic tests or an explicit in-memory diagnostics consumer.
# Normal frames never expand dictionaries or serialize reports. While a file
# writer owns the queue (configure_output), taking would race its drain and
# silently drop reports from the session file, so the request is refused.
func take_reports() -> Array:
	if _writer != null:
		if not _take_refused_warned:
			_take_refused_warned = true
			push_warning("hitch recorder: take_reports() ignored while the session file writer owns the report queue")
		return []
	_mutex.lock()
	var result := _reports
	_reports = []
	_mutex.unlock()
	var expanded: Array = []
	for report in result: expanded.append(expand_report(report))
	return expanded

static func expand_report(raw: Dictionary) -> Dictionary:
	var frames: Array = []
	var count := mini(int(raw.frames), HISTORY)
	for offset in count:
		var slot := (int(raw.slot) - count + 1 + offset + HISTORY) % HISTORY
		var start: int = raw.starts[slot]
		var finish: int = raw.ends[slot]
		var stages := {}
		var slowest := ""
		var slowest_us := 0
		for i in raw.names.size():
			var duration: int = raw.durations[slot * MAX_STAGES + i]
			if duration > 0: stages[raw.names[i]] = duration / 1000.0
			if duration > slowest_us:
				slowest_us = duration
				slowest = raw.names[i]
		var gap := maxi(0, finish - start - int(raw.covered[slot]))
		var late: int = raw.late_process[slot]
		frames.append({"frame": int(raw.frames) - count + offset + 1, "phase": raw.phases[slot],
			"start_us": start, "end_us": finish, "frame_ms": (finish - start) / 1000.0,
			"process_to_late_ms": (late-start)/1000.0 if late >= start and late <= finish else -1.0,
			"after_late_ms": (finish-late)/1000.0 if late >= start and late <= finish else -1.0,
			"instance_allocations": raw.work[slot * 3],
			"transform_writes": raw.work[slot * 3 + 1], "custom_writes": raw.work[slot * 3 + 2],
			"item_allocations": raw.item_work[slot * 3], "item_transform_writes": raw.item_work[slot * 3 + 1], "item_custom_writes": raw.item_work[slot * 3 + 2],
			"lifecycle": _lifecycle(raw, slot), "coarse_stages_ms": stages, "unattributed_ms": gap / 1000.0,
			"largest_component": "unattributed" if gap > slowest_us else slowest})
	return {"schema_version": 1, "kind": "presentation_hitch", "frames": frames,
		"hitches": raw.hitches, "suppressed": raw.suppressed,
		"dropped_reports": raw.dropped_reports, "dropped_stages": raw.dropped_stages,
		"write_failures": raw.write_failures, "invalid_intervals": raw.invalid_intervals,
		"meaning": "Consecutive process-entry wall intervals. Unattributed includes other nodes, engine work, waits and frame pacing; it is not a GPU measurement."}

# Explicit startup/shutdown; file operations and JSON formatting stay off the
# presentation thread. Queue is bounded, and slow storage drops reports.
func configure_output(path := "") -> Error:
	if not enabled: return OK
	if _writer != null: return ERR_INVALID_PARAMETER
	if path.is_empty(): path = OS.get_environment("DF3D_HITCH_OUT")
	if path.is_empty(): path = "user://hitches/session-" + str(Time.get_unix_time_from_system()).replace(".", "-") + ".jsonl"
	_output = ProjectSettings.globalize_path(path)
	_stopping = false
	_writer = Thread.new()
	var error := _writer.start(_write_loop)
	if error != OK:
		_writer = null
		write_failures += 1
	elif not _reports.is_empty(): _wake.post()
	return error

func _write_loop() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
	var file: FileAccess
	if directory_error == OK: file = FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		_mutex.lock()
		write_failures += 1
		_mutex.unlock()
	while true:
		_wake.wait()
		_mutex.lock()
		var batch := _reports
		_reports = []
		var stop := _stopping
		_mutex.unlock()
		for report in batch:
			if file != null:
				var encoded := JSON.stringify(expand_report(report))
				var bytes := encoded.to_utf8_buffer().size() + 1
				_mutex.lock()
				var fits := output_bytes + bytes <= max_output_bytes
				if fits: output_bytes += bytes
				else: disk_dropped_reports += 1
				_mutex.unlock()
				if fits: file.store_line(encoded)
		if file != null and not batch.is_empty():
			file.flush()
			if file.get_error() != OK:
				_mutex.lock()
				write_failures += 1
				_mutex.unlock()
				file.close()
				file = null
		if stop:
			if file != null:
				var summary := stats()
				summary["schema_version"] = 1
				summary["kind"] = "presentation_hitch_summary"
				summary["frames_recorded"] = summary.frames
				summary["frames"] = []
				file.store_line(JSON.stringify(summary))
				file.close()
			break

func shutdown() -> void:
	if _writer == null: return
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	_writer.wait_to_finish()
	_writer = null

func stats() -> Dictionary:
	_mutex.lock()
	var result := {"frames": _frames, "hitches": hitches, "suppressed": suppressed,
		"peak_frame_us": peak_frame_us, "frames_ge_100ms": frames_ge_100ms,
		"frames_ge_250ms": frames_ge_250ms, "frames_ge_1000ms": frames_ge_1000ms,
		"dropped_reports": dropped_reports, "dropped_stages": dropped_stages,
		"invalid_intervals": invalid_intervals, "pending_reports": _reports.size(),
		"write_failures": write_failures, "output": _output}
	result["output_bytes"] = output_bytes
	result["disk_dropped_reports"] = disk_dropped_reports
	_mutex.unlock()
	return result
