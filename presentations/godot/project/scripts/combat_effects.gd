extends Node3D
# Native four-frame sheets, resident geometry, bounded transient instances.
# Keys and coordinates are read from installed definitions, not invented art.
const MAX_EFFECTS := 32
const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
var effects: Dictionary = {}
var materials: Dictionary = {}
var counters := {"spawned": 0, "dropped": 0}
var enabled := true
var _pool: Array[MeshInstance3D] = []
var _until: Array[float] = []
var _style := false

func configure(install: String):
	var folder := install.path_join("data/vanilla/vanilla_interface/graphics")
	var definitions := folder.path_join("graphics_combat_animations.txt")
	if not FileAccess.file_exists(definitions): return
	var pages: Dictionary = {}
	var page := ""
	for line in FileAccess.get_file_as_string(folder.path_join("tile_page_interface.txt")).split("\n"):
		line = line.strip_edges()
		if line.begins_with("[TILE_PAGE:"): page = line.trim_prefix("[TILE_PAGE:").trim_suffix("]")
		elif page.begins_with("COMBAT_ANIMATIONS_") and line.begins_with("[FILE:"):
			var relative := line.trim_prefix("[FILE:").trim_suffix("]")
			if relative.begins_with("images/") and not relative.contains(".."):
				pages[page] = folder.path_join(relative)
	for line in FileAccess.get_file_as_string(definitions).split("\n"):
		line = line.strip_edges()
		if not line.begins_with("[TILE_GRAPHICS:"): continue
		var fields := line.trim_prefix("[").trim_suffix("]").split(":")
		if fields.size() != 8 or fields[7] != "1" or not pages.has(fields[1]): continue
		var key := fields[4] + ":" + fields[5] + ":" + fields[6]
		effects[key] = {"page": fields[1], "row": int(fields[3])}
	for token in pages:
		var source := Image.load_from_file(pages[token])
		if source == null or source.is_empty(): continue
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/combat_effect.gdshader")
		# Sprite geometry is lifted in shaders, so node-origin transparent sorting
		# is not a reliable ordering between a character and its hit overlay.
		# Draw effects after sprite transparency, while retaining the depth test.
		material.render_priority = 10
		source.generate_mipmaps()
		material.set_shader_parameter("atlas", ImageTexture.create_from_image(source))
		material.set_shader_parameter("atlas_tiles", Vector2(source.get_width(), source.get_height()) / 32.0)
		materials[token] = material
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 1.2
	for i in MAX_EFFECTS:
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.custom_aabb = AABB(Vector3.ONE * -0.9, Vector3.ONE * 1.8)
		piece.visible = false
		add_child(piece)
		_pool.append(piece)
		_until.append(0.0)

static func direction(delta: Vector3) -> String:
	return DIRECTIONS[posmod(roundi(atan2(delta.z, delta.x) / (PI / 4)), 8)]

func set_style(upright: bool):
	if upright == _style: return
	_style = upright
	for material in materials.values():
		material.set_shader_parameter("upright", upright)

func emit_effect(outcome: String, position: Vector3, from_attacker: Vector3, clock: float, sparks := false, target_height := 0.0) -> bool:
	# The atlas directions describe the ground plane, including upright style.
	from_attacker.y = 0.0
	if not from_attacker.is_finite(): return false
	if not enabled or outcome not in ["HIT", "MISS", "BLOCK", "PARRY"] or from_attacker.length_squared() < 0.000001: return false
	var family := "COMBAT_ANIMATION_SPARKS" if sparks else "COMBAT_ANIMATION_SWISH"
	# Native labels identify the side of the target occupied by the attacker.
	var bearing := -from_attacker
	var key := family + ":" + outcome + ":" + direction(bearing)
	if not effects.has(key) or not materials.has(effects[key].page): return false
	for i in _pool.size():
		if _until[i] > clock: continue
		var piece := _pool[i]
		piece.material_override = materials[effects[key].page]
		piece.position = position
		# Include every camera orientation and the target's possible center lift.
		var radius := 0.95 + maxf(0.0, target_height) * 0.5
		piece.custom_aabb = AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
		# Native combat groups start with W and proceed clockwise through eight
		# directions. The shader resolves the projected direction as cameras move.
		piece.set_instance_shader_parameter("atlas_row", float(effects[family + ":" + outcome + ":W"].row))
		piece.set_instance_shader_parameter("world_direction", Vector2(bearing.x, bearing.z))
		piece.set_instance_shader_parameter("target_height", float(maxf(0.0, target_height)))
		piece.set_instance_shader_parameter("start_time", clock)
		piece.set_instance_shader_parameter("duration", 0.28)
		_until[i] = clock + 0.28
		piece.visible = true
		counters.spawned += 1
		return true
	counters.dropped += 1
	return false

func advance(clock: float):
	for i in _pool.size():
		if _pool[i].visible and (not enabled or clock >= _until[i]): _pool[i].visible = false

func reset_session():
	_until.fill(0.0)
	for piece in _pool: piece.visible = false
