extends SceneTree
const FrameOracle=preload("res://tests/machine_frame_oracle.gd")
var world
var hashes={}
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
 check(false,"transmission replay did not settle")
func inspect(complete=true,palette=-1,changed=false):
 var meshes=[]
 for i in 6:
  var node=world.get_building_root().get_node("level_0/building_"+str(100+i))
  meshes.append(node.mesh.get_instance_id());check(node.layers==(0 if complete else 1),"batch visibility")
  var arrays=node.mesh.surface_get_arrays(0);var data=arrays[Mesh.ARRAY_CUSTOM2]
  check(data.size()==(48 if i<2 else 16),"wrong axle footprint")
  for color in arrays[Mesh.ARRAY_COLOR]:check(color.r==1 and color.g==1 and color.b==1 and absf(color.a-1.0)<0.005,"wrong stage tint")
  var image=node.mesh.surface_get_material(0).get_shader_parameter("albedo_tex").get_image()
  var row=2 if i==5 else 3 if i==4 else 0 if i%2==1 or changed and i==2 else 1
  var family="GEAR" if i==5 else "VERTICAL" if i==4 else "NS" if row==0 else "WE"
  check(absf(data[1]*image.get_height()/32-(row+0.5))<0.001,"wrong native axle axis")
  for frame in [1,2]:
   if not complete and frame==2:continue
   var tile=image.get_region(Rect2i((frame-1+(0 if i==5 else 2))*32,row*32,32,32));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps()
   var bytes=tile.get_data()
   for offset in range(0,bytes.size(),4):
    if bytes[offset+3]==0:bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0
   var key=family+"_"+str(frame)+(":pal" if i==5 else ":shaftpal")+str(palette)+("" if i==5 else ":fittingsraw")+":half"+("False" if complete else "True")
   var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
   check(hashes.has(key) and digest.finish().hex_encode()==hashes.get(key,""),"native composite RGBA mismatch "+key)
 return meshes
func run():
 var evidence=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../fixtures/construction/machinery_directions.json")))
 hashes=evidence.axles_gears_rendering_native.rgba_sha256
 root.size=Vector2i(768,384);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/transmission.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(12,20,7.5);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1);var initial=inspect();var images=[await FrameOracle.shot(self)]
 for step in range(1,8):
  await settle(step);check(initial==inspect(),"phase rebuilt transmission geometry");images.append(await FrameOracle.shot(self))
  check(await FrameOracle.matches(self,world,range(100,106),[0,1,2,-129,-128,-3,-1,127][step],false),"wrong native phase cells")
 check(images[0]!=images[1] and images[1]==images[7],"positive odd animation")
 for step in range(2,7):check(images[0]==images[step],"signed or unknown phase mismatch")
 await settle(8);var planned=inspect(false);var planned_image=await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/transmission-planned.png"))
 await settle(9);check(planned==inspect(false),"planned phase rebuilt geometry");check(planned_image==await FrameOracle.shot(self),"planned machinery animated")
 await settle(10);var wood=inspect(true,6);var wood_image=await FrameOracle.shot(self);check(wood_image!=images[0],"wood material ignored")
 await settle(11);check(wood==inspect(true,6),"colored animation rebuilt geometry");check(wood_image!=await FrameOracle.shot(self),"colored animation ignored")
 await settle(12);inspect(true,50);await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/transmission-rendered.png"))
 await settle(13);inspect();check(images[1]==await FrameOracle.shot(self),"item removal retained palette")
 await settle(14);check(world.get_building_root().get_node_or_null("level_0/building_100")==null,"removed axle retained geometry")
 await settle(15);var restored=inspect()
 await settle(16);check(restored==inspect(),"independent phase rebuilt geometry")
 await settle(17);var changed=inspect(true,-1,true);check(changed[2]!=restored[2],"one-cell orientation failed to update artwork")
 for i in [0,1,3,4,5]:check(changed[i]==restored[i],"axis change rebuilt unrelated building")
 check(world.load_fixture(fixture),"reload");await settle(0);inspect();check(images[0]==await FrameOracle.shot(self),"reload retained transmission state")
 world.free();camera.free();await process_frame
 print("TRANSMISSION_RENDER_PASS" if failures.is_empty() else "TRANSMISSION_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
