extends SceneTree
const Rig = preload("res://scripts/orbit_camera.gd")
var failures := 0
class Map extends RefCounted:
	var tiles: Dictionary = {}
	var occupants: Dictionary = {}
	var queries := 0
	var top := 0
	func tile_hover_info(p: Vector3i) -> Dictionary:
		queries += 1
		return tiles.get(p, {})
	func inspect_tile(p: Vector3i) -> Array: return occupants.get(p, [])
	func terrain_loaded() -> bool: return true
	func map_size() -> Vector3i: return Vector3i(32,16,32)
	func get_top_z() -> int: return top
	func set_top_z(value: int): top = value
	func put(x: int, y: int, z: int, shape: String): tiles[Vector3i(x,y,z)] = {"shape":shape}
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func run():
	var map := Map.new()
	for x in range(8):
		for y in range(8):
			map.put(x,y,0,"Floor")
			for z in range(1,16): map.put(x,y,z,"Empty")
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	rig.set_process(false)
	rig.walk_world = map
	var preferences = preload("res://scripts/presentation_settings.gd")
	for mode in ["free","df","isometric"]:
		rig.set_mode(mode)
		rig.focus_on(Vector3(3.5,1,3.5), 60)
		if mode == "free": rig.place_eye(Vector3(3.5,20,3.5),20)
		var eye := camera.global_position
		var direction := -camera.global_basis.z
		var before := map.queries
		var truescale: bool = preferences.truescale
		var style: String = preferences.visual_style
		rig.set_mode("walk")
		check(camera.global_position.is_equal_approx(eye), "entry preserves actual eye from " + mode)
		check((-camera.global_basis.z).is_equal_approx(direction), "entry preserves direction from " + mode)
		check(map.queries == before, "entry does not search terrain")
		check(preferences.truescale == truescale and preferences.visual_style == style, "entry preserves appearance preferences")
		check(is_equal_approx(camera.near,.025), "close clipping in Walk")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		for i in range(12): rig._process(1.0/60)
		check(camera.global_position.y < eye.y-.1, "gravity continues above map with cursor released")
		eye = camera.global_position
		direction = -camera.global_basis.z
		var top := map.top
		rig.exit_walk()
		check(rig.get_mode() == "free", "exit resumes free controls")
		check(camera.global_position.is_equal_approx(eye), "exit preserves eye")
		check((-camera.global_basis.z).is_equal_approx(direction), "exit preserves direction")
		check(map.top == top, "exit keeps current cutaway")
		before = map.queries
		for i in range(10): rig._process(1.0/60)
		check(map.queries == before, "normal camera has no collision queries")
	rig.set_orbit_pose(.2,-.3,12)
	rig.place_eye(Vector3(3.5,5,3.5),12)
	rig.set_mode("walk")
	for i in range(180): rig._process(1.0/60)
	check(absf(camera.global_position.y-(.1+rig.WALK_EYE))<.002,"gravity lands on floor without teleporting")
	var feet := rig.position
	rig.follow_level(4)
	check(rig.position == feet,"level tracking cannot lift visitor")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(10,-200)
	rig._input(look)
	if DisplayServer.get_name() != "headless":
		check(camera.rotation.x > 0.0, "walk can look up")
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		space.pressed = true
		rig._input(space)
		check(rig._ground._jump_buffer>0.0,"Space queues a jump")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	rig._input(escape)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and rig.is_walk_mode(),"escape only releases cursor")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"focus loss releases cursor")
	rig.free()
	print("walk_camera_test: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
