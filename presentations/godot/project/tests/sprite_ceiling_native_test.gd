extends SceneTree
const Geometry=preload("res://scripts/sprite_geometry.gd")
class ReferenceSource:
 extends RefCounted
 var world
 func terrain_revision(): return world.terrain_revision()
 func session_generation(): return world.session_generation()
 func get_top_z(): return world.get_top_z()
 func tile_hover_info(tile): return world.tile_hover_info(tile)
func _initialize(): call_deferred("run")
func run():
 var world=Df3dWorld.new()
 root.add_child(world)
 world.set_fixed_render_tick(1000)
 if not world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")):
  push_error("Roof fixture failed"); quit(1); return
 world.poll()
 var source=ReferenceSource.new()
 source.world=world
 var reference=Geometry.new()
 reference.configure(source)
 var checked=0
 for top in [0,110,127,150]:
  world.set_top_z(top)
  reference.refresh()
  for x in range(-1,world.map_size().x+1,17):
   for y in range(-1,world.map_size().z+1,23):
    for floor_z in [top-3,top-1,top]:
     for size in [Vector3(0.5,1.0,0.5),Vector3(2.5,3.2,1.5)]:
      var bounds=AABB(Vector3(x+0.1,floor_z+0.25,y+0.1),size)
      if not is_equal_approx(world.sprite_ceiling(bounds,floor_z),reference.ceiling_for(bounds,floor_z)):
       push_error("Native roof differs from reference at "+str(bounds)); quit(1); return
      checked+=1
 print("SPRITE_CEILING_NATIVE_PASS comparisons=",checked)
 world.free()
 quit()
