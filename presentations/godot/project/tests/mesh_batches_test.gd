extends SceneTree
const SourceMesh = preload("res://tests/source_mesh.gd")
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
func packed_color(color: Color,cpu: bool) -> int:
 if not cpu:return color.to_rgba32()
 # Mesh upload truncates each clamped float channel to UNorm8 (e.g. .45 -> 114).
 return (int(clampf(color.r,0,1)*255)<<24)|(int(clampf(color.g,0,1)*255)<<16)|(int(clampf(color.b,0,1)*255)<<8)|int(clampf(color.a,0,1)*255)
func signature(world, sources: bool) -> Dictionary:
 var out={}
 for holder in [world.get_terrain_root(),world.get_building_root()]:
  for node in holder.find_children("*", "MeshInstance3D", true, false):
   if not node is MeshInstance3D or node.mesh==null or not node.is_visible_in_tree(): continue
   if sources and node.get_meta("df3d_render_batch",false): continue
   if not sources and node.layers==0: continue
   for surface in SourceMesh.count(node.mesh):
    var mat=null if SourceMesh.retired(node.mesh) else node.get_surface_override_material(surface)
    if mat==null: mat=SourceMesh.material(node.mesh,surface)
    var key=mat.get_meta("df3d_batch_original_material",mat.get_instance_id())
    var a=SourceMesh.arrays(node.mesh,surface)
    var layers=a[Mesh.ARRAY_CUSTOM0]
    var provenance=mat.get_meta("df3d_batch_source_materials",PackedInt64Array())
    var v=a[Mesh.ARRAY_VERTEX]
    var n=a[Mesh.ARRAY_NORMAL]
    var c=a[Mesh.ARRAY_COLOR]
    var uv=a[Mesh.ARRAY_TEX_UV]
    var uv2=a[Mesh.ARRAY_TEX_UV2]
    var centers=a[Mesh.ARRAY_CUSTOM2]
    var ix=a[Mesh.ARRAY_INDEX]
    for j in (ix.size() if ix!=null and not ix.is_empty() else v.size()):
     var i=ix[j] if ix!=null and not ix.is_empty() else j
     if not sources and node.has_meta("df3d_terrain_slab"):
      var part=int(a[Mesh.ARRAY_CUSTOM1][i])
      var z=part/3
      var alternative=part%3
      var top=world.get_top_z()
      if z>top or z<=top-world.get_window_depth() or (alternative==1 and z>=top) or (alternative==2 and z!=top):continue
     if layers!=null and not provenance.is_empty(): key=provenance[int(layers[i])]
     if not out.has(key): out[key]=[0,0]
     var center=Vector4(centers[i*4],centers[i*4+1],centers[i*4+2],centers[i*4+3]) if centers!=null else Vector4.ZERO
     var h=hash([v[i],n[i].snapped(Vector3.ONE*0.001) if n!=null else null,packed_color(c[i],SourceMesh.retired(node.mesh)) if c!=null else null,uv[i] if uv!=null else null,uv2[i] if uv2!=null else null,center])
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
 var terrain_uploads=w.presentation_perf_stats()
 check(terrain_uploads.terrain_surface_uploads<terrain_uploads.terrain_surface_inputs,"terrain consolidates compatible textures before GPU allocation")
 print("MESH_BATCH_STATS ",JSON.stringify(stats))
 check(stats.terrain.batches>0 and stats.buildings.batches>0,"terrain and buildings are batched")
 check(stats.terrain.retired_source_meshes==stats.terrain.sources and stats.terrain.source_surfaces==0,"published terrain batches release duplicate source GPU surfaces")
 check(stats.terrain.max_surfaces_per_mesh<=RenderingServer.MAX_MESH_SURFACES and stats.buildings.max_surfaces_per_mesh<=RenderingServer.MAX_MESH_SURFACES,"published mesh chunks respect engine surface capacity")
 # Compare retained CPU sources at Godot's upload precision: packed RGBA8
 # colors and normal quantization at 0.001. Positions, UVs, counts and material
 # IDs stay exact, including each texture-array layer's source material.
 check(signature(w,true)==signature(w,false),"merged vertex attributes/materials preserved within normal packing precision")
 w.set_mesh_batching_enabled(false)
 check(signature(w,true)==signature(w,false),"disable immediately restores source rendering")
 w.set_mesh_batching_enabled(true)
 await settle(w)
 check(signature(w,true)==signature(w,false),"reenable preserves geometry")
 var slab_before=w.mesh_batch_stats().terrain
 var original_top=w.get_top_z()
 for top in [0,1,14,15,16,17,30,31,32,33,original_top]:
  w.set_top_z(top)
  check(signature(w,true)==signature(w,false),"vertical slab clipping matches source parents at level %s" % top)
  for node in w.get_terrain_root().get_children():
   if node.get_meta("df3d_terrain_cut_batch",false) and node.is_visible():
    check(node.get_meta("df3d_terrain_slab")==w.get_top_z()/16,"only the selected slab submits cut-cap batches")
 check(w.mesh_batch_stats().terrain.builds==slab_before.builds and w.mesh_batch_stats().terrain.invalidations==slab_before.invalidations,"crossing slab boundaries preserves resident meshes")
 var buildings_before=w.mesh_batch_stats().buildings
 var building_builds_before=w.presentation_perf_stats().building_geometry_builds
 var terrain_before=w.mesh_batch_stats().terrain
 var builds_before=w.presentation_perf_stats().terrain_geometry_builds
 w.set_top_z(preload("res://tests/recorded_fixture.gd").top_z()-1)
 w.poll()
 check(signature(w,true)==signature(w,false),"slice visibility preserves batched geometry immediately")
 await settle(w)
 check(w.mesh_batch_stats().buildings.deferred_sources==0,"paused polls rejoin all stable deferred sources")
 check(signature(w,true)==signature(w,false),"retained cut alternatives preserve geometry")
 w.set_top_z(preload("res://tests/recorded_fixture.gd").top_z())
 w.set_window_depth(1)
 await settle(w)
 check(signature(w,true)==signature(w,false),"window shrink removes stale batch geometry")
 check(w.presentation_perf_stats().building_geometry_builds==building_builds_before,"slice travel retains building geometry")
 check(w.mesh_batch_stats().buildings.builds==buildings_before.builds and w.mesh_batch_stats().buildings.invalidations==buildings_before.invalidations,"slice travel retains building batches")
 check(w.presentation_perf_stats().terrain_geometry_builds==builds_before,"slice travel does not rebuild resident terrain")
 check(w.mesh_batch_stats().terrain.builds==terrain_before.builds and w.mesh_batch_stats().terrain.invalidations==terrain_before.invalidations,"slice travel retains published terrain batches")
 w.set_zone_overlays_visible(true)
 check(signature(w,true)==signature(w,false),"zone overlays remain independent")
 w.set_zone_overlays_visible(false)
 # Start incremental rebatching, then replace the entire source epoch.
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
