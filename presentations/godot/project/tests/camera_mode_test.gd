extends SceneTree
const Rig = preload("res://scripts/orbit_camera.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	OS.set_environment("DF3D_CAM_ORTHO", "")
	root.size = Vector2i(960, 640)
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	rig.set_process(false)
	rig._yaw = 0.65
	rig._pitch = -0.55
	rig.focus_on(Vector3(6.5, 7.0, 40.5), 6.0)
	rig.follow_level(6)
	var free_basis := camera.basis
	var free_offset := camera.position
	rig.set_df_mode(true)
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "DF projection")
	check(is_equal_approx(camera.size, 20.0), "DF default shows 20 tile rows in640px, independent of Free6 distance")
	var pixel_width := camera.unproject_position(rig.global_position + Vector3.RIGHT).distance_to(camera.unproject_position(rig.global_position))
	check(is_equal_approx(pixel_width, 32.0), "Actual DF projection draws a tile32 logical pixels wide")
	var distant := Rig.new()
	var distant_camera := Camera3D.new()
	distant_camera.name = "Camera3D"
	distant.add_child(distant_camera)
	root.add_child(distant)
	distant.set_process(false)
	distant.focus_on(Vector3.ZERO, 160.0)
	distant.set_df_mode(true)
	check(is_equal_approx(distant_camera.size, camera.size), "Whole-map Free auto-fit160 does not shrink first DF framing")
	distant.free()
	check(camera.basis.is_finite() and camera.basis.y.is_equal_approx(Vector3.FORWARD), "finite north-up pole")
	check(camera.basis.x.is_equal_approx(Vector3.RIGHT) and camera.basis.z.is_equal_approx(Vector3.UP), "east right and look down")
	check(rig._horizontal_forward() == Vector3.FORWARD, "north panning at pole")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	motion.relative = Vector2(30, 40)
	rig._unhandled_input(motion)
	check(is_equal_approx(rig._yaw, 0.65) and is_equal_approx(rig._pitch, -0.55), "DF ignores orbit")
	var start := rig.position
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	rig._unhandled_input(motion)
	check(rig.position.x < start.x and rig.position.z < start.z and is_equal_approx(rig.position.y, start.y), "DF drag follows screen plane")
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	var size := camera.size
	rig._unhandled_input(wheel)
	check(camera.size < size and is_equal_approx(rig.current_distance(), 6.0), "DF zoom changes framing, preserves Free dolly")
	rig.follow_level(9)
	check(is_equal_approx(rig.position.y, 10.0), "DF follows current level exactly")
	rig.level_focus_offset = -4.0
	rig.follow_level(9)
	check(is_equal_approx(rig.position.y, 6.0), "Capture focus remains below recording ceiling")
	rig.level_focus_offset = 0.0
	rig.follow_level(9)
	var panned := rig.position
	var df_size := camera.size
	var user_scale := 640.0 / df_size
	var controller := preload("res://scripts/interaction.gd").new()
	controller.camera_rig = rig
	controller.camera = camera
	root.add_child(controller)
	controller.set_process(false)
	check(controller.camera_button.text.contains("DF") and controller.camera_help.text.contains("QE level"), "toolbar describes DF controls")
	controller.camera_button.pressed.emit()
	check(not rig.is_df_mode() and controller.camera_button.text.contains("Isometric"), "toolbar toggles actual camera and updates label")
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Isometric uses orthographic projection")
	var iso_direction := camera.basis.z.abs()
	check(is_equal_approx(iso_direction.x, iso_direction.y) and is_equal_approx(iso_direction.y, iso_direction.z), "True isometric axis foreshortening")
	var iso_basis := camera.basis
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	rig._unhandled_input(motion)
	check(camera.basis.is_equal_approx(iso_basis), "Isometric ignores free orbit")
	rig.follow_level(10)
	check(is_equal_approx(rig.position.y, 11.0), "Isometric follows elevation")
	rig.follow_level(9)
	rig.position = panned
	rig.set_df_mode(true)
	rig.set_df_mode(false)
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and camera.basis.is_equal_approx(free_basis), "Free projection and orientation restored")
	check(camera.position.is_equal_approx(free_offset) and rig.position.is_equal_approx(panned), "Free dolly restored at new focus")
	rig.set_df_mode(true)
	check(is_equal_approx(camera.size, df_size), "DF zoom restored")
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig._unhandled_input(wheel)
	check(is_equal_approx(camera.size, df_size) and rig.controls_blocked(), "loader disabled controls")
	rig.process_mode = Node.PROCESS_MODE_INHERIT
	root.size = Vector2i(1280, 720)
	await process_frame
	check(is_equal_approx(720.0 / camera.size, user_scale), "Viewport resize preserves user DF tile pixel scale")
	rig.set_df_mode(false)
	check(camera.position.is_equal_approx(free_offset) and camera.basis.is_equal_approx(free_basis), "DF resize preserves Free pose and dolly")
	root.size = Vector2i(960, 640)
	await process_frame
	rig.set_df_mode(true)
	check(is_equal_approx(camera.size, df_size), "Resize while Free retains user DF zoom on return")
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	check(rig.controls_blocked(), "text focus blocks camera")
	edit.release_focus()
	rig.set_df_mode(false)
	OS.set_environment("DF3D_CAM_ORTHO", "1")
	rig._pitch = -PI / 2
	rig._update_transform()
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and camera.basis.y.is_equal_approx(Vector3.FORWARD), "offline exact-pole hook preserved")
	OS.set_environment("DF3D_CAM_ORTHO", "")
	edit.free()
	controller.free()
	rig.free()
	print("camera_mode_test: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
