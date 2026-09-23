extends Node3D
# Original UNIT_STATUS variants. Semantic bit positions are defined in wm/types.h.
# Native fortress primary precedence plus movement fallback, traced at RVA269340.
const ART = {0:8, 1:39, 2:27, 3:30, 4:9, 5:11, 6:10, 7:13, 8:12,
	9:18, 10:17, 11:19, 12:22, 13:34, 14:35, 15:36, 16:36,
	17:0,18:1,19:2,20:3,21:4,22:5,23:6,24:7,25:14,26:15,27:16,
	28:20,29:21,30:22,31:23,32:24,33:25,34:26,35:28,36:29,37:31,
	38:32,39:33,40:37,41:38,42:40}
const PRIORITY = [0,38,3,34,39,13,14,15,16,31,35,2,36,33,32,37,21,20,22,23,24,
	29,28,25,27,26,18,19,4,5,6,7,8,11,10,9,12,30,17]
const FALLBACK = [40,1,41,42]
var records := {}
var batches := {}
var dirty := {}
var generation := -1
var scope: Array = []
var uploads := 0
var world
var motion
var capture_phase := -1.0

static func primary_variant(flags: int) -> int:
	for bit in PRIORITY:
		if flags & (1 << bit): return ART[bit]
	return -1

static func fallback_variant(flags: int) -> int:
	for bit in FALLBACK:
		if flags & (1 << bit): return ART[bit]
	return -1

static func variant(flags: int) -> int:
	var primary := primary_variant(flags)
	return primary if primary >= 0 else fallback_variant(flags)

func _dirty_record(record: Dictionary) -> void:
	for layer in record.get("layers",[]): dirty[layer[0]] = true

func set_capture_phase(value: float) -> void:
	# Test/capture control only; runtime uses a shared wall clock in the shader.
	capture_phase = value
	for node in batches.values(): node.material_override.set_shader_parameter("capture_phase",value)

func refresh_stack_materials() -> void:
	for node in batches.values(): world.configure_stack_material(node.material_override)

func begin(epoch: int, view_scope: Array, ids: PackedInt64Array) -> void:
	if epoch != generation or scope != view_scope:
		for record in records.values(): _dirty_record(record)
		records.clear()
		generation = epoch
		scope = view_scope.duplicate()
	var live := {}
	for id in ids: live[id] = true
	for id in records.keys():
		if not live.has(id):
			_dirty_record(records[id])
			records.erase(id)

func observe(id: int, flags: int, address: int, first: Vector3, last: Vector3,
		size: Vector2, scale: Color, billboard: bool) -> void:
	var art := variant(flags)
	var old: Dictionary = records.get(id, {})
	if art < 0:
		if not old.is_empty(): _dirty_record(old); records.erase(id)
		return
	var primary := primary_variant(flags)
	var fallback := fallback_variant(flags)
	var layers: Array = [[primary,1]] if primary >= 0 else []
	if fallback >= 0: layers.append([fallback,2 if primary >= 0 else 0])
	# Endpoints only affect conservative culling. Movement itself uses the shared GPU pool.
	var next := {"art":art, "address":address, "first":first, "last":last,
		"height":size.y, "scale":scale.r, "padding":scale.g, "billboard":billboard,
		"layers":layers,"phase":((id*34536)&0xffffffff)%7000}
	if old == next: return
	if not old.is_empty(): _dirty_record(old)
	records[id] = next
	_dirty_record(next)

func flush() -> void:
	for art in dirty:
		var members: Array = []
		for record in records.values():
			for layer in record.layers:
				if layer[0] == art: members.append([record,layer[1]])
		if members.is_empty():
			if batches.has(art): batches[art].visible = false
			continue
		if not batches.has(art):
			var texture: Texture2D = world.ui_texture("UNIT_STATUS", art)
			if texture == null: continue
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://shaders/unit_status.gdshader")
			mat.set_shader_parameter("status_texture", texture)
			mat.set_shader_parameter("capture_phase", capture_phase)
			motion.bind_material(mat)
			world.configure_stack_material(mat)
			var node := MultiMeshInstance3D.new()
			node.name = "Status" + str(art)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.material_override = mat
			var mesh := QuadMesh.new()
			mesh.size = Vector2.ONE
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			node.multimesh = mm
			add_child(node)
			batches[art] = node
		var node: MultiMeshInstance3D = batches[art]
		var mm := node.multimesh
		mm.instance_count = members.size()
		var bounds := AABB()
		for i in members.size():
			var r: Dictionary = members[i][0]
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(r.height, r.padding, float(r.billboard))))
			mm.set_instance_custom_data(i, Color(r.address, r.scale, members[i][1], r.phase))
			var box := AABB(r.first,Vector3.ZERO).expand(r.last).grow(maxf(2.0,r.height*maxf(1.0,r.scale)+1.0))
			bounds = box if i == 0 else bounds.merge(box)
		mm.custom_aabb = bounds
		node.visible = true
		uploads += 1
	dirty.clear()
