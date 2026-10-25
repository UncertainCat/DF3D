extends SceneTree
# Native phase/art provenance: fixtures/construction/pump_rendering.json.
# This synthetic replay checks renderer lifecycle, not native pumping effects.
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
 check(false,"pump scene did not settle")
func shot():
 for frame in 3: await process_frame; await RenderingServer.frame_post_draw
 return root.get_texture().get_image().get_data()
func meshes():
 var result=[]
 for id in range(100,104):
  var node=world.get_building_root().get_node_or_null("level_0/building_"+str(id))
  check(node!=null,"missing pump "+str(id))
  if node!=null:
   check(node.layers==0,"pump source still renders outside batch")
   result.append(node.mesh.get_instance_id())
 check(int(world.mesh_batch_stats().buildings.batches)>0,"no published building batches")
 return result
func run():
 root.size=Vector2i(640,360)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/pump-animation.df3dfix")
 check(world.load_fixture(fixture),"fixture loads")
 world.set_top_z(0);world.set_window_depth(1)
 var camera=Camera3D.new();root.add_child(camera)
 camera.position=Vector3(8,20,7.5);camera.rotation=Vector3(-PI/2,0,0)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16;camera.current=true
 await settle(0)
 var first=await shot()
 var initial_meshes=meshes()
 await settle(1)
 var second=await shot()
 check(first!=second,"calendar phase did not animate")
 check(initial_meshes==meshes(),"clock-only update rebuilt pump geometry")
 check(second==await shot(),"paused replay animated")
 await settle(2)
 var idle=await shot()
 RenderingServer.global_shader_parameter_set("machinery_calendar_tick",0)
 check(idle==await shot(),"idle pump responds to phase")
 await settle(3)
 check(idle==await shot(),"unknown calendar retained animation phase")
 await settle(4)
 check(first==await shot(),"activity restart rendered wrong phase")
 await settle(5)
 check(idle==await shot(),"unknown activity retained animation")
 await settle(6)
 check(first==await shot(),"backward calendar retained old phase")
 # Replay is forward-only. Reload is the supported way to return to its start.
 var epoch=world.session_generation()
 check(world.load_fixture(fixture),"fixture reload")
 await settle(0)
 check(world.session_generation()!=epoch,"reload retained session generation")
 check(first==await shot(),"reload retained previous phase")
 await settle(1)
 check(second==await shot(),"reloaded replay cannot advance")
 meshes()
 world.free();camera.free();await process_frame
 print("PUMP_ANIMATION_PASS" if failures.is_empty() else "PUMP_ANIMATION_FAIL")
 quit(0 if failures.is_empty() else 1)
