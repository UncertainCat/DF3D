extends Node3D
# Original installed DESIGNATIONS cells, keyed by semantic v7 DesignationKind.
# Native reference: build/native-references/08-mining-accepted-row.png.
const ORDER_ART = ["", "DESIGNATION_DIG_STANDARD", "DESIGNATION_DIG_CHANNEL",
	"DESIGNATION_DIG_STAIR_UP", "DESIGNATION_DIG_STAIR_DOWN", "DESIGNATION_DIG_STAIR_UPDOWN",
	"DESIGNATION_DIG_RAMP", "DESIGNATION_DIG_REMOVE_CONSTRUCTION", "DESIGNATION_CHOP",
	"DESIGNATION_GATHER", "DESIGNATION_SMOOTH", "DESIGNATION_ENGRAVE", "DESIGNATION_FORTIFY", ""]
var world
var layer_priority := 10
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _last_markers: Array = []
var _last_level := -1
var _last_priorities := false
var _last_traffic := false
var _last_warnings := false
var _grid: MeshInstance3D
var _grid_key: Array = []

func update_grid(map_size: Vector3, level: int, enabled: bool) -> void:
	if _grid != null: _grid.visible = enabled
	if not enabled: return
	var key := [map_size, level]
	if key == _grid_key: return
	var material := material_for("VIEWPORT_GRID")
	if material == null: return
	if _grid == null:
		_grid = MeshInstance3D.new()
		_grid.name = "ViewportGrid"
		_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_grid)
	# One repeated source cell per map tile, one quad for the selected level.
	# This is a DF-camera overlay, not thousands of per-tile scene nodes.
	material.texture_repeat = true
	material.render_priority = 5
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for uv in [Vector2(0,0), Vector2(map_size.x,0), Vector2(map_size.x,map_size.z), Vector2(0,0), Vector2(map_size.x,map_size.z), Vector2(0,map_size.z)]:
		mesh.surface_set_uv(uv)
		mesh.surface_add_vertex(Vector3(uv.x, level + 1.01, uv.y))
	mesh.surface_end()
	_grid.mesh = mesh
	_grid.visible = true
	_grid_key = key

func material_for(selector: String) -> StandardMaterial3D:
	if selector.is_empty() or world == null or not world.has_method("ui_texture"): return null
	if _materials.has(selector): return _materials[selector]
	var marker_only := selector.ends_with(":marker")
	var automine := selector.ends_with(":auto")
	var source := selector.trim_suffix(":marker").trim_suffix(":auto")
	var is_priority := source.begins_with("DESIGNATION_PRIORITY_")
	var texture: Texture2D = world.ui_texture("DESIGNATION_PRIORITY", int(source.trim_prefix("DESIGNATION_PRIORITY_")) - 1) if is_priority else world.ui_texture(source)
	if texture == null: return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	if marker_only: material.albedo_color = Color(0,0.5,1,1)
	elif automine: material.albedo_color = Color(0,1,0,1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = layer_priority + (2 if source.ends_with("_STONE_WARNING") else 1 if is_priority else -1 if source.begins_with("DESIGNATION_TRAFFIC_") else 0)
	_materials[selector] = material
	return material

static func selector(operation: int) -> String:
	return ORDER_ART[operation] if operation >= 0 and operation < ORDER_ART.size() else ""

static func track_selector(mask: int) -> String:
	var directions := ""
	for entry in [[1,"N"],[2,"S"],[8,"W"],[4,"E"]]:
		if mask & entry[0]: directions += entry[1]
	return "DESIGNATION_TRACK_" + directions if not directions.is_empty() else ""

func update_markers(markers: Array, level: int, show_priorities := false, show_traffic := false, show_warnings := false) -> void:
	if markers == _last_markers and level == _last_level and show_priorities == _last_priorities and show_traffic == _last_traffic and show_warnings == _last_warnings: return
	_last_priorities = show_priorities
	_last_traffic = show_traffic
	_last_warnings = show_warnings
	_last_markers = markers.duplicate(true)
	_last_level = level
	var groups := {}
	for marker in markers:
		if marker.tile.z != level: continue
		var names: Array[String] = []
		var track := track_selector(int(marker.get("track",0)))
		var order := selector(int(marker.get("operation",0)))
		if not track.is_empty(): names.append(track)
		elif not order.is_empty(): names.append(order)
		if bool(marker.get("marker",false)):
			for i in names.size(): names[i] += ":marker"
		elif bool(marker.get("auto",false)):
			for i in names.size(): names[i] += ":auto"
		var priority := int(marker.get("priority",0))
		if show_priorities and not names.is_empty() and priority >= 1 and priority <= 7:
			names.append("DESIGNATION_PRIORITY_%d" % priority)
		var warnings := int(marker.get("warnings",0))
		if show_warnings and warnings & 1: names.append("DAMP_STONE_WARNING")
		if show_warnings and warnings & 2: names.append("WARM_STONE_WARNING")
		var traffic := int(marker.get("traffic",0))
		if show_traffic and traffic >= 1 and traffic <= 3:
			names.append(["","DESIGNATION_TRAFFIC_LOW","DESIGNATION_TRAFFIC_HIGH","DESIGNATION_TRAFFIC_RESTRICTED"][traffic])
		for name in names:
			if not groups.has(name): groups[name] = []
			groups[name].append(marker)
	_render_groups(groups)

static func cursor_selector(rect: Rect2i, tile: Vector2i) -> String:
	if not rect.has_point(tile): return ""
	var edges := PackedStringArray()
	if tile.y == rect.position.y: edges.append("N")
	if tile.y == rect.end.y - 1: edges.append("S")
	if tile.x == rect.position.x: edges.append("W")
	if tile.x == rect.end.x - 1: edges.append("E")
	return "RECTANGLE_CURSOR_" + ("_".join(edges) if not edges.is_empty() else "INTERIOR")

func update_cursor(rect: Rect2i, level: int) -> void:
	var groups := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var name := cursor_selector(rect, Vector2i(x,y))
			if not groups.has(name): groups[name] = []
			var tile := Vector3i(x,y,level)
			groups[name].append({"tile": tile, "height": maxf(0.0,world.selection_height(tile))})
	_render_groups(groups)

func update_track_cursor(route: Array, level: int) -> void:
	var groups := {}
	for tile in route:
		if tile.tile.z != level: continue
		var name := track_selector(int(tile.track))
		if name.is_empty(): continue
		if not groups.has(name): groups[name] = []
		groups[name].append(tile)
	_render_groups(groups)

func _render_groups(groups: Dictionary) -> void:
	for name in _batches: _batches[name].visible = groups.has(name)
	for name in groups:
		var material := material_for(name)
		if material == null: continue
		if not _batches.has(name):
			var node := MeshInstance3D.new()
			node.name = name
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_batches[name] = node
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		for marker in groups[name]:
			var tile: Vector3i = marker.tile
			var height := tile.z + float(marker.get("height", 1.0)) + 0.015
			for uv in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				mesh.surface_set_uv(uv)
				mesh.surface_add_vertex(Vector3(tile.x + uv.x, height, tile.y + uv.y))
		mesh.surface_end()
		_batches[name].mesh = mesh
		_batches[name].visible = true
