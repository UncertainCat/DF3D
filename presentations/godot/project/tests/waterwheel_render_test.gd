extends SceneTree
const FrameOracle=preload("res://tests/machine_frame_oracle.gd")
# Native oracle: machinery_directions.json.waterwheel_animation_native.
# Synthetic replay checks rendering and resource lifetime, not mechanical power.
var failures: Array = []
var world
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
 if not ok: failures.append(message); push_error(message)
func settle(elapsed: float):
 world.set_replay_elapsed(elapsed)
 for frame in 4000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0: return
  await process_frame
 check(false,"wheel scene did not settle")
func shot():
 for frame in 3: await process_frame; await RenderingServer.frame_post_draw
 return root.get_texture().get_image().get_data()
func meshes(complete:bool=true):
 var result=[]
 for id in range(100,102):
  var node=world.get_building_root().get_node_or_null("level_0/building_"+str(id))
  check(node!=null,"missing wheel "+str(id))
  if node==null:continue
  result.append(node.mesh.get_instance_id())
  check(node.layers==(0 if complete else 1),"wheel batch visibility")
  var arrays=node.mesh.surface_get_arrays(0)
  var data=arrays[Mesh.ARRAY_CUSTOM2]
  check(data.size()==(96 if id==100 else 64),"missing wheel overhang cells")
  if complete:
   for cell in range(data.size()/16):check(data[cell*16+3]==(12 if id==100 else 13),"wheel axis code")
  for color in arrays[Mesh.ARRAY_COLOR]:
   check(color==Color.WHITE,"wheel stage tint")
  if not complete:check(preload("res://tests/native_planned_pixels.gd").matches(node,"WaterWheel"),"native planned Water Wheel pixels")
 return result
func run():
 root.size=Vector2i(640,360)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/waterwheel.df3dfix")
 check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera)
 camera.position=Vector3(8,20,7.5);camera.rotation=Vector3(-PI/2,0,0)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var initial=meshes();var images=[await shot()]
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/waterwheel-frame-one.png"))
 for step in range(1,9):
  await settle(step);images.append(await shot())
  check(initial==meshes(),"phase rebuilt wheel geometry")
  check(await FrameOracle.matches(self,world,[100,101],[0,1,2,-129,-128,-3,-2,-1,127][step],true),"wheel does not render native frame cells")
  if step==1:await shot();root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/waterwheel-frame-two.png"))
 check(images[0]!=images[1],"wheel did not animate")
 for step in range(2,8):check(images[0]==images[step],"signed or unknown wheel phase incorrect")
 check(images[1]==images[8],"positive odd phase incorrect")
 check(images[8]==await shot(),"paused wheel animated")
 await settle(9);var planned=await shot();var planned_meshes=meshes(false)
 await settle(10);check(planned==await shot(),"planned wheel animated");check(planned_meshes==meshes(false),"planned phase rebuilt geometry")
 await settle(11);var colored=await shot();var colored_meshes=meshes()
 check(colored!=images[0],"first item material ignored")
 await settle(12);check(colored!=await shot(),"colored wheel did not animate");check(colored_meshes==meshes(),"colored animation rebuilt geometry")
 await settle(13);check(images[1]==await shot(),"empty wheel retained item palette")
 await settle(14);check(world.get_building_root().get_node_or_null("level_0/building_100")==null,"removed wheel retained geometry")
 await settle(15);check(images[1]==await shot(),"readded wheel retained stale phase");var restored=meshes()
 await settle(16);check(restored==meshes(),"independent phase rebuilt wheels");check(images[1]!=await shot(),"independent phase ignored")
 check(world.load_fixture(fixture),"reload");await settle(0);check(images[0]==await shot(),"reload retained phase slots")
 world.free();camera.free();await process_frame
 print("WATERWHEEL_RENDER_PASS" if failures.is_empty() else "WATERWHEEL_RENDER_FAIL")
 quit(0 if failures.is_empty() else 1)
