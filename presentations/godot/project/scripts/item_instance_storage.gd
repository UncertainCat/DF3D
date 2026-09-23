extends RefCounted
# Physical residency only. No source/layout/cache decisions occur here.
const Capacity = preload("res://scripts/item_instance_capacity.gd")
var _resident: Dictionary = {}
var _kernel = ItemPayloadKernel.new()

func apply(mm: MultiMesh, patch, counters: Dictionary) -> bool:
	var group = patch.group
	var allocated := Capacity.set_count(mm, group.transforms.size())
	var id := mm.get_instance_id()
	var resident: Dictionary = _resident.get(id, {})
	# A patch references the retained owner, which may have advanced since it was
	# prepared. Its old ordinal list cannot describe that newer payload.
	var full: bool = allocated or patch.force or patch.target_version != group.version or resident.get("owner") != group or resident.get("version", -1) != patch.base_version
	_kernel.write(mm, group, patch, full, counters)
	if mm.custom_aabb != group.bounds: mm.custom_aabb = group.bounds
	_resident[id] = {"owner": group, "version": group.version}
	return allocated

func hide(mm: MultiMesh) -> void:
	if mm.visible_instance_count != 0: mm.visible_instance_count = 0

func forget(mm: MultiMesh) -> void:
	_resident.erase(mm.get_instance_id())
