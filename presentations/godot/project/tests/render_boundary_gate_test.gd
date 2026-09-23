extends SceneTree
# Run twice in separate processes with DF3D_FRAME_BOUNDARIES unset and set to 1.
# No force_sync, draw readback, or live DF connection is used.
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; push_error(message)
func _initialize(): call_deferred("run")
func run():
	var world := Df3dWorld.new()
	var enabled := OS.get_environment("DF3D_FRAME_BOUNDARIES") == "1"
	if not enabled:
		check(world.profiling_render_boundary(true).is_empty(), "disabled enqueue has no checkpoint")
		check(world.profiling_render_boundary(false).is_empty(), "disabled read has no checkpoint")
	else:
		var previous := 0
		for iteration in 2:
			var requested: Dictionary = world.profiling_render_boundary(true)
			check(requested.get("sequence", 0) > previous, "enabled request allocates a fresh sequence")
			var completed: Dictionary = world.profiling_render_boundary(false)
			for frame in 120:
				if not completed.is_empty(): break
				await process_frame
				completed = world.profiling_render_boundary(false)
			check(not completed.is_empty(), "render checkpoint completes without explicit synchronization")
			if completed.is_empty(): break
			check(completed.sequence == requested.get("sequence", -1), "completed checkpoint matches requested identity")
			check(completed.reached_us >= completed.requested_us and completed.queue_delay_ms >= 0, "render queue timing uses ordered monotonic endpoints")
			check(completed.render_thread_cpu_ms == -1 or completed.render_thread_cpu_ms >= 0, "CPU interval is measured or explicitly unknown")
			check(completed.render_thread_cycles == -1 or completed.render_thread_cycles >= 0, "cycle interval is measured or explicitly unknown")
			previous = int(completed.sequence)
	world.free()
	print("RENDER_BOUNDARY_GATE_PASS enabled=", enabled) if failures == 0 else print("RENDER_BOUNDARY_GATE_FAIL")
	quit(0 if failures == 0 else 1)
