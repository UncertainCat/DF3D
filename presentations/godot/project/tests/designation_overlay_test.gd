extends SceneTree
const Overlay = preload("res://scripts/designation_overlay.gd")
var failures: Array[String] = []
func check(value: bool, message: String):
	if not value: failures.append(message)
func _initialize(): call_deferred("run")
func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "licensed original assets load")
	var overlay := Overlay.new()
	overlay.world = world
	root.add_child(overlay)
	var markers := [
		{"tile": Vector3i(2,3,1), "height": 1.0, "operation": 1},
		{"tile": Vector3i(3,3,1), "height": 1.0, "operation": 1},
		{"tile": Vector3i(4,3,1), "height": 1.0, "operation": 8},
		{"tile": Vector3i(4,3,2), "height": 1.0, "operation": 1}]
	overlay.update_markers(markers, 1)
	check(overlay.get_child_count() == 2, "two selectors batch three current-level orders")
	for operation in range(1, 13):
		var name := Overlay.selector(operation)
		var material := overlay.material_for(name)
		check(material != null, "native operation selector resolves: %s" % name)
		if material == null: continue
		check(material.albedo_texture.get_size() == Vector2(32,32), "native operation retains full 32px cell")
		check(material.albedo_color == Color.WHITE and material.no_depth_test, "source sprite remains untinted and cannot z-fight")
		check(material.albedo_texture.get_image().get_data() == world.ui_texture(name).get_image().get_data(), "unmodified installed sprite pixels")
	check(overlay.material_for("DESIGNATION_DIG_STANDARD:auto").albedo_color == Color(0,1,0,1), "automining uses green source glyph")
	check(overlay.material_for("DESIGNATION_DIG_STANDARD:marker").albedo_color == Color(0,0.5,1,1), "blueprint uses blue source glyph")
	var pickaxes: MeshInstance3D = overlay.get_node("DESIGNATION_DIG_STANDARD")
	var vertices: PackedVector3Array = pickaxes.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size() == 12, "two accepted cells produce two full-tile quads")
	check(vertices[0].x == 2 and vertices[0].z == 3 and is_equal_approx(vertices[0].y, 2.015), "order sits on selected tile cap")
	check(Overlay.selector(13).is_empty() and Overlay.selector(255).is_empty(), "unknown operations never pretend to be mining")
	check(Overlay.cursor_selector(Rect2i(2,3,1,1),Vector2i(2,3)) == "RECTANGLE_CURSOR_N_S_W_E", "native singleton uses all four edges")
	var row := Rect2i(2,3,3,1)
	check(Overlay.cursor_selector(row,Vector2i(2,3)) == "RECTANGLE_CURSOR_N_S_W", "single row west cap")
	check(Overlay.cursor_selector(row,Vector2i(3,3)) == "RECTANGLE_CURSOR_N_S", "single row middle")
	check(Overlay.cursor_selector(row,Vector2i(4,3)) == "RECTANGLE_CURSOR_N_S_E", "single row east cap")
	var column := Rect2i(2,3,1,3)
	check(Overlay.cursor_selector(column,Vector2i(2,3)) == "RECTANGLE_CURSOR_N_W_E", "single column north cap")
	check(Overlay.cursor_selector(column,Vector2i(2,4)) == "RECTANGLE_CURSOR_W_E", "single column middle")
	check(Overlay.cursor_selector(column,Vector2i(2,5)) == "RECTANGLE_CURSOR_S_W_E", "single column south cap")
	var square := Rect2i(2,3,3,3)
	var expected := ["N_W","N","N_E","W","INTERIOR","E","S_W","S","S_E"]
	for y in 3:
		for x in 3:
			var name := Overlay.cursor_selector(square,Vector2i(2+x,3+y))
			check(name == "RECTANGLE_CURSOR_" + expected[y*3+x], "rectangle cursor edges match native named cells")
			check(overlay.material_for(name) != null, "native cursor selector resolves")
	check(Overlay.cursor_selector(square,Vector2i(1,3)).is_empty(), "outside cursor rectangle emits no art")
	var route := [{"tile":Vector3i(2,3,1),"track":4,"height":0.5},{"tile":Vector3i(3,3,2),"track":8,"height":0.1}]
	overlay.update_track_cursor(route,1)
	check(overlay.get_node("DESIGNATION_TRACK_E").visible and not overlay.has_node("DESIGNATION_TRACK_W"), "track preview shows current slice only")
	overlay.update_track_cursor(route,2)
	check(not overlay.get_node("DESIGNATION_TRACK_E").visible and overlay.get_node("DESIGNATION_TRACK_W").visible, "changing elevation switches route slice without losing path")
	var track_vertices: PackedVector3Array = overlay.get_node("DESIGNATION_TRACK_W").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(is_equal_approx(track_vertices[0].y,2.115), "track preview respects route tile height")
	# Numerals layer over the operation; toggling local visibility rebuilds once.
	markers[0]["priority"] = 2
	markers[1]["priority"] = 7
	overlay.update_markers(markers, 1, true)
	var number: MeshInstance3D = overlay.get_node("DESIGNATION_PRIORITY_2")
	check(number != null and number.visible, "priority atlas batch appears alongside pickaxes")
	var number_material := overlay.material_for("DESIGNATION_PRIORITY_2")
	check(number_material.albedo_texture.get_image().get_data() == world.ui_texture("DESIGNATION_PRIORITY",1).get_image().get_data(), "priority digits retain source placement and colors")
	check(number_material.render_priority > overlay.material_for("DESIGNATION_DIG_STANDARD").render_priority, "numerals composite above designation artwork")
	var retained = number.mesh
	overlay.update_markers(markers,1,true)
	check(number.mesh == retained, "unchanged priority frame retains geometry")
	overlay.update_markers(markers,1,false)
	check(not number.visible and pickaxes.visible, "hide priorities retains operation symbols")
	for value in range(1,8):
		check(overlay.material_for("DESIGNATION_PRIORITY_%d" % value) != null, "all seven native priority variants resolve")
	var marker_material := overlay.material_for("DESIGNATION_DIG_STANDARD:marker")
	check(marker_material.albedo_color == Color(0,0.5,1,1), "native marker-only sprite blue modulation")
	check(marker_material.albedo_texture == overlay.material_for("DESIGNATION_DIG_STANDARD").albedo_texture, "marker mode retains original source artwork")
	# Every direction combination has original art; traffic is a local display choice.
	for mask in range(1,16):
		check(overlay.material_for(Overlay.track_selector(mask)) != null, "track combination has native artwork")
	markers = [{"tile":Vector3i(2,3,1), "track":9, "priority":3, "traffic":2, "warnings":1}]
	overlay.update_markers(markers,1,true,false,true)
	check(overlay.get_node("DESIGNATION_TRACK_NW").visible, "track-only pending work renders without dig flags")
	check(overlay.get_node("DAMP_STONE_WARNING").visible, "warning independent of ordinary designation")
	check(not overlay.has_node("DESIGNATION_TRAFFIC_HIGH"), "traffic hidden by default")
	overlay.update_markers(markers,1,true,true,true)
	var traffic: MeshInstance3D = overlay.get_node("DESIGNATION_TRAFFIC_HIGH")
	check(traffic.visible, "explicit traffic display resolves installed art")
	retained=traffic.mesh
	overlay.update_markers(markers,1,true,true,true)
	check(traffic.mesh==retained,"unchanged map indicators retain geometry")
	overlay.update_markers(markers,1,true,false,true)
	check(not traffic.visible,"traffic toggles without altering source work")
	overlay.update_markers([], 1)
	check(not pickaxes.visible, "canceled orders disappear without retaining stale batch")
	overlay.update_grid(Vector3(192,145,192), 143, true)
	var grid: MeshInstance3D = overlay.get_node("ViewportGrid")
	var grid_arrays: Array = grid.mesh.surface_get_arrays(0)
	check(grid_arrays[Mesh.ARRAY_VERTEX].size() == 6, "map grid costs one quad regardless of map size")
	check(grid_arrays[Mesh.ARRAY_TEX_UV][2] == Vector2(192,192), "grid repeats exactly once per DF tile")
	var grid_material := grid.mesh.surface_get_material(0) as StandardMaterial3D
	check(grid_material.texture_repeat and grid_material.no_depth_test and grid_material.render_priority < 10, "grid repeats below order and cursor overlays without depth fighting")
	check(grid_material.albedo_texture.get_image().get_data() == world.ui_texture("VIEWPORT_GRID").get_image().get_data(), "grid uses unchanged installed sprite pixels")
	var grid_mesh = grid.mesh
	overlay.update_grid(Vector3(192,145,192), 143, true)
	check(grid.mesh == grid_mesh, "unchanged grid is not rebuilt every frame")
	overlay.update_grid(Vector3(192,145,192), 143, false)
	check(not grid.visible, "leaving designation mode hides grid")
	overlay.free()
	world.free()
	for failure in failures: push_error(failure)
	print("DESIGNATION_OVERLAY_TEST_PASS" if failures.is_empty() else "DESIGNATION_OVERLAY_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
