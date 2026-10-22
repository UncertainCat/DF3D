extends "res://scripts/setup_launcher.gd"

# The protected runner supplies only a disposable installation and profile.
# This observer survives the setup scene to verify the actual game transition.
class Observer extends Node:
	var setup: WeakRef
	var setup_canvas: WeakRef
	var setup_world: WeakRef
	var pid: int
	var window: int
	var output: String
	var captured := false
	var last_state := ""
	func _process(_delta: float) -> void:
		if captured: return
		var scene := get_tree().current_scene
		var state := str(scene.name if scene else "no scene")
		if scene and scene.name == "Main": state += " assets=" + str(scene.get("_assets_ok")) + " source=" + scene.get_node("Df3dWorld").source_name()
		if state != last_state:
			print("SETUP_HANDOFF ", state)
			var trace := FileAccess.open(output + ".state", FileAccess.WRITE)
			trace.store_string(state)
			trace.close()
			last_state = state
		if scene == null or scene.name != "Main" or not scene.get("_assets_ok"): return
		var world = scene.get_node("Df3dWorld")
		if scene.get("_session_state").is_empty(): return
		captured = true
		var ok := OS.get_process_id() == pid and DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE) == window
		ok = ok and setup.get_ref() == null and setup_canvas.get_ref() == null and setup_world.get_ref() == null
		ok = ok and get_tree().root.min_size == Vector2i.ZERO and get_tree().root.max_size == Vector2i.ZERO
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(output + ".png")
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok": ok, "pid": pid, "window": window, "scene": scene.name}))
		file.close()
		if not ok: get_tree().quit(1)
		if OS.get_environment("DF3D_SETUP_CASE") == "close":
			# Exercise the game's real exit confirmation rather than tree.quit().
			scene.get("_release_close").request_close()
			await get_tree().process_frame
			scene.get("_release_close").confirm_close()

func launch() -> void:
	var observer := Observer.new()
	observer.setup = weakref(self)
	observer.setup_canvas = weakref(canvas)
	observer.setup_world = weakref(world)
	observer.pid = OS.get_process_id()
	observer.window = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	observer.output = OS.get_environment("DF3D_SETUP_REPORT")
	root.add_child(observer)
	var trace := FileAccess.open(observer.output + ".launch", FileAccess.WRITE)
	trace.store_string("launch")
	trace.close()
	await super.launch()
	if page == "failed":
		var file := FileAccess.open(observer.output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"startup_failed": true, "pid": observer.pid, "window": observer.window}))
		file.close()
		observer.queue_free()
		quit()
