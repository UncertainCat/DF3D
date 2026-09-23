extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var world := Df3dWorld.new();root.add_child(world)
 assert(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/render-cache.df3dfix")))
 world.set_fixed_render_tick(100)
 world.poll()
 world.set_window_depth(3)
 for top in [2,1,0,2]:
  world.set_top_z(top)
  for frame in 20: world.poll();await process_frame
  var count := 0
  for source in world.get_terrain_root().get_children():
   var occluder = source.get_node_or_null("OpaqueOccluder")
   if occluder == null: continue
   count += 1
   var vertices: PackedVector3Array = occluder.occluder.get_vertices()
   var indices: PackedInt32Array = occluder.occluder.get_indices()
   assert(vertices.size()>0 and indices.size()%3==0)
   for vertex in vertices:
    assert(source.mesh.get_aabb().grow(0.0001).has_point(vertex))
    assert(vertex.y<=top+1.0001)
   for index in indices: assert(index>=0 and index<vertices.size())
  assert(count>0)
 world.queue_free()
 for frame in 5: await process_frame
 print("TERRAIN_OCCLUDER_PASS")
 quit()
