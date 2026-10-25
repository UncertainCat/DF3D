extends "res://tests/layout_stage_render_test.gd"
func cell_pixels(node):
 var got={}
 for surface in SourceMesh.count(node.mesh):
  var arrays=SourceMesh.arrays(node.mesh,surface)
  for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"native progress opacity")
  var tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
  if tex==null:tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("sprite_tex")
  check(tex!=null,"decal texture");if tex==null:continue
  var image=tex.get_image();var uv=arrays[Mesh.ARRAY_TEX_UV];var vertices=arrays[Mesh.ARRAY_VERTEX];var indices=arrays[Mesh.ARRAY_INDEX];var hashes={}
  for triangle in range(0,indices.size(),3):
   var a=indices[triangle];var b=indices[triangle+1];var c=indices[triangle+2]
   var mid=(uv[a]+uv[b]+uv[c])/3.0*Vector2(image.get_width(),image.get_height())
   var atlas=Vector2i(int(mid.x)/32,int(mid.y)/32)
   if not hashes.has(atlas):
    var tile=image.get_region(Rect2i(atlas*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
    for n in range(0,bytes.size(),4):
     if bytes[n+3]==0:bytes[n]=0;bytes[n+1]=0;bytes[n+2]=0
    var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);hashes[atlas]=digest.finish().hex_encode()
   var position=node.to_global((vertices[a]+vertices[b]+vertices[c])/3.0)
   var key=str(int(floor(position.x))-4)+","+str(int(floor(position.z))-4)
   if got.has(key):check(got[key]==hashes[atlas],"one native image per cell")
   got[key]=hashes[atlas]
 return got
func check_case(row,index):
 var node=world.get_building_root().get_node_or_null("level_0/building_100")
 check((node!=null)==not row.cells.is_empty(),"native visibility "+str(index))
 if node!=null:
  var got=cell_pixels(node)
  check(got==row.cells,"native cell positions and pixels "+str(index)+" state "+str(row.state)+" got "+str(got))
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/farm-road.df3dfix")
 check(world.load_fixture(fixture),"farm/road fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(7,24,7);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../build/farm-road-pixels.json"))
 for i in refs.size():
  await settle(i);check_case(refs[i],i)
  if i%100==0:print("FARM_ROAD_CASE ",i)
 await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/farm-road-render.png"))
 for i in [0,refs.size()-1,1]:
  check(world.load_fixture(fixture),"farm/road reload")
  await settle(i);check_case(refs[i],i)
 world.free();camera.free();await process_frame
 print("FARM_ROAD_RENDER_PASS" if failures.is_empty() else "FARM_ROAD_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
