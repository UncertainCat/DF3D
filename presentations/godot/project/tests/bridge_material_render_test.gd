extends "res://tests/bars_render_test.gd"
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/bars.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(9,24,9);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1);var initial=await FrameOracle.shot(self)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json"))
 var offset=6
 for key in ["completed_opening_native_reference","completed_furniture_native_reference","planned_equipment_furniture","completed_chain_native_reference","completed_ordinary_native_reference","tool_furniture_native_reference","completed_bed_component_reference"]:offset+=refs[key].rgba_sha256.size()
 var rows=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bridge_rendering.json")).material_reference.rgba_sha256
 for i in rows.size():
  await settle(offset+i)
  var node=world.get_building_root().get_node_or_null("level_0/building_228")
  var got=[]
  if node!=null:
   for surface in SourceMesh.count(node.mesh):
    var arrays=SourceMesh.arrays(node.mesh,surface)
    for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,"bridge vertex tint "+str(i))
    var tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
    if tex==null:tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("sprite_tex")
    check(tex!=null,"bridge texture");if tex==null:continue
    var image=tex.get_image();var uv=arrays[Mesh.ARRAY_TEX_UV];var indices=arrays[Mesh.ARRAY_INDEX];var cells={}
    for triangle in range(0,indices.size(),3):
     var mid=(uv[indices[triangle]]+uv[indices[triangle+1]]+uv[indices[triangle+2]])/3.0*Vector2(image.get_width(),image.get_height())
     cells[Vector2i(int(mid.x)/32,int(mid.y)/32)]=true
    for cell in cells:
     var tile=image.get_region(Rect2i(cell*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
     for b in range(0,bytes.size(),4):
      if bytes[b+3]==0:bytes[b]=0;bytes[b+1]=0;bytes[b+2]=0
     var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);var hash=digest.finish().hex_encode()
     if hash not in got:got.append(hash)
  got.sort();check(got==rows[i].hashes,"bridge native pixels "+str(i)+" "+str(got))
 await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/bridge-material.png"))
 check(world.load_fixture(fixture),"bridge reload");await settle(0);check(initial==await FrameOracle.shot(self),"bridge state survived reload")
 world.free();camera.free();await process_frame
 print("BRIDGE_MATERIAL_PASS" if failures.is_empty() else "BRIDGE_MATERIAL_FAIL");quit(0 if failures.is_empty() else 1)
