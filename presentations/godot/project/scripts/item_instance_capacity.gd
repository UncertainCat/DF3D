extends RefCounted
# Item groups own resident allocations. Membership changes only expose a prefix;
# shrinking/hiding must not discard GPU data or the matching CPU upload cache.
# Capacity is retained for the lifetime of the scene-owned layer.
static func visible_count(mm: MultiMesh) -> int:
	return mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count

# Returns true only when Godot discarded the old instance buffer. The caller
# must then visit every live instance, even if the source supplies a sparse delta.
static func set_count(mm: MultiMesh, count: int, uploads: RefCounted = null) -> bool:
	assert(count >= 0)
	var allocated := count > mm.instance_count
	if allocated:
		var capacity := maxi(8, mm.instance_count)
		while capacity < count: capacity *= 2
		mm.instance_count = capacity
		if uploads != null: uploads.invalidate(mm)
	if mm.visible_instance_count != count: mm.visible_instance_count = count
	return allocated
