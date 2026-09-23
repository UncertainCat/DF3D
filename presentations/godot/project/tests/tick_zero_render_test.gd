extends SceneTree
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error(reason)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Df3dWorld.new()
	root.add_child(world)
	world.set_fixed_render_tick(0)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/interaction.df3dfix")), "fixture loaded")
	world.set_window_depth(1)
	world.poll()
	check(world.unit_count() > 0, "first render at zero draws current units")
	world.set_top_z(0)
	world.poll()
	check(world.unit_count() == 1, "slice invalidation re-evaluates at unchanged zero")
	world.set_slice_units(false)
	world.poll()
	check(world.unit_count() > 1, "slice flag invalidation re-evaluates at unchanged zero")
	check(not world.poll(), "unchanged zero does not rebuild forever")
	world.free()
	print("TICK_ZERO_RENDER failures=", failures)
	quit(1 if failures else 0)
