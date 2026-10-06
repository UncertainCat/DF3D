extends SceneTree
const Recorder = preload("res://scripts/hitch_recorder.gd")
class Clock:
	extends RefCounted
	var calls := 0
	var cpu := 10.0
	var cycles := 100
	func sample() -> Dictionary:
		calls += 1
		return {"thread_cpu_ms": cpu, "thread_cycles": cycles}
class Checkpoint:
	extends RefCounted
	var mode := "match"
	var requests := 0
	var reads := 0
	func sample(enqueue: bool) -> Dictionary:
		if enqueue:
			requests += 1
			return {"sequence": requests}
		reads += 1
		if mode == "pending": return {}
		return {"sequence": requests if mode == "match" else requests - 1,
			"queue_delay_ms": 1.25, "render_thread_cpu_ms": 2.0, "render_thread_cycles": 40}
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	OS.set_environment("DF3D_HITCHES", "")
	var default_off = Recorder.new()
	check(not default_off.enabled and default_off.configure_output("user://hitches/never.jsonl") == OK and default_off.stats().output == "",
		"recorder is off by default and its writer stays idle")
	OS.set_environment("DF3D_HITCHES", "1") # Opt-in; instances read the flag on construction.
	check(Recorder.new().enabled, "DF3D_HITCHES=1 enables the recorder")
	var disabled = Recorder.new()
	disabled.enabled = false
	var disabled_before: Dictionary = disabled.stats()
	disabled.begin_frame(1, "must_not_mutate")
	disabled.record("ignored", 1, 100000)
	disabled.begin_frame(100001)
	check(disabled.stats().frames == 0 and disabled.take_reports().is_empty(), "disabled recorder does no sampling")
	check(disabled.stats() == disabled_before and disabled.phase == "startup", "disabled preserves all state")
	test_windows()
	test_lifecycle()
	test_render_checkpoint()
	test_window_overflow_and_details()
	var escalation = Recorder.new()
	var peaks = Recorder.new()
	peaks.begin_frame(1)
	peaks.begin_frame(600001)
	peaks.begin_frame(1400001)
	check(peaks.take_reports().size() == 2, "new severe peak is retained even below double the previous hitch")
	escalation.begin_frame(1, "play")
	escalation.begin_frame(60001, "test")
	escalation.begin_frame(1950001)
	var escalation_reports: Array = escalation.take_reports()
	check(escalation_reports.size() == 2, "severe stall bypasses cooldown after small hitch")
	check(escalation_reports[0].frames[-1].phase == "play" and escalation_reports[1].frames[-1].phase == "test", "phase belongs to preceding frame")
	escalation.begin_frame(2050001)
	check(escalation.take_reports().is_empty() and escalation.suppressed == 1, "small hitch after escalation stays suppressed")
	check(escalation.peak_frame_us == 1890000 and escalation.frames_ge_100ms == 2 and escalation.frames_ge_1000ms == 1, "peak and severity counters include suppressed hitches")
	var recorder = Recorder.new()
	recorder.begin_frame(1000)
	recorder.record("poll", 1000, 2000)
	recorder.record_work(1, 50, 50)
	recorder.begin_frame(17667)
	recorder.record("upload", 17667, 80000)
	recorder.begin_item_work(1, 50, 50)
	recorder.end_item_work(1, 52, 51)
	recorder.record_work(1, 53, 51)
	recorder.late_process(107667)
	recorder.begin_frame(117667)
	var reports: Array = recorder.take_reports()
	check(reports.size() == 1, "one hitch report")
	var frames: Array = reports[0].frames
	check(frames.size() == 2 and frames[1].frame == 2, "hitch belongs to preceding process frame")
	check(frames[0].coarse_stages_ms == {"poll": 2.0}, "preceding context preserved")
	check(frames[1].coarse_stages_ms == {"upload": 80.0}, "stages reset each frame")
	check(frames[1].unattributed_ms == 20.0 and frames[1].largest_component == "upload", "accounted and unattributed classification")
	check(frames[1].process_to_late_ms == 90.0 and frames[1].after_late_ms == 10.0, "late process boundary separates callback work from trailing gap")
	check(frames[0].process_to_late_ms == -1.0, "missing boundary is unknown")
	check(frames[1].instance_allocations == 0 and frames[1].transform_writes == 3 and frames[1].custom_writes == 1, "work counters are frame deltas")
	check(frames[1].item_allocations == 0 and frames[1].item_transform_writes == 2 and frames[1].item_custom_writes == 1, "item counters exclude other sprite stages")
	check(frames[0].item_transform_writes == 0, "frames without item updates have zero item work")
	recorder.begin_frame(217667)
	check(recorder.take_reports().is_empty() and recorder.suppressed == 1, "cooldown suppresses repeated hitches")
	recorder.begin_frame(2217667)
	reports = recorder.take_reports()
	check(reports.size() == 1 and reports[0].frames[-1].largest_component == "unattributed", "unknown engine gap stays unknown")
	recorder.record("outer", 2217667, 100)
	recorder.record("nested", 2217668, 10)
	check(recorder.invalid_intervals == 1, "overlap rejected without double counting")
	var bounded = Recorder.new()
	bounded.cooldown_us = 0
	bounded.begin_frame(1)
	for n in 20:
		for i in 40: bounded.record("stage" + str(i), n * 60000 + i + 1, 1)
		bounded.begin_frame((n + 1) * 60000 + 1)
	check(bounded.stats().pending_reports == Recorder.MAX_REPORTS, "bounded report queue")
	check(bounded.dropped_reports == 12 and bounded.dropped_stages > 0, "overflow counted")
	bounded.take_reports()
	bounded.begin_frame(1260001)
	reports = bounded.take_reports()
	check(reports[0].frames.size() == Recorder.HISTORY, "bounded preceding history")
	var writer = Recorder.new()
	var path := "user://hitch-recorder-test.jsonl"
	check(writer.configure_output(path) == OK, "writer starts")
	writer.begin_frame(1)
	writer.begin_frame(100001)
	writer.shutdown()
	var file := FileAccess.open(path, FileAccess.READ)
	check(file != null, "writer creates file")
	if file != null:
		var report = JSON.parse_string(file.get_line())
		check(report is Dictionary and report.kind == "presentation_hitch", "writer drains on shutdown")
		var summary = JSON.parse_string(file.get_line())
		check(summary is Dictionary and summary.kind == "presentation_hitch_summary" and summary.hitches == 1, "final counters persist")
		file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A diagnostics consumer must not race the writer thread for the same queue.
	var owned = Recorder.new()
	check(owned.configure_output(path) == OK, "owned writer starts")
	owned.begin_frame(1)
	owned.begin_frame(100001)
	# This case deliberately violates queue ownership; verify refusal and retention.
	owned._take_refused_warned = true
	check(owned.take_reports().is_empty() and owned.take_reports().is_empty() and owned.hitches == 1, "take_reports refuses while the session file writer owns the queue")
	owned.shutdown()
	file = FileAccess.open(path, FileAccess.READ)
	var owned_report = JSON.parse_string(file.get_line())
	check(owned_report is Dictionary and owned_report.kind == "presentation_hitch", "refused take leaves the report to the session file")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	owned.begin_frame(2200001)
	check(owned.take_reports().size() == 1, "in-memory consumer works again once the writer is shut down")
	var limited = Recorder.new()
	limited.max_output_bytes = 0
	check(limited.configure_output(path) == OK, "bounded writer starts")
	limited.begin_frame(1)
	limited.begin_frame(100001)
	limited.shutdown()
	file = FileAccess.open(path, FileAccess.READ)
	var limited_summary = JSON.parse_string(file.get_line())
	check(limited_summary.kind == "presentation_hitch_summary" and limited_summary.disk_dropped_reports == 1, "disk cap preserves final drop summary")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("HITCH_RECORDER_PASS" if failures == 0 else "HITCH_RECORDER_FAIL")
	quit(0 if failures == 0 else 1)

func test_windows() -> void:
	var recorder = Recorder.new()
	recorder.cooldown_us = 100000000
	recorder.begin_frame(1, "viewer")
	recorder.start_window("viewer")
	# Exclude the already-running frame, even when its phase matches the window.
	var now := 100001
	recorder.begin_frame(now, "viewer")
	var durations: Array[int] = [60000, 65000, 64000]
	for i in range(1, 25): durations.append(i * 1000)
	for duration in durations:
		recorder.record("work", now, duration / 2)
		now += duration
		recorder.begin_frame(now, "viewer")
	# Close the pending viewer frame, then a much slower excluded phase.
	now += 1000
	recorder.begin_frame(now, "export")
	now += 900000
	recorder.begin_frame(now, "viewer")
	var result: Dictionary = recorder.finish_window()
	check(result.kind == "presentation_worst_frames" and result.phase == "viewer", "window artifact identity")
	check(result.observed_frames == durations.size() + 1, "window counts completed matching intervals only")
	check(result.intervals_us.size() == result.observed_frames and result.sample_overflow == 0, "all bounded interval samples retained")
	check(result.peak_frame_us == 65000 and result.frames[0].frame_ms == 65.0, "exact maximum survives report cooldown")
	check(recorder.suppressed >= 3, "selected peaks were suppressed in ordinary reporting")
	var expected := durations.duplicate()
	expected.append(1000); expected.sort(); expected.reverse(); expected.resize(Recorder.WORST_LIMIT)
	check(result.frames.size() == Recorder.WORST_LIMIT, "top frame selection is bounded")
	for i in expected.size():
		check(result.frames[i].frame_ms == expected[i] / 1000.0, "exact top ranking %d" % i)
		check(result.frames[i].phase == "viewer", "export and pre-window frames excluded")
	check(result.frames[0].coarse_stages_ms.work == 32.5, "worst snapshot survives history ring overwrite")
	check(result.frames[0].lifecycle.is_empty(), "no boundary sampler means unknown lifecycle")
	check(recorder.finish_window().observed_frames == 0, "finishing again does not duplicate intervals")
	var short = Recorder.new()
	short.begin_frame(1, "play"); short.start_window("play"); short.begin_frame(2)
	short.begin_frame(16002)
	var sample: Dictionary = short.finish_window()
	check(sample.observed_frames == 1 and sample.peak_frame_us == 16000 and short.take_reports().is_empty(), "subthreshold frame is retained without producing a hitch")

func test_lifecycle() -> void:
	var clock := Clock.new()
	var recorder = Recorder.new()
	recorder.boundary_clock = clock.sample
	recorder.start_window("play")
	recorder.begin_frame(1, "play")
	clock.cpu = 12; clock.cycles = 120
	recorder.late_process(20001)
	clock.cpu = 13; clock.cycles = 150
	recorder.pre_draw(30001)
	clock.cpu = 15; clock.cycles = 190
	recorder.begin_frame(100001)
	var lifecycle: Dictionary = recorder.finish_window().frames[0].lifecycle
	check(lifecycle.start_to_late == {"wall_ms":20.0,"thread_cpu_ms":2.0,"thread_cycles":20}, "start-to-late clocks are exact differences")
	check(lifecycle.late_to_pre == {"wall_ms":10.0,"thread_cpu_ms":1.0,"thread_cycles":30}, "late-to-pre clocks are exact differences")
	check(lifecycle.pre_to_end == {"wall_ms":70.0,"thread_cpu_ms":2.0,"thread_cycles":40}, "pre-to-next-entry clocks are exact differences")
	check(lifecycle.start_to_end == {"wall_ms":100.0,"thread_cpu_ms":5.0,"thread_cycles":90}, "whole-frame measurement overlaps segments without double counting")
	for invalid in ["pre_before_late", "duplicate_pre"]:
		var broken = Recorder.new()
		broken.boundary_clock = clock.sample
		broken.start_window("play"); broken.begin_frame(1,"play")
		if invalid == "pre_before_late": broken.pre_draw(10)
		broken.late_process(20); broken.pre_draw(30)
		if invalid == "duplicate_pre": broken.pre_draw(40)
		broken.begin_frame(100)
		check(broken.finish_window().frames[0].lifecycle.is_empty(), "invalid boundary sequence stays unknown: " + invalid)
	var missing = Recorder.new()
	missing.boundary_clock = clock.sample
	missing.start_window("play"); missing.begin_frame(1,"play")
	clock.cpu = -1; clock.cycles = -1
	missing.begin_frame(1001)
	var frame: Dictionary = missing.finish_window().frames[0]
	check(frame.process_to_late_ms == -1 and frame.after_late_ms == -1, "missing late boundary remains unknown")
	check(not frame.lifecycle.has("pre_to_end") and frame.lifecycle.start_to_end.thread_cpu_ms == -1 and frame.lifecycle.start_to_end.thread_cycles == -1, "missing CPU counters and boundaries are never zero measurements")
	check(Recorder._boundary_gap({"time_us":20},{"time_us":10}).is_empty(), "backwards wall boundary is invalid")
	var rollback: Dictionary = Recorder._boundary_gap({"time_us":10,"thread_cpu_ms":5,"thread_cycles":50},{"time_us":20,"thread_cpu_ms":4,"thread_cycles":40})
	check(rollback.thread_cpu_ms == -1 and rollback.thread_cycles == -1 and rollback.wall_ms == .01, "regressing CPU counters preserve wall evidence but report CPU unknown")
	var disabled = Recorder.new()
	disabled.enabled = false; disabled.boundary_clock = clock.sample
	var calls := clock.calls
	disabled.start_window("disabled"); disabled.begin_frame(1); disabled.late_process(2); disabled.pre_draw(3); disabled.begin_frame(4)
	check(clock.calls == calls and disabled.finish_window().observed_frames == 0, "disabled mode never calls boundary sampler")

func test_render_checkpoint() -> void:
	for mode in ["match", "mismatch", "pending"]:
		var clock := Clock.new()
		var checkpoint := Checkpoint.new()
		checkpoint.mode = mode
		var recorder = Recorder.new()
		recorder.boundary_clock = clock.sample
		recorder.render_checkpoint = checkpoint.sample
		recorder.start_window("play"); recorder.begin_frame(1, "play")
		recorder.late_process(10); recorder.pre_draw(20); recorder.begin_frame(100)
		var lifecycle: Dictionary = recorder.finish_window().frames[0].lifecycle
		check(checkpoint.requests == 1 and checkpoint.reads == 1, "one nonblocking request/read per sampled frame")
		if mode == "match":
			check(lifecycle.render_queue.sequence == 1 and lifecycle.render_queue.queue_delay_ms == 1.25, "matching checkpoint retains render queue evidence")
		else:
			check(not lifecycle.has("render_queue"), "unmatched/not-ready checkpoint remains unknown: " + mode)
		check(lifecycle.start_to_end.wall_ms == .099, "queue evidence does not alter frame duration")
	var disabled = Recorder.new()
	var checkpoint := Checkpoint.new()
	var clock := Clock.new()
	disabled.enabled = false; disabled.boundary_clock = clock.sample; disabled.render_checkpoint = checkpoint.sample
	disabled.begin_frame(1); disabled.late_process(10); disabled.pre_draw(20); disabled.begin_frame(100)
	check(checkpoint.requests == 0 and checkpoint.reads == 0, "disabled recorder never touches render queue")

func test_window_overflow_and_details() -> void:
	var recorder = Recorder.new()
	recorder.start_window("play"); recorder.begin_frame(1,"play")
	# Seed the retained prefix to exercise the cap without 250k fake frames.
	recorder._window_samples.resize(Recorder.WINDOW_SAMPLE_LIMIT)
	recorder._window_samples.fill(1)
	recorder.begin_frame(101)
	var overflow: Dictionary = recorder.finish_window()
	check(overflow.intervals_us.size() == Recorder.WINDOW_SAMPLE_LIMIT, "interval storage remains bounded on overflow")
	check(overflow.observed_frames == Recorder.WINDOW_SAMPLE_LIMIT + 1 and overflow.sample_overflow == 1, "overflow contributes to observed count without pretending to be retained")
	check(overflow.peak_frame_us == 100, "overflow still participates in exact peak selection")
	var empty: Dictionary = recorder.finish_window()
	check(empty.observed_frames == 0 and empty.sample_overflow == 0 and empty.intervals_us.is_empty(), "repeated finish clears overflow accounting")
	var clock := Clock.new()
	var details = Recorder.new()
	details.boundary_clock = clock.sample
	details.start_window("play"); details.begin_frame(Time.get_ticks_usec(), "play")
	check(details.detail_start() > 0, "explicit boundary probe enables detail clock")
	for i in 20: details.detail_mark("slot%d" % i, Time.get_ticks_usec()-100)
	var slots: Dictionary = details._boundary_samples[details._slot].detail_ms
	check(slots.size() == 16 and not slots.has("slot16"), "nested detail names have a fixed 16-slot cap")
	var previous: float = slots.slot0
	details.detail_mark("slot0", Time.get_ticks_usec()-100)
	check(slots.size() == 16 and slots.slot0 > previous, "existing detail accumulates when slots are full")
	details.begin_frame(Time.get_ticks_usec()+1000)
	var frame: Dictionary = details.finish_window().frames[0]
	check(frame.lifecycle.detail_ms.size() == 16 and frame.coarse_stages_ms.is_empty(), "nested detail does not double count disjoint coarse work")
	for enabled in [false, true]:
		var disabled = Recorder.new()
		disabled.enabled = enabled
		if not enabled: disabled.boundary_clock = clock.sample
		disabled.begin_frame(1)
		var before: Array = disabled._boundary_samples.duplicate(true)
		check(disabled.detail_start() == 0 and disabled.detail_mark("ignored", 1) == 0, "normal/disabled paths take no detail timestamps")
		check(disabled._boundary_samples == before, "normal/disabled detail calls leave sample storage untouched")
