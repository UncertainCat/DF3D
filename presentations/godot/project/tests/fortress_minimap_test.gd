extends SceneTree
const Overview = preload("res://scripts/fortress_minimap.gd")
class World extends RefCounted:
 var generation := 1
 var loaded := true
 var calls := 0
 var texture: ImageTexture
 func _init():
  var image := Image.create(40, 10, false, Image.FORMAT_RGBA8)
  image.fill(Color.GREEN)
  texture = ImageTexture.create_from_image(image)
 func get_top_z(): return 7
 func minimap_data(_z, _resolution):
  calls += 1
  return {"available": loaded, "texture": texture, "map_size": Vector2i(40,10), "z":7,"generation":generation}
class Interaction extends RefCounted:
 var cancelled := 0
 var tool := 1
 func cancel_selection(): cancelled += 1
func _initialize(): call_deferred("run")
func run():
 root.size = Vector2i(640,480)
 var rect := Overview.fitted_rect(Vector2(200,200), Vector2(40,10))
 assert(rect == Rect2(0,75,200,50))
 assert(Overview.point_to_tile(Vector2(100,100), Vector2(200,200), Vector2(40,10)) == Vector2(20,5))
 assert(Overview.point_to_tile(Vector2(-100,-100), Vector2(200,200), Vector2(40,10)) == Vector2.ZERO)
 var edge := Overview.point_to_tile(Vector2(1000,1000), Vector2(200,200), Vector2(40,10))
 assert(edge.x < 40 and edge.x > 39 and edge.y < 10 and edge.y > 9)
 assert(Overview.fitted_rect(Vector2(200,200), Vector2(10,40)) == Rect2(75,0,50,200))
 assert(Overview.clipped_segment(Vector2(-10,100),Vector2(300,100),rect) == PackedVector2Array([Vector2(0,100),Vector2(200,100)]))
 assert(Overview.clipped_segment(Vector2(-10,20),Vector2(300,20),rect).is_empty())
 var rig = load("res://scripts/orbit_camera.gd").new()
 var camera := Camera3D.new()
 camera.name = "Camera3D"
 rig.add_child(camera)
 root.add_child(rig)
 rig.follow_level(7)
 rig.set_df_mode(true)
 var overview := Overview.new()
 var world := World.new()
 var interaction := Interaction.new()
 overview.world = world
 overview.camera_rig = rig
 overview.interaction = interaction
 overview.position = Vector2(50,50)
 overview.size = Vector2(200,200)
 root.add_child(overview)
 overview.set_allowed(true)
 overview.refresh()
 await process_frame
 var click := InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 click.pressed = true
 click.position = overview.position + Vector2(100,100)
 root.push_input(click)
 assert(rig.position.is_equal_approx(Vector3(20,8,5)))
 assert(interaction.cancelled == 1 and interaction.tool == 1)
 click.pressed = false
 root.push_input(click)
 var before: Vector3 = rig.position
 click.pressed = true
 click.position = overview.position + Vector2(100,20)
 root.push_input(click)
 assert(rig.position == before, "aspect fit margins are not map tiles")
 overview.set_allowed(false)
 click.position = overview.position + Vector2(180,100)
 root.push_input(click)
 assert(rig.position == before, "blocked minimap cannot move camera")
 overview.set_allowed(true)
 rig.set_df_mode(false)
 var old_basis: Basis = camera.global_basis
 var old_distance: float = rig.current_distance()
 overview.navigate(Vector2(180,100))
 assert(camera.global_basis.is_equal_approx(old_basis))
 assert(rig.position.y == before.y and rig.current_distance() == old_distance)
 overview.update_footprint()
 assert(overview.footprint.size() in [0,5])
 world.loaded = false
 world.generation += 1
 overview.refresh()
 assert(not overview.data.available and overview.data.generation == 2)
 before = rig.position
 overview.navigate(Vector2.ZERO)
 assert(rig.position == before, "unloaded minimap cannot move camera")
 print("FORTRESS_MINIMAP_TEST_PASS")
 quit()
