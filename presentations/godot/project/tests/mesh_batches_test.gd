extends SceneTree
# Compare the complete indexed vertex streams grouped by effective material.
# Sources remain semantic objects; only render submission is merged.
var failures: Array=[]
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
 if not value: failures.append(message); push_error(message)
func settle(world):
 for i in 4000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0 and world.composite_pending_count()==0 and world.item_composite_pending_count()==0: return
  await process_frame
 check(false,"batch rebuilds settle")
func signature(world, sources: bool) -> Dictionary:
 var out={}
 for holder in [world.get_terrain_root(),world.get_building_root()]:
  for node in holder.get_children():
   if not node is MeshInstance3D or node.mesh==null or not node.visible: continue
   if sources and node.get_meta("df3d_render_batch",false): continue
   if not sources and node.layers==0: continue
   for surface in node.mesh.get_surface_count():
    var mat=node.get_surface_override_material(surface)
    if mat==null: mat=node.mesh.surface_get_material(surface)
    var key=mat.get_instance_id()
    var a=node.mesh.surface_get_arrays(surface)
    var layers=a[Mesh.ARRAY_CUSTOM0]
    var provenance=mat.get_meta("df3d_batch_source_materials",PackedInt64Array())
    var v=a[Mesh.ARRAY_VERTEX]
    var n=a[Mesh.ARRAY_NORMAL]
    var c=a[Mesh.ARRAY_COLOR]
    var uv=a[Mesh.ARRAY_TEX_UV]
    var uv2=a[Mesh.ARRAY_TEX_UV2]
    var ix=a[Mesh.ARRAY_INDEX]
    for j in (ix.size() if ix!=null and not ix.is_empty() else v.size()):
     var i=ix[j] if ix!=null and not ix.is_empty() else j
     if layers!=null and not provenance.is_empty(): key=provenance[int(layers[i])]
     if not out.has(key): out[key]=[0,0]
     var h=hash([v[i],n[i].snapped(Vector3.ONE*0.001) if n!=null else null,c[i] if c!=null else null,uv[i] if uv!=null else null,uv2[i] if uv2!=null else null])
     out[key][0]+=1
     out[key][1]+=h
 return out
func run():
 var w=Df3dWorld.new()
 root.add_child(w)
 check(w.load_assets(""),"assets load")
 w.set_fixed_render_tick(preload("res://tests/recorded_fixture.gd").tick())
 check(w.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")),"fixture loads")
 w.poll()
 w.set_window_depth(4)
 w.set_top_z(preload("res://tests/recorded_fixture.gd").top_z())
 await settle(w)
 var stats=w.mesh_batch_stats()
 print("MESH_BATCH_STATS ",JSON.stringify(stats))
 check(stats.terrain.batches>0 and stats.buildings.batches>0,"terrain and buildings are batched")
 check(stats.terrain.max_surfaces_per_mesh<=RenderingServer.MAX_MESH_SURFACES and stats.buildings.max_surfaces_per_mesh<=RenderingServer.MAX_MESH_SURFACES,"published mesh chunks respect engine surface capacity")
 # Godot repacks normal/tangent frames on upload; allow normal quantization
 # at 0.001 while positions, colors, UVs, counts and material IDs stay exact.
 check(signature(w,true)==signature(w,false),"merged vertex attributes/materials preserved within normal packing precision")
 w.set_mesh_batching_enabled(false)
 check(signature(w,true)==signature(w,false),"disable immediately restores source rendering")
 w.set_mesh_batching_enabled(true)
 await settle(w)
 check(signature(w,true)==signature(w,false),"reenable preserves geometry")
 w.set_top_z(preload("res://tests/recorded_fixture.gd").top_z()-1)
 w.poll()
 check(signature(w,true)==signature(w,false),"deferred sources preserve geometry before batches settle")
 await settle(w)
 check(w.mesh_batch_stats().buildings.deferred_sources==0,"paused polls rejoin all stable deferred sources")
 check(signature(w,true)==signature(w,false),"slice removal and recut preserve geometry")
 w.set_top_z(preload("res://tests/recorded_fixture.gd").top_z())
 w.set_window_depth(1)
 await settle(w)
 check(signature(w,true)==signature(w,false),"window shrink removes stale batch geometry")
 w.set_zone_overlays_visible(true)
 check(signature(w,true)==signature(w,false),"zone overlays remain independent")
 w.set_zone_overlays_visible(false)
 # Cancel a partially prepared window, then replace the entire source epoch.
 w.set_window_depth(24)
 w.poll()
 w.set_mesh_batching_enabled(false)
 check(signature(w,true)==signature(w,false),"disable during incremental work restores sources")
 w.set_mesh_batching_enabled(true)
 w.poll()
 check(w.load_fixture(ProjectSettings.globalize_path("res://../../../build/interaction.df3dfix")),"replacement fixture loads")
 w.set_fixed_render_tick(10)
 w.poll()
 w.set_top_z(1)
 w.set_window_depth(1)
 await settle(w)
 check(signature(w,true)==signature(w,false),"session replacement cancels partial batches and stale identities")
 check(w.presentation_perf_stats().building_duplicate_builds==0,
  "semantic and layout changes coalesce to one building build per poll")
 print("MESH_BATCH_TEST failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
