extends SceneTree
# Exercise the real main-scene wiring and lazy product registry, offline.
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	OS.set_environment("DF3D_FIXTURE", ProjectSettings.globalize_path("res://../../../fixtures/synthetic/demo_fort.df3dfix"))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene._ui != null, "main scene composes UI")
	var ui = scene._ui
	check(ui.controllers.is_empty(), "startup constructs no dormant panels")
	check(ui.controller("retired") == null, "unknown factory is unavailable")
	var readout = ui.controller("readouts")
	check(readout == ui.controller("readouts"), "accepted controller is reused")
	ui.open_destination("Residents")
	check(ui.host.active == readout and readout.panel.visible, "resident route activates its view")
	check(scene._interaction.construction_active, "readout owns map input")
	ui.open_destination("Build / construction")
	var construction = ui.controller("construction")
	check(ui.host.active == construction and not readout.panel.visible, "opening editor replaces readout")
	ui.open_destination("Stockpiles / zones")
	check(ui.host.active == ui.controller("areas") and not construction.panel.visible, "area route replaces editor")
	ui.actions.session_changed.emit()
	check(ui.host.active == null and not scene._interaction.construction_active, "session change releases local view")
	ui.host.set_play_enabled(false)
	ui.open_destination("Residents")
	check(ui.host.active == null, "disabled play refuses routes")
	check(ui.controllers.size() == 3, "inspector remains lazy")
	print("ui_composition_test: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
