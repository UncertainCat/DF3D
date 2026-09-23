extends SceneTree
# Runtime assets on real terrain faces, frozen camera residency, and real state
# cleanup. Run make_spatter_fixture first. No DF process or save modifications.
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
 if not ok: failures.append(message);push_error(message)
func settle(world):
 for frame in 100:
  world.poll()
  await process_frame
  if world.pending_block_count()==0: return
 check(false,"spatter meshes settle")
func sources(world) -> Array:
 var ids: Array=[]
 for node in world.get_terrain_root().get_children():
  if node is MeshInstance3D: ids.append(node.mesh.get_instance_id())
 return ids
func spattered(world) -> int:
 var count=0
 for node in world.get_terrain_root().get_children():
  if not node is MeshInstance3D or node.mesh==null: continue
  for surface in node.mesh.get_surface_count():
   var mat=node.mesh.surface_get_material(surface)
   if mat is ShaderMaterial and mat.get_shader_parameter("spattered")==true:
    var data=node.mesh.surface_get_arrays(surface)
    check(data[Mesh.ARRAY_TEX_UV2]!=null and data[Mesh.ARRAY_TEX_UV2].size()==data[Mesh.ARRAY_VERTEX].size(),"source and batch preserve spatter UV2")
    count+=1
 return count
func capture(name: String):
 if DisplayServer.get_name()=="headless": return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/spatter-"+name+".png"))
func run():
 root.size=Vector2i(960,720)
 var world=Df3dWorld.new();root.add_child(world)
 check(world.load_assets(""),"installed assets resolve")
 check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/spatter.df3dfix")),"fixture validates")
 world.set_replay_speed(0);world.set_replay_elapsed(0)
 world.poll();world.set_top_z(0);world.set_window_depth(1)
 var camera=Camera3D.new();root.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=18
 camera.position=Vector3(8,14,17);camera.look_at(Vector3(8,0,8));camera.current=true
 await settle(world)
 check(world.tile_spatters(Vector3i(6,6,0)).size()==1,"real tile contamination available")
 check(world.tile_spatters(Vector3i(12,7,0)).size()==3,"mixed deposits retained as native state")
 check(spattered(world)>0,"native blood material blended into terrain surfaces")
 var before=sources(world)
 var revision=world.spatter_revision()
 var terrain_revision=world.terrain_revision()
 var count=world.face_count()
 for frame in 30:
  camera.position.x=8+sin(frame*0.2)*2;camera.look_at(Vector3(8,0,8));world.poll();await process_frame
 check(sources(world)==before,"camera motion leaves resident meshes unchanged")
 check(world.spatter_revision()==revision,"camera leaves contamination state unchanged")
 camera.position=Vector3(8,14,17);camera.look_at(Vector3(8,0,8))
 await capture("flat")
 world.set_replay_elapsed(10);await settle(world)
 check(world.spatter_revision()==revision,"identical repeated native block is a no-op")
 check(sources(world)==before,"identical repeated state preserves geometry")
 world.set_replay_elapsed(20);await settle(world)
 check(world.tile_spatters(Vector3i(6,6,0)).is_empty(),"empty block removes blood")
 check(world.tile_spatters(Vector3i(12,7,0)).is_empty(),"replacement removes all mixed deposits without accumulation history")
 check(spattered(world)==0,"cleanup removes visual stain")
 check(world.terrain_revision()==terrain_revision,"contamination does not invalidate terrain semantics")
 check(world.face_count()==count,"blood adds no duplicate ground geometry")
 await capture("clean")
 print("GROUND_SPATTER_TEST ",JSON.stringify({"failures":failures,"faces":count,"spatter_revision":world.spatter_revision()}))
 world.queue_free();camera.queue_free()
 for frame in 3:await process_frame
 quit(0 if failures.is_empty() else 1)
