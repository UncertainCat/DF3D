extends SceneTree
const Orientation = preload("res://tests/door_orientation.gd")
class Fallback:
	extends RefCounted
	var world
	func _init(value): world = value
	func tile_hover_info(tile): return world.tile_hover_info(tile)
var failures: Array[String] = []
var started: int
func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)
func _initialize(): call_deferred("run")
func advance(world, index: int):
	var elapsed = float(Time.get_ticks_usec() - started) / 1000000.0
	world.set_replay_speed((10.0 * index + 5.0) / elapsed)
	world.poll()
	world.set_replay_speed(0)
	check(world.bridge_tick() == 100 + index, "exact replay frame " + str(index) + " got " + str(world.bridge_tick()))
func run():
	var world = Df3dWorld.new()
	root.add_child(world)
	world.set_replay_speed(0)
	var fixture = ProjectSettings.globalize_path("res://../../../build/render-cache.df3dfix")
	check(world.load_fixture(fixture), "fixture loads")
	started = Time.get_ticks_usec()
	world.poll()
	world.set_top_z(2)
	world.set_window_depth(3)
	world.poll()
	var fallback = Fallback.new(world)
	var revision = world.door_orientation_revision()
	var tile = Vector3i(1, 2, 2)
	world.door_orientation(tile)
	await create_timer(0.5).timeout
	for frame in range(1, 14):
		advance(world, frame)
		# Direct query BEFORE revision check cannot erase older evidence.
		var actual = world.door_orientation(tile)
		check(actual == Orientation.resolve(fallback, tile), "fallback parity frame " + str(frame))
		var current = world.door_orientation_revision()
		var changed = frame in [2, 5, 6, 10, 11, 12, 13]
		check((current > revision) == changed, "only queried classification changes invalidate frame " + str(frame))
		revision = current
	for setting in ["slice", "window", "reveal"]:
		if setting == "slice": world.set_top_z(1)
		elif setting == "window": world.set_window_depth(2)
		else: world.set_reveal_hidden(true)
		check(world.door_orientation_revision() > revision, setting + " resets scope")
		revision = world.door_orientation_revision()
	check(world.load_fixture(fixture), "fixture reloads")
	world.poll()
	check(world.door_orientation_revision() > revision, "reload preserves monotonic revision")
	world.free()
	print("DOOR_ORIENTATION_REVISION_PASS" if failures.is_empty() else "DOOR_ORIENTATION_REVISION_FAIL")
	quit(0 if failures.is_empty() else 1)
