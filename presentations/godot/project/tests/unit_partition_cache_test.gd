extends SceneTree

var keys = preload("res://scripts/instance_upload_cache.gd").new()

func batch_key(slot: int, region: Color, cell: Vector3i) -> String:
	return keys.region_key(slot, region) + ":" + str(cell)

func verify(cache, slots: PackedInt32Array, regions: PackedColorArray,
		positions: PackedVector3Array, spatial := false, xy := 16, z := 1) -> void:
	var expected: Dictionary = {}
	var markers: Array[int] = []
	for i in slots.size():
		if slots[i] < 0:
			markers.append(i)
			continue
		var cell := Vector3i.ZERO
		if spatial:
			cell = Vector3i(floori(positions[i].x / xy), floori(positions[i].y / z), floori(positions[i].z / xy))
		var key := batch_key(slots[i], regions[i], cell)
		if not expected.has(key): expected[key] = []
		expected[key].append(i)
	assert(cache.groups == expected and cache.markers == markers, "partition matches full reconstruction")

func _initialize() -> void:
	var cache = preload("res://scripts/unit_partition_cache.gd").new()
	var slots := PackedInt32Array([2, 2, -1, 3])
	var regions := PackedColorArray([Color(0, 0, 1, 1), Color(0, 0, 1, 1), Color.WHITE, Color.WHITE])
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3.ZERO, Vector3(3, 0, 0)])
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	var old_groups: Dictionary = cache.groups
	var key_count: int = cache.keys_built
	for frame in 100:
		positions[0] += Vector3(0.5, 0.1, 0)
		assert(not cache.update(slots, regions, positions, false, 16, 1, batch_key))
	assert(cache.rebuilds == 1 and cache.hits == 100 and cache.keys_built == key_count,
		"motion performs no grouping or key construction")
	assert(is_same(old_groups, cache.groups), "motion retains existing member arrays")
	# Mutating caller arrays cannot mutate the cached topology snapshot.
	slots[0] = 3
	var untouched_members: Array = cache.groups[batch_key(3, Color.WHITE, Vector3i.ZERO)]
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	assert(cache.keys_built == key_count + 1, "one artwork change constructs one key")
	assert(is_same(untouched_members, cache.groups[batch_key(3, Color.WHITE, Vector3i.ZERO)]), "incremental edits preserve group arrays")
	regions[0] = Color(0.1, 0, 0.5, 1)
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	# Same-length reorder and marker transitions must not reuse stale indices.
	slots.reverse()
	regions.reverse()
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	slots[1] = 8
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	assert(cache.update(slots, regions, positions, true, 16, 1, batch_key))
	verify(cache, slots, regions, positions, true)
	positions[3] += Vector3(0.01, 0, 0)
	assert(not cache.update(slots, regions, positions, true, 16, 1, batch_key), "motion inside a cell retains grouping")
	slots[1] = -1
	assert(cache.update(slots, regions, positions, true, 16, 1, batch_key))
	positions[1] += Vector3(100, 100, 100)
	assert(not cache.update(slots, regions, positions, true, 16, 1, batch_key), "marker motion has no spatial sprite membership")
	positions[0] = Vector3(-0.1, 2.1, -16.1)
	assert(cache.update(slots, regions, positions, true, 16, 1, batch_key))
	verify(cache, slots, regions, positions, true)
	assert(cache.update(slots, regions, positions, true, 8, 4, batch_key))
	verify(cache, slots, regions, positions, true, 8, 4)
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	var active_keys: Array = cache.groups.keys()
	slots.clear()
	regions.clear()
	positions.clear()
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	assert(cache.removed_keys == active_keys, "removal hides only previous active groups")
	slots.append(4)
	regions.append(Color.WHITE)
	positions.append(Vector3.ZERO)
	assert(cache.update(slots, regions, positions, false, 16, 1, batch_key))
	verify(cache, slots, regions, positions)
	# Changing membership in one cell must not invalidate an unrelated group,
	# including source-index shifts when an earlier actor disappears.
	cache = preload("res://scripts/unit_partition_cache.gd").new()
	slots = PackedInt32Array([1,1,2])
	regions = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE])
	positions = PackedVector3Array([Vector3.ZERO,Vector3(17,0,0),Vector3(33,0,0)])
	var ids := PackedInt64Array([10,20,30])
	cache.update(slots,regions,positions,true,16,1,batch_key,ids)
	var untouched := batch_key(2,Color.WHITE,Vector3i(2,0,0))
	positions[0].x = 18
	cache.update(slots,regions,positions,true,16,1,batch_key,ids)
	assert(not cache.changed_keys.has(untouched), "cell crossing does not invalidate unrelated members")
	key_count = cache.keys_built
	slots.remove_at(0); regions.remove_at(0); positions.remove_at(0); ids.remove_at(0)
	cache.update(slots,regions,positions,true,16,1,batch_key,ids)
	assert(not cache.changed_keys.has(untouched), "index shift preserves payload slots for unchanged actor IDs")
	assert(cache.keys_built == key_count, "membership removal reuses every surviving artwork key")
	verify(cache, slots, regions, positions, true)
	assert(not cache.update(slots,regions,positions,true,16,1,batch_key,ids) and cache.changed_keys.is_empty() and cache.removed_keys.is_empty())
	# Native changed-index deltas edit only their own memberships, including
	# swaps, marker transitions and removal/recreation of the same group.
	for step in 80:
		var index := step % slots.size()
		key_count = cache.keys_built
		slots[index] = -1 if step % 7 == 0 else 1 + step % 3
		positions[index] = Vector3((step % 5) * 17 - 20, step % 2, 0)
		cache.update(slots,regions,positions,true,16,1,batch_key,ids,PackedInt32Array([index]))
		verify(cache,slots,regions,positions,true)
		assert(cache.keys_built <= key_count + 1, "sparse native update constructs at most one key")
	# Reordering IDs refreshes source indices but retains resolved keys.
	key_count = cache.keys_built
	slots.reverse();regions.reverse();positions.reverse();ids.reverse()
	cache.update(slots,regions,positions,true,16,1,batch_key,ids)
	verify(cache,slots,regions,positions,true)
	assert(cache.keys_built == key_count, "source reordering retains resolved keys")
	print("UNIT_PARTITION_CACHE_PASS")
	quit()
