extends SceneTree
const Ground = preload("res://scripts/walk_ground.gd")
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
		for y in range(8): map.put(x,y,0,"Floor")
	var ground := Ground.new()
	ground.world = map
	check(ground.spawn_near(Vector3(3,0,3),0).is_equal_approx(Vector3(3.5,.1,3.5)), "spawn at known floor center")
	map.occupants[Vector3i(3,3,0)] = [{"kind":1}]
	check(ground.spawn_near(Vector3(3,0,3),0) != Vector3(3.5,.1,3.5), "entry avoids standing inside a dwarf")
	map.occupants.clear()
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	rig.set_process(false)
	rig.walk_world = map
	rig.focus_on(Vector3(3.5,1,3.5), 12)
	var old_position := rig.position
	var old_eye := camera.position
	rig.set_mode("walk")
	check(rig.get_mode() == "walk" and map.top == 4, "walk keeps overhead levels visible")
	check(is_equal_approx(camera.global_position.y,.64) and is_equal_approx(camera.near,.025), "75 percent dwarf eye height and close clipping")
	var scale = preload("res://scripts/actor_view_scale.gd")
	check(is_equal_approx(scale.current,.75) and is_equal_approx(scale.effective(2.0,true),1.5), "Walk applies view multiplier without changing species ratios")
	rig.follow_level(4)
	check(is_equal_approx(rig.position.y,.1), "cutaway tracking cannot lift visitor")
	rig.position.y = 1.3
	rig._walk_window()
	check(map.top==4,"jump crossing a level does not churn cutaway scope")
	rig.position.y = .1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(10,-200)
	rig._input(look)
	# Headless DisplayServer does not capture the mouse; also run on the hidden
	# render desktop to exercise real capture and these input assertions.
	if DisplayServer.get_name() != "headless":
		check(camera.rotation.x > 0.0 and camera.rotation.y < 0.0, "walk can look up and turn")
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		space.pressed = true
		rig._input(space)
		check(rig._ground._jump_buffer>0.0,"Space queues a physics jump, not a ledge path")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	rig._input(escape)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and rig.get_mode() == "walk", "escape releases cursor without leaving walk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss releases captured mouse")
	rig.exit_walk()
	check(is_equal_approx(scale.current,1.0) and is_equal_approx(scale.effective(2.0,true),2.0), "leaving Walk restores unmodified Truescale")
	check(rig.get_mode() == "free" and rig.position == old_position and camera.position.is_equal_approx(old_eye) and map.top == 0, "exit restores previous view and cutaway")
	var queries_before := map.queries
	for i in range(10): rig._process(1.0/60)
	check(map.queries==queries_before,"normal camera runs no visitor collision queries")
	for mode in ["df","isometric","free"]:
		rig.set_mode(mode)
		rig.set_mode("walk")
		check(is_equal_approx(scale.current,.75), "each normal mode enters reduced FPS scale")
		rig.exit_walk()
		check(rig.get_mode()==mode and is_equal_approx(scale.current,1.0), "each normal mode regains full scale")
	rig.set_mode("walk")
	rig.free()
	check(is_equal_approx(scale.current,1.0), "closing Walk scene cannot leak scale to next scene")
	print("walk_camera_test: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
