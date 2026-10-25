extends "res://tests/layout_stage_render_test.gd"
func inspect_ramp(row,index):
 var info=world.tile_hover_info(Vector3i(4,4,0))
 check(info.get("material","")==("INORGANIC:COAL_BITUMINOUS" if row.state[2]==0 else "PLANT:WILLOW:WOOD"),"ramp material reaches model "+str(index)+" "+str(info))
 var layers={}
 for node in world.get_terrain_root().find_children("*","MeshInstance3D",true,false):
  if node.mesh==null or node.get_meta("df3d_render_batch",false):continue
  for surface in SourceMesh.count(node.mesh):
   var arrays=SourceMesh.arrays(node.mesh,surface);var vertices=arrays[Mesh.ARRAY_VERTEX];var normals=arrays[Mesh.ARRAY_NORMAL];var uv=arrays[Mesh.ARRAY_TEX_UV];var ix=arrays[Mesh.ARRAY_INDEX]
   var mat=SourceMesh.material(node.mesh,surface);var tex=mat.get_shader_parameter("albedo_tex")
   if tex==null:continue
   var image=tex.get_image();var hashes={};var images={}
   var batch=mat.get_shader_parameter("batch_texture") if mat.get_shader_parameter("batch_texture_enabled")==true else null
   for triangle in range(0,ix.size(),3):
    var a=ix[triangle];var b=ix[triangle+1];var c=ix[triangle+2]
    var position=node.to_global((vertices[a]+vertices[b]+vertices[c])/3.0)
    if int(floor(position.x))!=4 or int(floor(position.z))!=4 or normals[a].y<0.1:continue
    var layer=int(arrays[Mesh.ARRAY_CUSTOM0][a]) if batch!=null else -1
    if batch!=null:
     check(layer==int(arrays[Mesh.ARRAY_CUSTOM0][b]) and layer==int(arrays[Mesh.ARRAY_CUSTOM0][c]),"triangle has one texture layer")
     if not images.has(layer):images[layer]=batch.get_layer_data(layer)
     image=images[layer]
    var mid=(uv[a]+uv[b]+uv[c])/3.0*Vector2(image.get_width(),image.get_height());var atlas=Vector2i(int(mid.x)/32,int(mid.y)/32)
    var image_cell=Vector3i(atlas.x,atlas.y,layer)
    if not hashes.has(image_cell):
     var tile=image.get_region(Rect2i(atlas*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
     for n in range(0,bytes.size(),4):
      if bytes[n+3]==0:bytes[n]=0;bytes[n+1]=0;bytes[n+2]=0
     var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);hashes[image_cell]=digest.finish().hex_encode()
    var hash=hashes[image_cell]
    check(hash==row.background or hash==row.rail,"native ramp pixels "+str(index)+" got "+hash)
    if not layers.has(hash):layers[hash]=[]
    for v in [a,b,c]:layers[hash].append(node.to_global(vertices[v]))
 check(layers.has(row.background) and layers.has(row.rail),"both ramp layers "+str(index))
 if not layers.has(row.background) or not layers.has(row.rail):return
 var base=layers[row.background];var rail=layers[row.rail]
 var normal=(base[1]-base[0]).cross(base[2]-base[0]).normalized()
 if normal.y<0:normal=-normal
 var expected=[Vector3.UP,Vector3(0,1,1),Vector3(0,1,-1),Vector3(-1,1,0),Vector3(1,1,0)][int(row.state[1])].normalized()
 check(normal.dot(expected)>0.99,"ramp support orientation "+str(index))
 var base_xz={};var rail_xz={}
 for v in base:base_xz[Vector2(v.x,v.z)]=true
 for v in rail:
  rail_xz[Vector2(v.x,v.z)]=true
  var distance=normal.dot(v-base[0]);check(distance>0 and distance<0.05,"rails follow ramp surface "+str(index))
 check(base_xz==rail_xz,"rail covers matching ramp footprint "+str(index))
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/constructed-ramp.df3dfix")
 check(world.load_fixture(fixture),"ramp fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(7,8,10);camera.look_at(Vector3(4.5,0.5,4.5));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../build/constructed-ramp-pixels.json"))
 for i in refs.size():
  await settle(i);inspect_ramp(refs[i],i)
  if i%50==0:print("CONSTRUCTED_RAMP_CASE ",i)
 await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/constructed-ramp-render.png"))
 for i in [0,refs.size()-1,1]:
  check(world.load_fixture(fixture),"ramp reload")
  await settle(i);inspect_ramp(refs[i],i)
 world.free();camera.free();await process_frame
 print("CONSTRUCTED_RAMP_RENDER_PASS" if failures.is_empty() else "CONSTRUCTED_RAMP_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
