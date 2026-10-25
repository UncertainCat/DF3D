extends SceneTree
const FrameOracle=preload("res://tests/machine_frame_oracle.gd")
var world
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
 if not ok:failures.append(message);push_error(message)
func settle(seconds):
 world.set_replay_elapsed(seconds)
 for frame in 4000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0:return
  await process_frame
 check(false,"windmill replay did not settle")
func mesh(complete=true):
 var node=world.get_building_root().get_node_or_null("level_0/building_100")
 check(node!=null,"windmill missing")
 if node==null:return 0
 check(node.layers==(0 if complete else 1),"windmill batch visibility")
 var arrays=node.mesh.surface_get_arrays(0)
 check(arrays[Mesh.ARRAY_CUSTOM2].size()==192,"windmill missing footprint/overhang geometry")
 for c in arrays[Mesh.ARRAY_COLOR]:check(c==Color.WHITE,"wrong stage tint")
 if not complete:check(preload("res://tests/native_planned_pixels.gd").matches(node,"Windmill"),"native planned Windmill pixels")
 return node.mesh.get_instance_id()
func run():
 root.size=Vector2i(384,384)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/windmill.df3dfix")
 check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(7.5,20,7);camera.rotation=Vector3(-PI/2,0,0)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var initial=mesh();var empty=await FrameOracle.shot(self)
 var step=1;var rows=[[3,2,1],[4,0,0],[5,6,7]]
 for complete in [true,false]:
  var retained=initial if complete else 0
  for x in range(-1,2):for y in range(-1,2):for rotation in [0,1,-128,127]:
   await settle(step);var current=mesh(complete)
   if retained==0:retained=current
   check(current==retained,"windmill orientation/rotation rebuilt geometry")
   var frame=rotation if complete else 0
   check(await FrameOracle.matches(self,world,[100],frame,false,rows[x+1][y+1]),"windmill frame disagrees with native atlas cells at "+str(step))
   if not complete and x==1 and y==1 and rotation==1:
    await FrameOracle.shot(self)
    root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/windmill-planned.png"))
   step+=1
 await settle(step);step+=1;var colored=await FrameOracle.shot(self);var colored_mesh=mesh()
 check(await FrameOracle.matches(self,world,[100],127,false,7),"colored windmill frame")
 await settle(step);step+=1;check(colored_mesh==mesh(),"colored rotation rebuilt geometry")
 var colored_idle=await FrameOracle.shot(self)
 check(colored!=colored_idle,"colored rotation ignored")
 check(await FrameOracle.matches(self,world,[100],0,false,7),"colored idle frame")
 await settle(step);step+=1;var cleared=await FrameOracle.shot(self)
 check(cleared!=colored_idle,"item removal retained palette")
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/windmill-rendered.png"))
 await settle(step);step+=1;check(world.get_building_root().get_node_or_null("level_0/building_100")==null,"removed windmill retained geometry")
 await settle(step);check(cleared==await FrameOracle.shot(self),"reused windmill ID retained state")
 check(world.load_fixture(fixture),"reload");await settle(0);check(empty==await FrameOracle.shot(self),"reload retained orientation")
 world.free();camera.free();await process_frame
 print("WINDMILL_RENDER_PASS" if failures.is_empty() else "WINDMILL_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
