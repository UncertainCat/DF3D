extends SceneTree
const FrameOracle=preload("res://tests/machine_frame_oracle.gd")
# Native phase/art provenance: fixtures/construction/roller_rendering.json.
# This synthetic replay checks renderer lifecycle, not native minecart or mechanical-power effects.
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
 check(false,"roller scene did not settle")
func shot():
 for frame in 3: await process_frame; await RenderingServer.frame_post_draw
 return root.get_texture().get_image().get_data()
func meshes(complete:bool=true):
 var result=[]
 for id in range(100,104):
  var node=world.get_building_root().get_node_or_null("level_0/building_"+str(id))
  check(node!=null,"missing roller "+str(id))
  if node!=null:
   check(node.layers==(0 if complete else 1),"roller source still renders outside batch")
   result.append(node.mesh.get_instance_id())
   var icon=world.selection_icon(3,id,false)
   var expected=world.ui_texture("BUILDING_ICON_ROLLERS",-1)
   check(icon!=null and expected!=null,"missing native Roller header icon")
   if icon!=null and expected!=null:
    check(icon.get_image().get_data()==expected.get_image().get_data(),"Roller header substituted world artwork")
 if complete:check(int(world.mesh_batch_stats().buildings.batches)>0,"no published building batches")
 return result
func inspect_art(changed:bool=false,planned:bool=false,row:int=0):
 for id in range(100,104):
  var node=world.get_building_root().get_node("level_0/building_"+str(id))
  check(node.mesh.get_surface_count()==1,"unexpected roller surfaces")
  var arrays=node.mesh.surface_get_arrays(0)
  var data=arrays[Mesh.ARRAY_CUSTOM2]
  var columns=[]
  # Each flat cell contributes four vertices; CUSTOM2.xy retains its atlas center.
  check(data.size()==48,"wrong three-cell roller geometry")
  for cell in range(3):
   var index=cell*16
   columns.append(roundi(data[index]*15-0.5))
   check(absf(data[index+1]*4-(row+0.5))<0.001,"wrong stone/log base row")
  columns.sort()
  var expected=[0,0,3 if changed and id==100 else 4]
  if planned:expected=[(id-100)%2,(id-100)%2,(id-100)%2]
  check(columns==expected,"wrong per-cell native track/axis artwork "+str(id))
  # Native planned alpha lives in the cached texture, before filtering.
  for color in arrays[Mesh.ARRAY_COLOR]:
   check(color==Color.WHITE,"wrong native planned/completed tint")
  if planned:check(preload("res://tests/native_planned_pixels.gd").matches(node,"Rollers"),"native planned Roller pixels")
func run():
 root.size=Vector2i(640,360)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/roller.df3dfix")
 check(world.load_fixture(fixture),"fixture loads")
 world.set_top_z(0);world.set_window_depth(1)
 var camera=Camera3D.new();root.add_child(camera)
 camera.position=Vector3(8,20,7.5);camera.rotation=Vector3(-PI/2,0,0)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16;camera.current=true
 await settle(0)
 var images=[await shot()]
 var initial=meshes();inspect_art()
 for step in range(1,6):
  await settle(step);images.append(await shot())
  check(initial==meshes(),"position update rebuilt roller geometry at "+str(step))
  check(await FrameOracle.matches(self,world,[100,101,102,103],[0,1,2,-129,-128,127][step],false),"roller does not render native frame cells")
 check(images[0]!=images[1] and images[1]!=images[2] and images[0]!=images[2],"three positions do not animate")
 check(images[0]==images[3],"unknown position does not use zero phase")
 check(images[1]==images[5],"signed native position remainder is wrong")
 check(images[4]!=images[0] and images[4]!=images[1] and images[4]!=images[2],"negative position not rendered")
 check(images[5]==await shot(),"paused roller animated")
 await settle(6)
 var changed=meshes();inspect_art(true)
 check(changed[0]!=initial[0],"changed underlying track did not rebuild owner")
 for index in range(1,4):check(changed[index]==initial[index],"track edit rebuilt unrelated roller")
 await settle(7);check(changed==meshes(),"unrelated track edit rebuilt rollers")
 await settle(8)
 var planned=await shot();var planned_meshes=meshes(false);inspect_art(true,true)
 await settle(9);check(planned==await shot(),"planned roller responds to machine position")
 check(planned_meshes==meshes(false),"planned phase rebuilt geometry")
 await settle(10);meshes()
 await settle(11)
 check(world.get_building_root().get_node_or_null("level_0/building_100")==null,"removed roller retained node")
 await settle(12);var restored=meshes();var before=await shot()
 await settle(13);check(restored==meshes(),"independent machine rebuilt geometry")
 check(before!=await shot(),"independent machine position not rendered")
 var unknown=await shot()
 await settle(14);var log_image=await shot();inspect_art(true,false,2)
 await settle(15);inspect_art(true);check(log_image!=await shot(),"wood block uses log artwork")
 await settle(16);check(unknown==await shot(),"unknown item did not restore painted palette")
 var epoch=world.session_generation()
 check(world.load_fixture(fixture),"fixture reload");await settle(0)
 check(world.session_generation()!=epoch,"reload retained session")
 check(images[0]==await shot(),"reload retained roller position slots")
 await settle(1);check(images[1]==await shot(),"reloaded phases incorrect")
 world.free();camera.free();await process_frame
 print("ROLLER_RENDER_PASS" if failures.is_empty() else "ROLLER_RENDER_FAIL")
 quit(0 if failures.is_empty() else 1)
