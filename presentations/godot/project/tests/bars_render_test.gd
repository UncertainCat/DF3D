extends SceneTree
const SourceMesh=preload("res://tests/source_mesh.gd")
const FrameOracle=preload("res://tests/machine_frame_oracle.gd")
var world
var hashes={}
var failures=[]
var simple_hashes={}
func _initialize():call_deferred("run")
func check(ok,message):
 if not ok:failures.append(message);push_error(message)
func settle(seconds):
 world.set_replay_elapsed(seconds)
 for frame in 4000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0:return
  await process_frame
 check(false,"bars replay did not settle")
func inspect(material,stage,reversed_masks=false):
 inspect_simple(material,stage,reversed_masks)
 for i in 16:
  var node=world.get_building_root().get_node("level_0/building_"+str(100+i))
  check(node.layers==(0 if stage==1 else 1),"bars stage visibility")
  var got=[]
  for surface in SourceMesh.count(node.mesh):
   var arrays=SourceMesh.arrays(node.mesh,surface)
   for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"bars vertex tint")
   var texture=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
   check(texture!=null,"missing bars texture")
   if texture==null:continue
   var image=texture.get_image()
   # Direct upper art occupies one source cell; composited base art is 32x32.
   # Use the UV bounding-box midpoint to avoid neighboring cells at a shared border.
   var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
   for uv in arrays[Mesh.ARRAY_TEX_UV]:lo=lo.min(uv);hi=hi.max(uv)
   var mid=(lo+hi)*0.5*Vector2(image.get_width(),image.get_height())
   var cell=Vector2i(int(mid.x)/32,int(mid.y)/32)
   var tile=image.get_region(Rect2i(cell*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
   for offset in range(0,bytes.size(),4):
    if bytes[offset+3]==0:bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0
   var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);got.append(digest.finish().hex_encode())
  got.sort()
  var mask=15-i if reversed_masks else i
  var key=material+":"+str(stage)+":"+str(mask)
  check(got==hashes.get(key,[]),"native bars RGBA mismatch "+key+" got "+str(got))
func inspect_simple(material,stage,reversed_masks=false):
 for i in (19 if stage==0 else 6):
  var node=world.get_building_root().get_node("level_0/building_"+str(200+i))
  check(node.layers==(0 if stage==1 else 1),"bars stage visibility")
  var got=[]
  for surface in SourceMesh.count(node.mesh):
   var arrays=SourceMesh.arrays(node.mesh,surface)
   for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"bars vertex tint")
   var texture=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
   if texture==null:texture=SourceMesh.material(node.mesh,surface).get_shader_parameter("sprite_tex")
   check(texture!=null,"missing bars texture")
   if texture==null:continue
   var image=texture.get_image()
   # Direct upper art occupies one source cell; composited base art is 32x32.
   # Use the UV bounding-box midpoint to avoid neighboring cells at a shared border.
   var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
   for uv in arrays[Mesh.ARRAY_TEX_UV]:lo=lo.min(uv);hi=hi.max(uv)
   var mid=(lo+hi)*0.5*Vector2(image.get_width(),image.get_height())
   var cell=Vector2i(int(mid.x)/32,int(mid.y)/32)
   var tile=image.get_region(Rect2i(cell*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
   for offset in range(0,bytes.size(),4):
    if bytes[offset+3]==0:bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0
   var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);got.append(digest.finish().hex_encode())
  got.sort()
  var key=(["BarsFloor","Support","WindowGem"][i])+":"+("INORGANIC:RUBY" if i==2 else material)+":"+str(stage) if i<3 else "Well:"+str((i-3) ^ int(reversed_masks))+":"+str(stage)
  if i>=6:key=["Door","Hatch","GrateWall","GrateFloor","Floodgate","Chair","Table","Box","Cabinet","Coffin","Cage","Chain","AnimalTrap"][i-6]+":planned"
  if i==5:key="WindowGlass:GLASS_GREEN:"+str(stage)
  check(got==[simple_hashes.get(key,"")],"native structure RGBA mismatch "+key+" got "+str(got))
func inspect_opening(sample):
 var id={"Door":206,"Hatch":207,"Chair":211,"Table":212,"Box":213,"Cabinet":214,"Armorstand":219,"Weaponrack":220,"Chain":217,"Coffin":215,"Cage":216,"AnimalTrap":218,"Bed":221,"Bookcase":222,"DisplayFurniture":223,"OfferingPlace":224,"Hive":225,"NestBox":226,"TractionBench":227}[sample.kind]
 var node=world.get_building_root().get_node("level_0/building_"+str(id))
 var got=[]
 for surface in SourceMesh.count(node.mesh):
  var arrays=SourceMesh.arrays(node.mesh,surface)
  for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"completed opening vertex tint")
  var texture=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
  if texture==null:texture=SourceMesh.material(node.mesh,surface).get_shader_parameter("sprite_tex")
  check(texture!=null,"completed opening texture")
  if texture==null:continue
  var source=texture.get_image()
  var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
  for uv in arrays[Mesh.ARRAY_TEX_UV]:lo=lo.min(uv);hi=hi.max(uv)
  var mid=(lo+hi)*0.5*Vector2(source.get_width(),source.get_height())
  var cell=Vector2i(int(mid.x)/32,int(mid.y)/32)
  var image=source.get_region(Rect2i(cell*32,Vector2i(32,32)));image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
  var bytes=image.get_data()
  for offset in range(0,bytes.size(),4):
   if bytes[offset+3]==0:bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0
  var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);got.append(digest.finish().hex_encode())
 check(got==[sample.sha256],"native completed "+str(sample)+" got "+str(got))
func run():
 hashes=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../fixtures/construction/bars_rendering.json"))).rgba_sha256
 simple_hashes=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json")).floor_and_support.rgba_sha256
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/bars.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(9,24,9);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1);inspect("INORGANIC:IRON",1);var initial=await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/bars-rendered.png"))
 await settle(1);inspect("INORGANIC:IRON",0);await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/bars-planned.png"))
 await settle(2);inspect("none",1);var before=await FrameOracle.shot(self)
 await settle(3);inspect("none",1,true);check(before!=await FrameOracle.shot(self),"bars adjacency did not change visible geometry")
 await settle(4);check(world.get_building_root().get_node_or_null("level_0/building_100")==null,"removed bars retained geometry")
 check(world.get_building_root().get_node_or_null("level_0/building_203")==null,"removed well retained geometry")
 await settle(5);check(world.get_building_root().get_node_or_null("level_0/building_100")!=null,"bars re-add failed")
 check(world.load_fixture(fixture),"reload");await settle(0);inspect("INORGANIC:IRON",1);check(initial==await FrameOracle.shot(self),"reload retained bars state")
 var opening_refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json")).completed_opening_native_reference.rgba_sha256
 for i in opening_refs.size():
  await settle(6+i);inspect_opening(opening_refs[i])
 var furniture_refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json")).completed_furniture_native_reference.rgba_sha256
 for i in furniture_refs.size():
  await settle(6+opening_refs.size()+i);inspect_opening(furniture_refs[i])
 await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/openings-completed.png"))
 check(world.load_fixture(fixture),"opening reload");await settle(0);check(initial==await FrameOracle.shot(self),"opening identity or color survived reload")
 world.free();camera.free();await process_frame
 print("BARS_RENDER_PASS" if failures.is_empty() else "BARS_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
