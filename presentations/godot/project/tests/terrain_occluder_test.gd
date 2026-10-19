extends SceneTree
const SourceMesh = preload("res://tests/source_mesh.gd")
func _initialize(): call_deferred("run")
func settle(world):
 for frame in 200:
  world.poll()
  if world.pending_block_count()==0: return
  await process_frame
 assert(false,"terrain source update settles")
func geometry(world) -> Array:
 var result=[]
 for node in world.get_terrain_root().find_children("*","MeshInstance3D",true,false):
  if not node.is_visible_in_tree() or node.get_meta("df3d_render_batch",false) or node.name=="backdrop": continue
  for surface in SourceMesh.count(node.mesh):
   result.append(hash(SourceMesh.arrays(node.mesh,surface)))
 result.sort()
 return result
func mesh_instances(world) -> Dictionary:
 var result={}
 for node in world.get_terrain_root().find_children("*","MeshInstance3D",true,false):
  if node.get_meta("df3d_render_batch",false) or node.name=="backdrop":continue
  var materials=[]
  for i in SourceMesh.count(node.mesh):materials.append(SourceMesh.material(node.mesh,i).get_instance_id())
  result[str(node.get_path())]={"instance":node.mesh.get_instance_id(),"shape":hash([node.mesh.get_meta("df3d_batch_arrays",[]),materials])}
 return result
func occluder_instances(world) -> Dictionary:
 var result={}
 for node in world.get_terrain_root().find_children("*","OccluderInstance3D",true,false):
  if node.occluder==null:continue
  result[str(node.get_path())]={"instance":node.get_instance_id(),"shape":hash([node.occluder.get_vertices(),node.occluder.get_indices()])}
 return result
func run():
 if DisplayServer.get_name()!="headless":
  root.use_occlusion_culling=true
  var camera:=Camera3D.new();root.add_child(camera)
  camera.position=Vector3(25,8,30);camera.look_at(Vector3(16,0,16))
 var world := Df3dWorld.new();root.add_child(world)
 assert(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/render-cache.df3dfix")))
 world.set_replay_speed(0)
 world.poll()
 world.set_window_depth(3)
 for top in [2,1,0,2]:
  world.set_top_z(top)
  for frame in 20: world.poll();await process_frame
  var count := 0
  for source in world.get_terrain_root().find_children("*", "MeshInstance3D", true, false):
   if not source.is_visible_in_tree(): continue
   var occluder = source.get_node_or_null("OpaqueOccluder")
   if occluder == null or occluder.occluder == null: continue
   count += 1
   var vertices: PackedVector3Array = occluder.occluder.get_vertices()
   var indices: PackedInt32Array = occluder.occluder.get_indices()
   assert(vertices.size()>0 and indices.size()%3==0)
   for vertex in vertices:
    var point: Vector3=occluder.transform*vertex
    assert(SourceMesh.bounds(source.mesh).grow(0.0001).has_point(point))
    assert(point.y<=top+1.0001)
   for index in indices: assert(index>=0 and index<vertices.size())
  assert(count>0)
 # Off-window source updates must repair covered and cut alternatives before
 # reentry. Compare retained rendering with independent fresh fixture playback.
 var prior_meshes=mesh_instances(world)
 var reused_meshes:=0
 var prior=occluder_instances(world)
 var retained:=0
 for frame in [2,4,5,6,7,8,9,12,13]:
  world.set_top_z(0)
  world.set_replay_elapsed(frame*10.0+5.0)
  await settle(world)
  assert(world.bridge_tick()==100+frame)
  var current_meshes=mesh_instances(world)
  for path in current_meshes:
   if prior_meshes.has(path) and prior_meshes[path].shape==current_meshes[path].shape:
    assert(prior_meshes[path].instance==current_meshes[path].instance,"unchanged mesh payload retains GPU owner")
    reused_meshes+=1
  prior_meshes=current_meshes
  var current=occluder_instances(world)
  for path in current:
   if prior.has(path) and prior[path].shape==current[path].shape:
    assert(prior[path].instance==current[path].instance,"unchanged opaque geometry retains spatial instance")
    retained+=1
  prior=current
  var prepared=world.presentation_perf_stats().terrain_geometry_builds
  world.set_top_z(2)
  await settle(world)
  assert(world.presentation_perf_stats().terrain_geometry_builds==prepared)
  var fresh:=Df3dWorld.new();root.add_child(fresh)
  fresh.set_replay_speed(0)
  assert(fresh.load_fixture(ProjectSettings.globalize_path("res://../../../build/render-cache.df3dfix")))
  fresh.poll();fresh.set_replay_elapsed(frame*10.0+5.0);fresh.poll();fresh.set_top_z(2)
  await settle(fresh)
  assert(geometry(world)==geometry(fresh),"returning level matches fresh source geometry")
  fresh.free()
 assert(reused_meshes>0,"fixture exercises retained mesh payloads")
 assert(retained>0,"fixture exercises retained occluders")
 world.queue_free()
 for frame in 5: await process_frame
 print("TERRAIN_OCCLUDER_PASS")
 quit()
