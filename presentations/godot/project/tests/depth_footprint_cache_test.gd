extends SceneTree
# Requires the licensed install for source-alpha footprints; exports no art.
var failures: Array[String] = []
func check(value: bool, message: String):
	if not value: failures.append(message)
func _initialize(): call_deferred("run")

func settle(world):
	for frame in 12000:
		world.poll()
		if world.pending_block_count() == 0 and world.building_pending_count() == 0 and world.composite_pending_count() == 0 and world.item_composite_pending_count() == 0:
			world.poll()
			return
		await process_frame
	check(false, "world settles")

func geometry(world) -> Dictionary:
	var out := {"units": world.unit_cutout_positions(), "unit_thickness": world.unit_thicknesses(), "items": [], "buildings": {}}
	# Dense slot compaction is independent of stable piece identity. Compare the
	# exact multiset, retaining both quantity layers, rather than incidental slots.
	var ids = world.item_ids()
	var positions = world.item_physical_layout().positions
	var thicknesses = world.item_physical_layout().thicknesses
	for i in ids.size(): out.items.append([ids[i],positions[i],thicknesses[i]])
	out.items.sort_custom(func(a,b): return a[0]<b[0] if a[0]!=b[0] else a[1].y<b[1].y)
	for node in world.get_building_root().find_children("*", "MeshInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		if node.get_meta("df3d_render_batch", false): continue # Compare semantic geometry, independent of submission grouping.
		var surfaces: Array = []
		for index in node.mesh.get_surface_count(): surfaces.append(node.mesh.surface_get_arrays(index))
		out.buildings[str(node.name)] = [node.transform, surfaces, node.get_meta("df3d_draw_fragments", [])]
	return out

func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "licensed source assets load")
	world.set_fixed_render_tick(preload("res://tests/recorded_fixture.gd").tick())
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")), "mature fixture loads")
	world.poll()
	world.set_top_z(preload("res://tests/recorded_fixture.gd").top_z())
	world.set_window_depth(24)
	await settle(world)
	var cached := geometry(world)
	# Furniture's filter surface extends into transparent image pixels, but
	# ray selection must retain the opaque silhouette, including north spills.
	var padding_checks := 0
	var opaque_hits := 0
	for node in world.get_building_root().find_children("*", "MeshInstance3D", true, false):
		if node.get_meta("df3d_building_kind", "") != "Statue": continue
		var id := str(node.name).trim_prefix("building_").to_int()
		var slots: PackedInt32Array = node.mesh.get_meta("df3d_pick_slots", PackedInt32Array())
		var surfaces: Array = node.mesh.get_meta("df3d_batch_arrays", [])
		for surface in surfaces.size():
			if slots[surface] < 0: continue
			var image: Image = world.sprite_texture(slots[surface]).get_image()
			var arrays: Array = surfaces[surface]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var a := indices[i]; var b := indices[i+1]; var c := indices[i+2]
				if (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).y >= -0.00001: continue
				for weights in [Vector3(.7,.2,.1), Vector3(.2,.7,.1), Vector3(.2,.1,.7), Vector3(.34,.33,.33)]:
					var uv: Vector2 = uvs[a]*weights.x+uvs[b]*weights.y+uvs[c]*weights.z
					var point: Vector3 = vertices[a]*weights.x+vertices[b]*weights.y+vertices[c]*weights.z
					var alpha := image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1)).a
					var hit: Dictionary = world.pick_building(point+Vector3.UP*2,Vector3.DOWN,world.get_top_z())
					if alpha == 0:
						var clear_pixel := image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1))
						check(clear_pixel.r==0 and clear_pixel.g==0 and clear_pixel.b==0, "uploaded furniture clears hidden RGB before filtering")
						padding_checks += 1
						check(hit.get("id",-1) != id, "transparent furniture padding is not selectable")
					elif alpha >= .5 and hit.get("id",-1) == id: opaque_hits += 1
	check(padding_checks > 0 and opaque_hits > 0, "recorded statues exercise transparent padding and opaque picking")
	check(world.layout_matches_reference(), "independent layout oracle matches original mature scene depth exactly")
	check(cached.buildings.size() > 100 and cached.items.size() > 100, "comparison contains substantial real fortress geometry")
	world.clear_layout_cache()
	await settle(world)
	check(geometry(world) == cached, "cached and uncached mature geometry/depth are exactly equal")
	world.clear_layout_cache()
	await settle(world)
	var before: Dictionary = world.presentation_perf_stats()
	# View depth changes retain semantic layout and source footprints.
	world.set_window_depth(25)
	await settle(world)
	world.set_window_depth(24)
	await settle(world)
	var after: Dictionary = world.presentation_perf_stats()
	check(after.footprint_cache_misses == before.footprint_cache_misses, "window changes do not resolve unchanged source footprints")
	check(after.stack_atlas_revision == before.stack_atlas_revision, "window changes retain physical layout storage")
	check(geometry(world) == cached, "returning slice restores exactly the same cached geometry")
	before = after
	world.set_reveal_hidden(true)
	await settle(world)
	world.set_reveal_hidden(false)
	await settle(world)
	after = world.presentation_perf_stats()
	check(after.footprint_cache_resets > before.footprint_cache_resets and after.footprint_cache_misses > before.footprint_cache_misses, "reveal reset rebuilds footprint cache")
	check(geometry(world) == cached, "visibility toggles do not leave cached hidden geometry")
	before = after
	world.set_fixed_render_tick(10)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/interaction.df3dfix")), "replacement fixture loads")
	world.poll()
	world.set_top_z(1)
	world.set_window_depth(1)
	await settle(world)
	after = world.presentation_perf_stats()
	check(after.footprint_cache_resets > before.footprint_cache_resets, "session replacement clears reused building IDs")
	var replaced := geometry(world)
	world.clear_layout_cache()
	await settle(world)
	check(geometry(world) == replaced, "replacement IDs match fresh uncached source resolution")
	world.free()
	for failure in failures: push_error(failure)
	print("DEPTH_FOOTPRINT_CACHE_TEST_PASS" if failures.is_empty() else "DEPTH_FOOTPRINT_CACHE_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
