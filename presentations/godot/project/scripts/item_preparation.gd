extends RefCounted
# Logical item presentation state. This owns resolved payloads, not GPU resources.
# A patch is relative to this group's preparation version, independently of the
# native source revision. Storage can replay all retained payloads after growth.
class Group:
	extends RefCounted
	var key := 0
	var source_revision := -1
	var version := 0
	var context: Array = []
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	var colors := PackedColorArray()
	var bounds := AABB()
	# Keep source-query coverage independent of the shader-clipped render bounds:
	# removing a roof must still invalidate clipping and expand visibility again.
	var render_bounds := AABB()
	var clip_floor_z := 0
	var clip_source_revision := -1
	var radii: Dictionary = {}
	var layer_key := ""
	var marker := false
	var mesh_bounds := AABB()

	func envelope(position: Vector3, size: Vector2) -> AABB:
		if not radii.has(size):
			var extent := mesh_bounds.position.abs().max(mesh_bounds.end.abs())
			radii[size] = Vector3(extent.x * size.x, extent.y * 0.045 / 0.12, extent.z * size.y).length() + size.y * 0.5
		var radius: float = radii[size]
		return AABB(position - Vector3.ONE * radius, Vector3.ONE * radius * 2.0 + Vector3(0,.9,0))

class Patch:
	extends RefCounted
	var group: Group
	var base_version := 0
	var target_version := 0
	var transforms := PackedInt32Array()
	var custom := PackedInt32Array()
	var colors := PackedInt32Array()
	var force := false

var groups: Dictionary = {}
var source_revision := -1
var delta_revision := -1
var context: Array = []
var hits := 0
var misses := 0
var sparse_checks := 0
var full_checks := 0
var _kernel = ItemPayloadKernel.new()
var _clip_scope: Array = []
var _clipping_dirty := false

func refresh_clipping(world, oriented: bool) -> bool:
	if not oriented:
		_clip_scope.clear()
		_clipping_dirty = false
		return false
	var scope := [world.terrain_revision(), world.session_generation(), world.get_top_z(), world.get_window_depth()]
	if scope == _clip_scope: return _clipping_dirty
	_clip_scope = scope
	var changed := false
	for group: Group in groups.values():
		if group.marker or group.transforms.is_empty(): continue
		var revision: int = world.sprite_ceiling_source_revision(group.bounds, group.clip_floor_z)
		if revision != group.clip_source_revision:
			# Missing evidence is stale evidence. Newly prepared groups establish
			# their baseline after the kernel resolves their retained bounds.
			group.context.clear()
			group.clip_source_revision = revision
			changed = true
	_clipping_dirty = _clipping_dirty or changed
	return _clipping_dirty

func needs_update(revision: int, dependencies: Array, enabled: bool) -> bool:
	return _clipping_dirty or not enabled or revision != source_revision or dependencies != context

func begin(revision: int, dependencies: Array) -> bool:
	var changed := dependencies != context
	source_revision = revision
	context = dependencies.duplicate()
	_clipping_dirty = false
	return changed

func remove(key: int) -> Group:
	var group: Group = groups.get(key)
	groups.erase(key)
	return group


func prepare(record: Dictionary, positions: PackedVector3Array, sizes: PackedVector2Array,
		thicknesses: PackedFloat32Array, source_colors: PackedColorArray, ground: PackedByteArray,
		mesh_bounds: AABB, layer_key: String, dependencies: Array, world,
		counters: Dictionary, enabled := true, probe = null, stack_ordinals := PackedFloat32Array()) -> Patch:
	var group: Group = groups.get(record.key)
	if group != null and enabled and group.source_revision == record.revision and group.context == dependencies:
		hits += 1
		return null
	misses += 1
	if group == null:
		group = Group.new()
		group.key = record.key
		group.marker = record.slot < 0
		group.layer_key = layer_key
		group.mesh_bounds = mesh_bounds
		groups[record.key] = group
	var patch := Patch.new()
	patch.group = group
	patch.base_version = group.version
	patch.force = not enabled
	var list: PackedInt32Array = record.indices
	var sparse: bool = enabled and group.source_revision >= 0 and group.source_revision == record.base_revision and group.context == dependencies
	var changes: PackedInt32Array = record.changed_indices
	if sparse: sparse_checks += changes.size()
	else: full_checks += list.size()
	var probing: bool = probe != null and probe.enabled
	if probing: probe.group_selection(record, group.source_revision, false, sparse)
	var result: Dictionary = _kernel.prepare(group, record,
		{"positions":positions,"sizes":sizes,"thicknesses":thicknesses,"colors":source_colors,"ground":ground,"stack_ordinals":stack_ordinals},
		dependencies, world, sparse, patch.force, counters)
	patch.transforms = result.transforms
	patch.custom = result.custom
	patch.colors = result.colors
	group.source_revision = record.revision
	group.context = dependencies.duplicate()
	if not group.marker and int(dependencies[0]) != 0:
		group.clip_source_revision = world.sprite_ceiling_source_revision(group.bounds, group.clip_floor_z)
	else:
		group.clip_source_revision = -1
	group.version += 1
	patch.target_version = group.version
	if probing: probe.prepared(patch)
	return patch
