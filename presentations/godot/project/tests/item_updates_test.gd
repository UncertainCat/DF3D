extends SceneTree
var world: Df3dWorld
var failures: Array[String] = []
var delta_revision := -1
var delta_records := {}
var prior_payloads := {}
func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)
func _initialize(): call_deferred("run")
func validate(count: int):
	var ids := world.item_ids()
	check(ids.size() == count, "expected compact payload count")
	var seen := {}
	var complete: Array = world.item_render_groups()
	var delta: Dictionary = world.item_render_group_delta(delta_revision)
	var old_records: Dictionary = delta_records.duplicate()
	if delta.full: delta_records.clear()
	for id in delta.removed: delta_records.erase(id)
	for group in delta.groups: delta_records[group.key] = group
	check(delta_records.size() == complete.size(), "delta reconstructs exact live group count")
	delta_revision = delta.revision
	check(world.item_render_group_delta(delta_revision).groups.is_empty(), "current cursor visits no groups")
	var next_payloads := {}
	for group in complete:
		check(delta_records.get(group.key) == group, "delta reconstructs exact group manifest")
		var payload: Array = []
		for index in group.indices:
			# Stack depth and ground mode are shader custom data. Neighbouring
			# membership changes can alter them without moving the CPU position.
			payload.append([ids[index], world.item_positions()[index], world.item_sprite_sizes()[index], world.item_thicknesses()[index], world.item_colors()[index], world.item_stack_ordinals()[index], world.item_ground_flags()[index]])
		if old_records.has(group.key) and group.base_revision >= 0 and group.base_revision == old_records[group.key].revision:
			var expected := PackedInt32Array()
			var old: Array = prior_payloads[group.key]
			for k in payload.size():
				if k >= old.size() or old[k] != payload[k]: expected.append(k)
			# Count changes preserve the surviving local ordinals and can be sparse.
			if group in delta.groups: check(group.changed_indices == expected, "sparse offsets match actual changed payloads")
		next_payloads[group.key] = payload
		for index in group.indices:
			check(index >= 0 and index < ids.size() and not seen.has(index), "group indices form exact compact partition")
			seen[index] = true
	prior_payloads = next_payloads
	check(seen.size() == count, "every exported quantity piece has one group")
	check(world.layout_matches_reference(), "lazy ID/quantity slots match independent whole-scene oracle")
func advance(frame: int):
	world.set_replay_elapsed(10.0 * frame + 5.0)
	world.poll()
	check(world.bridge_tick() == 100 + frame, "exact replay frame")

# Depth-cache replay: finalized depth payloads, slice removal and ID reuse.
func validate_groups(w) -> Array:
	var groups: Array = w.item_render_groups()
	var slots: PackedInt32Array = w.item_sprite_slots()
	var regions: PackedColorArray = w.item_sprite_regions()
	var seen: Dictionary = {}
	for group in groups:
		var indices: PackedInt32Array = group.indices
		check(not indices.is_empty(), "no empty groups")
		for index in indices:
			check(not seen.has(index), "indices belong to exactly one group")
			seen[index] = true
			check(slots[index] == group.slot, "group slot matches exported item")
			if group.slot >= 0: check(regions[index] == group.region, "group region matches exported item")
	check(seen.size() == w.item_positions().size(), "all exported items have a group")
	check(groups == w.item_render_groups(), "unchanged native revision returns stable manifest")
	return groups

func advance_groups(w, started: int, index: int) -> void:
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	w.set_replay_speed((10.0 * index + 5.0) / elapsed)
	w.poll()
	w.set_replay_speed(0)
	check(w.bridge_tick() == 100 + index, "exact replay frame")

func run_render_groups() -> void:
	var w := Df3dWorld.new()
	root.add_child(w)
	w.set_replay_speed(0)
	var fixture := ProjectSettings.globalize_path("res://../../../build/depth-cache.df3dfix")
	check(w.load_fixture(fixture), "fixture loads")
	var started := Time.get_ticks_usec()
	w.poll()
	w.set_top_z(1)
	w.set_window_depth(1)
	w.poll()
	var first := validate_groups(w)
	check(first.size() == 1 and first[0].slot == -1, "asset-free item marker group")
	var revision: int = first[0].revision
	var key: int = first[0].key
	var height: float = w.item_physical_layout().positions[0].y
	await create_timer(0.1).timeout
	advance_groups(w, started, 1)
	var expanded := validate_groups(w)
	check(w.item_physical_layout().positions[0].y > height, "fixture changes item support height")
	check(expanded[0].revision == revision and expanded[0].key == key, "shared support change preserves resident item group revision")
	revision = expanded[0].revision
	w.poll()
	check(validate_groups(w)[0].revision == revision, "stationary payload keeps group revision")
	# Force a native item rebuild while adding an empty lower layer. The exact
	# group payload and indices stay unchanged, including its cached record.
	var stationary: Dictionary = validate_groups(w)[0]
	w.set_window_depth(2)
	w.poll()
	var widened: Dictionary = validate_groups(w)[0]
	check(widened.revision == stationary.revision, "unchanged payload survives native rebuild")
	check(is_same(widened, stationary), "unchanged payload and indices reuse immutable record")
	w.set_window_depth(1)
	w.set_top_z(0)
	w.poll()
	check(validate_groups(w).is_empty(), "slice removes groups")
	w.set_top_z(1)
	w.poll()
	var restored := validate_groups(w)
	check(restored[0].revision > revision, "reappearing group cannot reuse an old revision")
	revision = restored[0].revision
	check(w.load_fixture(fixture), "fixture reloads")
	w.poll()
	w.set_top_z(1)
	w.poll()
	check(validate_groups(w)[0].revision > revision, "session reset cannot alias prior group revisions")
	w.free()

func run():
	await run_render_groups()
	world = Df3dWorld.new()
	root.add_child(world)
	world.set_replay_speed(0)
	var path := ProjectSettings.globalize_path("res://../../../build/item-updates.df3dfix")
	check(world.load_fixture(path), "fixture loads")
	world.poll()
	world.set_top_z(2)
	check(world.get_window_depth() == 3, "default terrain depth follows loaded map")
	check(world.get_sprite_depth() == 12, "default sprite range is twelve levels")
	world.set_window_depth(2)
	world.poll()
	validate(7)
	var initial_cursor := delta_revision
	var initial_layout := {}
	for i in world.item_ids().size():
		initial_layout[str(world.item_ids()[i])+":"+str(world.item_stack_ordinals()[i])] = world.item_positions()[i]
	# A sprite range is independent of terrain residency and follows the selected
	# level. Exercise both edges and restoration without advancing the replay.
	world.set_sprite_depth(1)
	world.poll()
	validate(1)
	check(world.item_ids()[0] == 500, "range includes selected level and excludes level below")
	check(world.get_window_depth() == 2, "sprite range preserves terrain depth")
	world.set_top_z(1)
	world.poll()
	validate(6)
	check(not 500 in world.item_ids(), "range follows selected level and excludes level above")
	world.set_top_z(2)
	world.set_sprite_depth(2)
	world.poll()
	validate(7)
	world.set_sprite_depth(0)
	world.poll()
	validate(7)
	check(world.get_sprite_depth() == 0, "zero restores terrain-inherited range")
	for i in world.item_ids().size():
		check(initial_layout.get(str(world.item_ids()[i])+":"+str(world.item_stack_ordinals()[i])) == world.item_positions()[i], "restoring range preserves item stack positions and ordinals")
	var before := world.presentation_perf_stats()
	advance(1)
	validate(7)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated + 1, "one moved owner does not rebuild other item records")
	advance(2)
	validate(6)
	check(not 100 in world.item_ids(), "removed owner is absent after swap compaction")
	advance(3)
	validate(8)
	check(world.item_render_group_delta(initial_cursor).full, "skipped delta cursor receives full recovery manifest")
	check(world.item_ids().count(100) == 2, "reused ID owns both new quantity ordinals")
	var groups: Array = world.item_render_groups()
	before = world.presentation_perf_stats()
	advance(4)
	validate(8)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated + 1, "flag-only event visits one owner")
	check(world.presentation_perf_stats().item_groups_updated == before.item_groups_updated, "unchanged rendered fields do not rebuild groups")
	check(world.item_render_groups() == groups, "flag-only update retains exact group records")
	world.set_presentation_region(Rect2i(0,0,16,16))
	world.poll()
	check(world.item_ids().size() == 2 and world.item_ids().count(200) == 2, "region scope materializes indexed candidates only")
	validate(2)
	groups = world.item_render_groups()
	before = world.presentation_perf_stats()
	advance(5)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated + 1, "offscreen event visits only its dirty owner")
	check(world.item_render_groups() == groups, "offscreen event does not change demanded group payloads")
	validate(2)
	world.set_presentation_region(Rect2i())
	world.poll()
	validate(8)
	var positions := world.item_positions()
	world.set_presentation_region(Rect2i(-256,-256,1024,1024))
	world.poll()
	before = world.presentation_perf_stats()
	world.set_presentation_region(Rect2i(-128,-128,768,768))
	world.poll()
	check(world.presentation_perf_stats().item_update_passes == before.item_update_passes, "camera margins covering the same map do not rescope items")
	check(world.presentation_perf_stats().layout_candidate_tiles == before.layout_candidate_tiles, "equivalent map demand does not rescan occupied tiles")
	var ids := world.item_ids()
	for i in ids.size():
		if ids[i] == 400: check(positions[i].x == 34.5, "reentry uses latest offscreen position")
	world.clear_layout_cache()
	world.poll()
	validate(8)
	before = world.presentation_perf_stats()
	advance(6)
	validate(8)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated,
		"unrelated glyph append does not revisit materialized item owners")
	before = world.presentation_perf_stats()
	advance(7)
	validate(8)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated,
		"liquid-only terrain event does not revisit any item owner")
	check(world.presentation_perf_stats().visibility_blocks_unchanged > before.visibility_blocks_unchanged,
		"unchanged entity visibility is detected independently of terrain version")
	before = world.presentation_perf_stats()
	advance(8)
	validate(6)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated + 1,
		"hiding a tile updates only its item owner")
	check(not 200 in world.item_ids(), "hidden tile removes both quantity pieces")
	before = world.presentation_perf_stats()
	advance(9)
	validate(8)
	check(world.presentation_perf_stats().item_records_updated == before.item_records_updated + 1,
		"revealing a tile restores only its item owner")
	check(world.load_fixture(path), "fixture reloads")
	world.poll()
	validate(7)
	world.free()
	print("ITEM_UPDATES_PASS" if failures.is_empty() else "ITEM_UPDATES_FAIL")
	quit(0 if failures.is_empty() else 1)
