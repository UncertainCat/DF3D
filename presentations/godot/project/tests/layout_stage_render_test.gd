extends "res://tests/bars_render_test.gd"
func pixels(node):
 var got=[]
 for surface in SourceMesh.count(node.mesh):
  var arrays=SourceMesh.arrays(node.mesh,surface)
  for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"layout stage retains native opacity")
  var tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
  if tex==null:tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("sprite_tex")
  check(tex!=null,"layout texture");if tex==null:continue
  var image=tex.get_image();var uv=arrays[Mesh.ARRAY_TEX_UV];var indices=arrays[Mesh.ARRAY_INDEX];var cells={}
  for triangle in range(0,indices.size(),3):
   var mid=(uv[indices[triangle]]+uv[indices[triangle+1]]+uv[indices[triangle+2]])/3.0*Vector2(image.get_width(),image.get_height())
   cells[Vector2i(int(mid.x)/32,int(mid.y)/32)]=true
  for cell in cells:
   var tile=image.get_region(Rect2i(cell*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data();var visible=false
   for b in range(0,bytes.size(),4):
    if bytes[b+3]==0:bytes[b]=0;bytes[b+1]=0;bytes[b+2]=0
    else:visible=true
   if not visible:continue
   var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);var hash=digest.finish().hex_encode()
   if hash not in got:got.append(hash)
 got.sort();return got
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/bars.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(5,24,5);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=9;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/layout_stages.json")).carpenter_stage_pixels.rows
 var previous=null;var seen={};var stages=[0,1,2,3,1,2]
 for i in stages.size():
  await settle(441+i)
  var node=world.get_building_root().get_node_or_null("level_0/building_229");check(node!=null,"layout exists")
  if node==null:continue
  check(node.mesh!=previous,"stage changes rebuild geometry");previous=node.mesh
  var got=pixels(node);var stage=stages[i]
  check(got==refs[stage].hashes,"native stage pixels "+str(stage)+" "+str(got))
  if stage in seen:check(got==seen[stage],"repeated stage restores artwork")
  else:seen[stage]=got
 check(seen.size()==4 and seen[1]!=seen[2],"intermediate stages remain distinct")
 var components=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/layout_stages.json")).component_pixels.rows
 for i in components.size():
  await settle(447+i)
  var row=components[i];var id=229 if row.kind=="Workshop" else 230 if row.kind=="Furnace" else 231
  var node=world.get_building_root().get_node_or_null("level_0/building_"+str(id));check(node!=null,"component layout exists")
  if node!=null:
   var got=pixels(node)
   check(got==row.hashes,"native component layout "+str(i)+" got "+str(got))
 await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/layout-stage.png"))
 check(world.load_fixture(fixture),"reload");await settle(442)
 var restored=world.get_building_root().get_node_or_null("level_0/building_229")
 check(restored!=null,"restored building")
 if restored!=null:check(pixels(restored)==seen[1],"reload stage artwork")
 world.free();camera.free();await process_frame
 print("LAYOUT_STAGE_PASS" if failures.is_empty() else "LAYOUT_STAGE_FAIL");quit(0 if failures.is_empty() else 1)
