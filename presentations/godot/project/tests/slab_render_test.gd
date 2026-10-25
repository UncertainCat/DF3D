extends SceneTree
const SourceMesh=preload("res://tests/source_mesh.gd")
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
 check(false,"slab replay did not settle")
func inspect(material,stage):
 for i in 28:
  var node=world.get_building_root().get_node("level_0/building_"+str(100+i))
  check(node.layers==(0 if stage==1 else 1),"slab stage visibility")
  var engraving=i-1
  var row=0 if material=="none" or stage==0 or engraving<0 or engraving>=1 and engraving<=5 else 1 if engraving==0 else engraving-4
  var arrays=SourceMesh.arrays(node.mesh,0)
  for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"slab has non-native vertex tint")
  var texture=SourceMesh.material(node.mesh,0).get_shader_parameter("sprite_tex")
  check(texture!=null,"missing slab texture")
  if texture==null:continue
  var image=texture.get_image()
  for uv in arrays[Mesh.ARRAY_TEX_UV]:check(uv.x>=-0.001 and uv.x*image.get_width()<=32.001 and uv.y*image.get_height()>=row*32-0.001 and uv.y*image.get_height()<=(row+1)*32+0.001,"slab uses wrong engraving cell")
  var tile=image.get_region(Rect2i(0,row*32,32,32));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
  for offset in range(0,bytes.size(),4):
   if bytes[offset+3]==0:bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0
  var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
  var key=material+":"+str(stage)+":"+str(engraving)
  check(digest.finish().hex_encode()==hashes.get(key,""),"native slab RGBA mismatch "+key)
func run():
 hashes=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../fixtures/construction/slab_rendering.json"))).rgba_sha256
 root.size=Vector2i(768,512);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/slab.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(12,20,7.5);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1);inspect("INORGANIC:GRANITE",1);var initial=await FrameOracle.shot(self)
 await settle(1);inspect("INORGANIC:IRON",1);check(initial!=await FrameOracle.shot(self),"slab first-item palette ignored")
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/slab-rendered.png"))
 await settle(2);inspect("INORGANIC:IRON",0);await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/slab-planned.png"))
 await settle(3);inspect("none",1)
 await settle(4);check(world.get_building_root().get_node_or_null("level_0/building_100")==null,"removed slab retained geometry")
 await settle(5);check(world.get_building_root().get_node_or_null("level_0/building_100")!=null,"slab re-add failed")
 check(world.load_fixture(fixture),"reload");await settle(0);inspect("INORGANIC:GRANITE",1);check(initial==await FrameOracle.shot(self),"reload retained slab state")
 world.free();camera.free();await process_frame
 print("SLAB_RENDER_PASS" if failures.is_empty() else "SLAB_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
