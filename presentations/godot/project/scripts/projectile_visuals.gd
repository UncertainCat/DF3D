extends MultiMeshInstance3D
## Small shared ammunition mesh. Positions are observed/interpolated by the model.
## This renderer never invents trajectories, impacts or projectile lifetimes.
var _ids := PackedInt64Array()
var _positions := PackedVector3Array()
var _directions := PackedVector3Array()
var _scope := Vector2i(-1, -1)
var transform_writes := 0

func _init():
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _bolt_mesh()
	extra_cull_margin = .4
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _bolt_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := CylinderMesh.new()
	shaft.top_radius = .014
	shaft.bottom_radius = .014
	shaft.height = .28
	shaft.radial_segments = 6
	shaft.rings = 0
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = .035
	head.height = .09
	head.radial_segments = 4
	head.rings = 0
	var along_z := Basis(Vector3.RIGHT, PI / 2.0)
	surface.append_from(shaft, 0, Transform3D(along_z, Vector3.ZERO))
	surface.append_from(head, 0, Transform3D(along_z, Vector3(0, 0, .175)))
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.85, .79, .58)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, material)
	return mesh

static func pose(position: Vector3, direction: Vector3) -> Transform3D:
	var forward := direction.normalized() if direction.length_squared() > .000001 else Vector3.FORWARD
	var up := Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > .99 else Vector3.UP
	return Transform3D(Basis.looking_at(forward, up, true), position)

func update(world):
	var ids: PackedInt64Array = world.projectile_ids()
	var positions: PackedVector3Array = world.projectile_positions()
	var directions: PackedVector3Array = world.projectile_directions()
	var scope := Vector2i(world.get_top_z(), world.get_window_depth())
	if ids == _ids and positions == _positions and directions == _directions and scope == _scope: return
	_ids = ids.duplicate()
	_positions = positions.duplicate()
	_directions = directions.duplicate()
	_scope = scope
	var visible_indices: Array[int] = []
	for i in ids.size():
		if positions[i].y >= scope.x + 1.0 or positions[i].y < scope.x - scope.y + 1.0: continue
		visible_indices.append(i)
	if multimesh.instance_count != visible_indices.size(): multimesh.instance_count = visible_indices.size()
	for k in visible_indices.size():
		var i: int = visible_indices[k]
		multimesh.set_instance_transform(k, pose(positions[i], directions[i]))
		transform_writes += 1
