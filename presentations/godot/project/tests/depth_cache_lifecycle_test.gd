extends SceneTree
# Asset-free real replay -> BuildingEvents -> warmed presentation cache. Arrival
# gaps are 10 s; select their midpoints with the deterministic replay clock.
# Exact tick assertions make an unexpectedly delayed test fail, never skip a case.
var failures: Array[String] = []
func check(value: bool, message: String):
	if not value: failures.append(message)
func _initialize(): call_deferred("run")

func advance(world, index: int):
	world.set_replay_speed(0)
	world.set_replay_elapsed(10.0 * index + 5.0)
	world.poll()
	check(world.bridge_tick() == 100 + index, "replay reaches exact lifecycle frame %d" % index)

func height(world) -> float:
	check(world.item_physical_layout().positions.size() == 1, "one test item remains visible")
	return world.item_physical_layout().positions[0].y if world.item_physical_layout().positions.size() == 1 else -1.0

func compare_uncached(world):
	var expected: PackedVector3Array = world.item_physical_layout().positions
	var thickness: PackedFloat32Array = world.item_physical_layout().thicknesses
	world.clear_layout_cache()
	world.poll()
	check(world.item_physical_layout().positions == expected and world.item_physical_layout().thicknesses == thickness, "warm-cache result equals fresh uncached allocation")
	world.clear_layout_cache()
	world.poll()

func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	world.set_replay_speed(0)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/depth-cache.df3dfix")), "lifecycle fixture loads")
	world.poll()
	world.set_top_z(1)
	world.set_window_depth(1)
	world.poll()
	var floor_height := height(world)
	compare_uncached(world)
	# Start with adequate wall-time precision while the replay remains frozen.
	await create_timer(0.1).timeout
	var stats: Dictionary = world.presentation_perf_stats()
	advance(world, 1)
	check(world.presentation_perf_stats().footprint_cache_evictions > stats.footprint_cache_evictions, "Changed evicts warm previous building version")
	check(height(world) > floor_height, "expanded footprint supplies actual item support")
	compare_uncached(world)
	stats = world.presentation_perf_stats()
	advance(world, 2)
	check(world.presentation_perf_stats().footprint_cache_evictions > stats.footprint_cache_evictions, "Removed evicts warm footprint")
	check(is_equal_approx(height(world), floor_height), "removed furniture stops supporting item")
	compare_uncached(world)
	advance(world, 3)
	check(height(world) > floor_height, "readded identity supplies fresh expanded support")
	compare_uncached(world)
	stats = world.presentation_perf_stats()
	advance(world, 5)
	check(world.presentation_perf_stats().footprint_cache_evictions > stats.footprint_cache_evictions, "coalesced remove/readd evicts even when version restarts at same value")
	check(is_equal_approx(height(world), floor_height), "same-version replacement cannot retain stale wide footprint")
	compare_uncached(world)
	world.free()
	for failure in failures: push_error(failure)
	print("DEPTH_CACHE_LIFECYCLE_TEST_PASS" if failures.is_empty() else "DEPTH_CACHE_LIFECYCLE_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
