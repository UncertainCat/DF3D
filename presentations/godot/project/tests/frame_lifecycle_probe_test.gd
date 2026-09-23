extends SceneTree
class Sink:
	var events: Array = []
	func record(name: String, start: int, duration: int):
		events.append([name, start, duration])
func _initialize():
	var probe = preload("res://scripts/frame_lifecycle_probe.gd").new()
	var sink := Sink.new()
	probe.recorder = sink
	probe._process_boundary()
	probe._process(0.0)
	probe._pre_draw()
	probe._post_draw()
	probe._process_boundary()
	var expected := ["engine.process_to_late_node", "engine.process_to_pre_draw", "engine.late_node_to_pre_draw", "engine.post_draw_signal", "engine.pre_draw_to_process"]
	var ok: bool = sink.events.size() == 5 and probe.unexpected_boundaries == 0
	for i in sink.events.size():
		ok = ok and sink.events[i][0] == expected[i] and sink.events[i][2] >= 0
	probe._post_draw() # Late post-draw delivery cannot corrupt process/pre pairing.
	ok = ok and probe.unexpected_boundaries == 0 and sink.events.size() == 6
	probe._foreign_boundary()
	ok = ok and probe.foreign_thread_boundaries == 1 and probe._phase == 0
	probe._cpu_gap("late_to_pre_draw", 1, 50001, {"thread_cpu_ms": 10.0, "thread_cycles": 100}, {"thread_cpu_ms": 10.0, "thread_cycles": 200})
	var row: Dictionary = probe.stats().cpu_boundary_gaps.late_to_pre_draw[0]
	ok = ok and row.wall_ms == 50.0 and row.thread_cpu_ms == 0.0 and row.thread_cycles == 100
	for i in 40:
		probe._cpu_gap("late_to_pre_draw", 1, 20001 + i, {"thread_cpu_ms": -1.0, "thread_cycles": -1}, {"thread_cpu_ms": -1.0, "thread_cycles": -1})
	var rows: Array = probe.stats().cpu_boundary_gaps.late_to_pre_draw
	ok = ok and rows.size() == 32 and rows[0].wall_ms == 50.0 and rows[1].thread_cpu_ms == -1.0 and rows[1].thread_cycles == -1
	probe.free()
	print("FRAME_LIFECYCLE_PASS" if ok else "FRAME_LIFECYCLE_FAIL")
	quit(0 if ok else 1)
