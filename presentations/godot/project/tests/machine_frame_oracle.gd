extends RefCounted
# Compare the dynamic shader with static UVs selecting the native atlas cells.
# This catches invalid offsets even when successive frames differ and geometry
# remains stable. Native cells are 32px on the supported wheel/roller sheets.
static func shot(tree):
 for frame in 3:await tree.process_frame;await RenderingServer.frame_post_draw
 return tree.root.get_texture().get_image().get_data()
static func matches(tree,world,ids,phase:int,wheel:bool,windmill_row:int=-1):
 var animated=Node3D.new();var reference=Node3D.new()
 tree.root.add_child(animated);tree.root.add_child(reference);reference.hide()
 for id in ids:
  var source=world.get_building_root().get_node("level_0/building_"+str(id))
  var actual=MeshInstance3D.new();actual.mesh=source.mesh;animated.add_child(actual);actual.global_transform=source.global_transform
  var mesh=ArrayMesh.new()
  for surface in source.mesh.get_surface_count():
   var material=source.mesh.surface_get_material(surface)
   var texture=material.get_shader_parameter("albedo_tex")
   var arrays=source.mesh.surface_get_arrays(surface).duplicate(true)
   var uv=arrays[Mesh.ARRAY_TEX_UV];var data=arrays[Mesh.ARRAY_CUSTOM2]
   for vertex in uv.size():
    var code=roundi(data[vertex*4+3]);var shift=Vector2.ZERO
    if code==15:
     if phase>0 and phase%2==1:shift=Vector2(32,0)
    elif windmill_row>=0:
     shift=Vector2(0 if phase==0 else 96,windmill_row*128)
    elif wheel:
     if phase>0 and phase%2==1:shift=Vector2(0,64) if code==12 else Vector2(32,0)
    else:
     var direction=code/3;var coordinate=code%3
     var remainder=0 if phase==-129 else phase%3
     var target=remainder if direction==1 or direction==2 else 2-remainder
     if coordinate!=target:shift=Vector2(0,32)
    shift/=Vector2(texture.get_width(),texture.get_height())
    uv[vertex]+=shift;data[vertex*4]+=shift.x;data[vertex*4+1]+=shift.y
    data[vertex*4+3]=-1 # Static reference bypasses all dynamic frame selection.
   arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_CUSTOM2]=data
   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
   mesh.surface_set_material(surface,material)
  var expected=MeshInstance3D.new();expected.mesh=mesh;reference.add_child(expected);expected.global_transform=source.global_transform
 var hidden=[]
 for child in world.get_children():
  if child is Node3D and child.visible:hidden.append(child);child.hide()
 var actual_pixels=await shot(tree)
 animated.hide();reference.show();var reference_pixels=await shot(tree)
 animated.free();reference.free()
 for child in hidden:child.show()
 return actual_pixels==reference_pixels
