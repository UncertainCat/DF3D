extends "res://tests/frame_profile.gd"
func run():
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline = Time.get_ticks_msec() + 60000
	while not ready_scene() and Time.get_ticks_msec() < deadline: await process_frame
	if not ready_scene(): push_error("Profile scene failed to load"); quit(1); return
	for i in 60: await process_frame
	var prefix := OS.get_environment("DF3D_PROFILE_OUT")
	root.remove_child(scene)
	scene.free()
	if OS.get_environment("DF3D_PROFILE") == "off":
		if FileAccess.file_exists(prefix + ".profile.json") or FileAccess.file_exists(prefix + ".trace.json"):
			push_error("Disabled scene exported a profile"); quit(1); return
		print("PROFILING_SCENE_PASS off")
		quit(); return
	var data = JSON.parse_string(FileAccess.get_file_as_string(prefix + ".profile.json"))
	if data == null or not data.stages.has("world_poll"):
		push_error("Scene exit did not export profile"); quit(1); return
	print("PROFILING_SCENE_PASS")
	quit()
