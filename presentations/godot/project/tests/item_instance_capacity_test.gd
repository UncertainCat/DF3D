extends SceneTree
const Capacity = preload("res://scripts/item_instance_capacity.gd")
const Uploads = preload("res://scripts/instance_upload_cache.gd")

func populate(mm: MultiMesh, cache: RefCounted, count: int, allocated: bool, changed: PackedInt32Array) -> void:
	var layer = cache.begin(mm)
	# This is the item path's sparse-delta contract: allocation invalidates even
	# unchanged source ordinals, because Godot replaced the entire GPU buffer.
	for ordinal in (count if allocated else changed.size()):
		var i: int = ordinal if allocated else changed[ordinal]
		var position := Vector3(i + 1, 2, 3)
		layer.write(mm, i, Transform3D(Basis.IDENTITY, position), Color(1, 2, 3, 4))

func _initialize() -> void:
	var cache := Uploads.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	var allocated := Capacity.set_count(mm, 5, cache)
	assert(allocated and mm.instance_count == 8 and Capacity.visible_count(mm) == 5)
	populate(mm, cache, 5, allocated, [])
	assert(cache.counters.transforms_written == 5)
	var invalidations: int = cache.counters.cache_invalidations
	# Shrink, grow, hide, and return keep resident payloads. A reappearing group
	# may check all source ordinals, but only genuinely new ones cause writes.
	for count in [4, 5, 0, 5]:
		assert(not Capacity.set_count(mm, count, cache))
		assert(Capacity.visible_count(mm) == count and mm.instance_count == 8)
		populate(mm, cache, count, false, PackedInt32Array(range(count)))
	assert(cache.counters.transforms_written == 5)
	assert(cache.counters.cache_invalidations == invalidations)
	allocated = Capacity.set_count(mm, 8, cache)
	assert(not allocated)
	populate(mm, cache, 8, allocated, [5, 6, 7])
	assert(cache.counters.transforms_written == 8)
	# Crossing reserve must restore all nine transforms, not just new ordinal8.
	allocated = Capacity.set_count(mm, 9, cache)
	assert(allocated and mm.instance_count == 16 and Capacity.visible_count(mm) == 9)
	populate(mm, cache, 9, allocated, [8])
	assert(cache.counters.transforms_written == 17)
	assert(cache.counters.custom_written == 17)
	for i in 9:
		assert(cache.begin(mm).transforms[i].origin == Vector3(i + 1, 2, 3))
	assert(Capacity.set_count(mm, 9, cache) == false)
	# Hiding/reusing an allocation preserves its exact resident output.
	Capacity.set_count(mm, 0, cache)
	Capacity.set_count(mm, 9, cache)
	populate(mm, cache, 9, false, PackedInt32Array(range(9)))
	assert(cache.counters.transforms_written == 17)
	var layer = cache.begin(mm)
	layer.write(mm, 0, Transform3D(Basis.IDENTITY, Vector3(99, 2, 3)))
	assert(cache.counters.transforms_written == 18)
	assert(load("res://scripts/world_view.gd") != null)
	print("ITEM_INSTANCE_CAPACITY_PASS")
	quit()
