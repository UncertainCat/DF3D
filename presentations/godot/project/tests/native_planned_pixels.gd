extends RefCounted
const SourceMesh=preload("res://tests/source_mesh.gd")
static func matches(node,family:String)->bool:
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/planned_machine_pixels.json")).families[family].hashes
 var seen={}
 for surface in SourceMesh.count(node.mesh):
  var arrays=SourceMesh.arrays(node.mesh,surface)
  var tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("albedo_tex")
  if tex==null:tex=SourceMesh.material(node.mesh,surface).get_shader_parameter("sprite_tex")
  if tex==null:return false
  var image=tex.get_image();var uv=arrays[Mesh.ARRAY_TEX_UV];var indices=arrays[Mesh.ARRAY_INDEX];var cells={}
  for triangle in range(0,indices.size(),3):
   var mid=(uv[indices[triangle]]+uv[indices[triangle+1]]+uv[indices[triangle+2]])/3.0*Vector2(image.get_width(),image.get_height())
   cells[Vector2i(int(mid.x)/32,int(mid.y)/32)]=true
  for cell in cells:
   var tile=image.get_region(Rect2i(cell*32,Vector2i(32,32)));tile.convert(Image.FORMAT_RGBA8);tile.clear_mipmaps();var bytes=tile.get_data()
   for i in range(0,bytes.size(),4):
    if bytes[i+3]==0:bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0
   var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);var digest=h.finish().hex_encode()
   if digest not in refs:return false
   seen[digest]=true
 return not seen.is_empty()
