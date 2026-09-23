extends SceneTree
# This is a GPU-residency integration test: it reads MultiMesh storage back from
# the renderer. Run with a real renderer (a tiny window is sufficient), not
# --headless, whose dummy storage does not retain instance transforms/custom data.
const Preparation = preload("res://scripts/item_preparation.gd")
const Storage = preload("res://scripts/item_instance_storage.gd")
class World:
	extends RefCounted
	var calls := 0
	var roof := 3.0
	var terrain := 1
	var right_revision := 1
	var _ceilings: Dictionary = {}
	func get_top_z() -> int: return 5
	func get_window_depth() -> int: return 5
	func session_generation() -> int: return 1
	func terrain_revision() -> int: return terrain
	func sprite_ceiling_source_revision(bounds: AABB, _floor_z: int) -> int:
		return right_revision if bounds.position.x > 16 else int(roof)
	func sprite_ceiling(_bounds: AABB, _floor_z: int) -> float:
		# Source adapters now own clipping locality; the payload kernel has no
		# independent cache that could hide a native/source revision.
		var end := _bounds.end
		var key := [_bounds.position.floor(), end.ceil(), _floor_z, roof]
		if not _ceilings.has(key):
			calls += 1
			_ceilings[key] = roof
		return roof
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ITEM_PREPARATION_REQUIRES_RENDERER: omit --headless; use --resolution 64x64 --render-thread safe")
		quit(2)
		return
	var prep = Preparation.new()
	var storage = Storage.new()
	var world = World.new()
	var cache = preload("res://scripts/instance_upload_cache.gd").new()
	var counters: Dictionary = cache.counters
	var deps := [1, 1, 5]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	var pos := PackedVector3Array()
	var sizes := PackedVector2Array()
	var thickness := PackedFloat32Array()
	var colors := PackedColorArray()
	var ground := PackedByteArray()
	var indices := PackedInt32Array()
	for i in 9:
		pos.append(Vector3(1.5, 1.1, 1.5));sizes.append(Vector2.ONE)
		thickness.append(0.12);colors.append(Color.WHITE);ground.append(0);indices.append(i)
	var record := {"key": 1, "slot": 1, "region": Color(0.1, 0.2, 0.3, 0.4), "revision": 1, "base_revision": -1, "indices": indices.slice(0, 5), "changed_indices": PackedInt32Array()}
	var patch = prep.prepare(record, pos, sizes, thickness, colors, ground, mm.mesh.get_aabb(), "a", deps, world, counters)
	check(world.calls == 1, "shared discrete ceiling coverage queried once")
	check(storage.apply(mm, patch, counters) and mm.instance_count == 8, "first resident allocation")
	check(counters.transforms_written == 5 and counters.custom_written == 5, "complete initial payload")
	check(prep.prepare(record, pos, sizes, thickness, colors, ground, mm.mesh.get_aabb(), "a", deps, world, counters) == null, "unchanged group skipped")
	record.base_revision = 1;record.revision = 2;record.changed_indices = PackedInt32Array([0])
	thickness[0] = 0.06
	patch = prep.prepare(record, pos, sizes, thickness, colors, ground, mm.mesh.get_aabb(), "a", deps, world, counters)
	check(patch.transforms == PackedInt32Array([0]) and patch.custom.is_empty() and world.calls == 1, "thickness-only change reuses ceiling and emits one transform")
	check(not storage.apply(mm, patch, counters), "sparse patch preserves allocation")
	var floor_bounds: AABB = patch.group.bounds
	# The retained envelope must cover every stack height within this floor.
	for height in [1.001, 1.5, 1.999]:
		var envelope: AABB = patch.group.envelope(Vector3(1.5,height,1.5),Vector2.ONE)
		check(floor_bounds.encloses(envelope), "culling bounds enclose the whole vertical tile")
	record.base_revision=2;record.revision=3;record.indices=indices;record.changed_indices=PackedInt32Array([5,6,7,8])
	patch = prep.prepare(record, pos, sizes, thickness, colors, ground, mm.mesh.get_aabb(), "a", deps, world, counters)
	check(storage.apply(mm, patch, counters) and mm.instance_count == 16, "growth replays full retained payload")
	for i in 9: check(mm.get_instance_transform(i) == patch.group.transforms[i] and mm.get_instance_custom_data(i) == patch.group.custom[i], "growth restores unchanged live slots")
	# Prepare but do not apply one revision. Later patch must recover its predecessor.
	record.base_revision=3;record.revision=4;record.changed_indices=PackedInt32Array([1]);pos[1].x=8
	prep.prepare(record, pos, sizes, thickness, colors, ground, mm.mesh.get_aabb(), "a", deps, world, counters)
	record.base_revision=4;record.revision=5;record.changed_indices=PackedInt32Array([2]);pos[2].x=9
	patch=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,patch,counters)
	check(mm.get_instance_transform(1).origin.x == 8 and mm.get_instance_transform(2).origin.x == 9, "missed preparation patch recovers full state")
	record.base_revision=2;record.revision=6;record.changed_indices=PackedInt32Array([2]);pos[3].x=10
	patch=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,patch,counters)
	check(mm.get_instance_transform(3).origin.x == 10, "mismatched native baseline scans complete group")
	world.roof=4;world.terrain+=1
	check(prep.refresh_clipping(world,true), "terrain change with identical source/dependencies wakes local clipping")
	patch=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,patch,counters)
	check(mm.get_instance_custom_data(0).r == 4, "local source token refreshes clipping without source or global context changes")
	deps[0]=0
	patch=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,patch,counters)
	check(mm.get_instance_custom_data(0).r == float(record.region.r) and mm.custom_aabb.has_point(mm.get_instance_transform(0).origin), "style-only update changes payload convention and retains conservative bounds")
	# Applying an earlier patch after the retained owner advances must replay the
	# current payload, even if the earlier patch's base still matches storage.
	record.base_revision=6;record.revision=7;record.changed_indices=PackedInt32Array([8]);pos[8].x=30
	var delayed=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	record.base_revision=7;record.revision=8;record.changed_indices=PackedInt32Array([1]);pos[1].x=31
	patch=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,delayed,counters)
	check(mm.get_instance_transform(8).origin.x == 30 and mm.get_instance_transform(1).origin.x == 31, "delayed patch replays advanced owner")
	storage.apply(mm,patch,counters)
	record.base_revision=8;record.revision=9;record.indices=indices.slice(0,2);record.changed_indices=PackedInt32Array()
	prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,delayed,counters)
	check(mm.visible_instance_count == 2 and mm.get_instance_transform(1).origin.x == 31, "stale ordinals cannot write past a later shrink")
	prep.remove(1);storage.hide(mm)
	record.revision=1;record.base_revision=-1;record.indices=indices.slice(0,1);pos[0].x=20
	patch=prep.prepare(record,pos,sizes,thickness,colors,ground,mm.mesh.get_aabb(),"a",deps,world,counters)
	storage.apply(mm,patch,counters)
	check(mm.visible_instance_count == 1 and mm.get_instance_transform(0).origin.x == 20, "recreated logical owner reusing GPU allocation cannot alias old revisions")
	prep.begin(7,deps)
	check(not prep.needs_update(7,deps,true), "idle scheduler")
	deps[0]=1
	check(prep.needs_update(7,deps,true), "scheduler observes presentation-only change")
	# Source-only terrain wakeups inspect local occupancy tokens. A changing
	# right-hand region must not invalidate the left group's retained payload.
	var local_prep = Preparation.new()
	var left = Preparation.Group.new()
	left.transforms.append(Transform3D());left.bounds=AABB(Vector3.ZERO,Vector3(2,2,2));left.context=[1,0,1,5]
	left.clip_source_revision=world.sprite_ceiling_source_revision(left.bounds,0)
	var right = Preparation.Group.new()
	right.transforms.append(Transform3D());right.bounds=AABB(Vector3(32,0,0),Vector3(2,2,2));right.context=[1,0,1,5]
	right.clip_source_revision=world.sprite_ceiling_source_revision(right.bounds,0)
	local_prep.groups={1:left,2:right}
	check(not local_prep.refresh_clipping(world,true), "prepared local baselines stay valid")
	world.terrain+=1;world.right_revision+=1
	check(local_prep.refresh_clipping(world,true), "local source change wakes scheduler")
	check(not left.context.is_empty() and right.context.is_empty(), "only affected group preparation invalidates")
	check(local_prep.needs_update(-1,[],true), "local clipping wake cannot be hidden by unchanged source revision")
	check(local_prep.refresh_clipping(world,true), "pending clipping work retains its manifest wake without another terrain change")
	left.clip_source_revision=-1;world.terrain+=1
	check(local_prep.refresh_clipping(world,true) and left.context.is_empty(), "missing baseline cannot conceal terrain change")
	print("ITEM_PREPARATION_PASS" if failures == 0 else "ITEM_PREPARATION_FAIL")
	quit(0 if failures == 0 else 1)
