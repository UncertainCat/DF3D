# Resident flat cutouts and camera-facing sprites. Camera motion changes only shaders.
extends Node
const Geometry = preload("res://scripts/sprite_geometry.gd")
var billboard := false
var _main: Node3D
var _camera: Camera3D
var geometry = Geometry.new()
var _materials: Dictionary = {}

func sprites_oriented() -> bool:
	return billboard

func configure(main: Node3D) -> void:
	_main = main
	_camera = main.get_node("CameraRig/Camera3D") as Camera3D
	_camera.set_meta("sprite_presentation", self)
	geometry.configure(main.get_node("Df3dWorld"))
	get_tree().node_added.connect(_node_added)

func set_style(style: String) -> void:
	if style not in ["classic", "billboard"]: return
	var next := style == "billboard"
	if next == billboard: return
	_restore_materials()
	billboard = next
	if billboard: _visit(_main)
	_main._unit_revision_seen = -1

func piece_transform(size: Vector2, thickness: float, position: Vector3) -> Transform3D:
	return Geometry.billboard_transform(_camera, size, thickness, position)

func piece_ceiling(mesh: Mesh, transform: Transform3D, position: Vector3) -> float:
	if billboard:
		return geometry.ceiling_for(billboard_bounds(mesh, Vector2(transform.basis.x.length(), transform.basis.z.length()), position), floori(position.y))
	return geometry.ceiling_for(transform * mesh.get_aabb(), floori(position.y))

func billboard_bounds(mesh: Mesh, size: Vector2, position: Vector3) -> AABB:
	# Envelope of every possible card orientation, including the bottom anchor.
	# Stable between camera poses, shared by ceiling queries and engine culling.
	var box := mesh.get_aabb()
	var extent := box.position.abs().max(box.end.abs())
	var radius := Vector3(extent.x * size.x, extent.y * 0.045 / 0.12, extent.z * size.y).length() + size.y * 0.5
	return AABB(position - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)

func _node_added(node: Node) -> void:
	if sprites_oriented() and node is GeometryInstance3D:
		# Callers commonly assign mesh/material immediately after add_child.
		_track_geometry.call_deferred(weakref(node))

func _track_geometry(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if sprites_oriented() and is_instance_valid(node) and _main.is_ancestor_of(node):
		_prepare_geometry(node)

func _visit(node: Node) -> void:
	if node is GeometryInstance3D: _prepare_geometry(node)
	for child in node.get_children(): _visit(child)

func _prepare_geometry(node: GeometryInstance3D) -> void:
	if not (node is MultiMeshInstance3D and node.get_parent() == _main and node.material_override is ShaderMaterial): return
	var material: ShaderMaterial = node.material_override
	if material.shader == null or not material.shader.resource_path.ends_with("unit_sprite.gdshader"): return
	_materials[material.get_instance_id()] = [weakref(material), material.shader]
	material.shader = preload("res://shaders/billboard_sprite.gdshader")
	material.set_shader_parameter("use_instance_ceiling", true)

func _restore_materials() -> void:
	for entry in _materials.values():
		var material = entry[0].get_ref()
		if is_instance_valid(material): material.shader = entry[1]
	_materials.clear()

func _exit_tree() -> void:
	_restore_materials()
	if is_instance_valid(_camera): _camera.remove_meta("sprite_presentation")
