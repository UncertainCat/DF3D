extends SceneTree
# Exercise the real main-scene wiring and lazy product registry, offline.
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1200,800)
	OS.set_environment("DF3D_FIXTURE", ProjectSettings.globalize_path("res://../../../fixtures/synthetic/demo_fort.df3dfix"))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	check(scene._ui != null, "main scene composes UI")
	var ui = scene._ui
	check(not ui.has_node("TileHover"), "Unsourced tile descriptions stay outside the product")
	for child in ui.get_children():
		check(child.get_script()!=preload("res://scripts/tile_hover.gd"), "No unnamed tile hover bypasses availability")
	# This test owns navigation/session transitions explicitly; asynchronous
	# fixture polling must not reset the panels during deferred HUD layout.
	ui.actions.set_process(false)
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
	var hud = scene._fortress_hud
	hud.update_state(true,true,{})
	check(hud.active_launcher == "Build / construction" and not hud.navigation["Build / construction"].disabled,"route ownership enables its own launcher toggle")
	check(hud.navigation.Dig.disabled and hud.navigation.Citizens.disabled,"other launchers cannot steal modal placement")
	check(hud.navigation["Build / construction"].icon == hud.ui.texture("BUTTON_LOWER_MENU"),"active Build uses native lower-menu arrow")
	hud.navigation["Build / construction"].pressed.emit()
	check(ui.host.active == null and not construction.panel.visible,"own launcher closes placement and releases map input")
	hud.update_state(true,true,{})
	hud.navigation["Build / construction"].pressed.emit()
	check(ui.host.active == construction and construction.panel.visible,"launcher routes back to the same construction controller")
	hud.toggle_settings(); hud.navigation["Build / construction"].pressed.emit()
	check(ui.host.active == construction and construction.panel.visible,"HUD overlay prevents toggle dispatch behind it")
	hud.close_menus()
	ui.open_destination("Stockpiles / zones")
	check(ui.host.active == ui.controller("areas") and not construction.panel.visible, "area route replaces editor")
	var areas = ui.controller("areas")
	check(areas.focus_requested.is_connected(ui.focus_tile),"area selector recenter reaches shared camera navigation")
	hud.update_state(true,true,{})
	check(hud.active_launcher == "Stockpiles" and not hud.navigation.Stockpiles.disabled,"stockpile owns its launcher toggle")
	check(hud.navigation.Stockpiles.icon == hud.ui.texture("BUTTON_LOWER_MENU"),"active stockpile uses native lower-menu arrow")
	hud.navigation.Stockpiles.pressed.emit()
	check(ui.host.active == null and not areas.panel.visible,"stockpile launcher closes its own mode")
	ui.open_destination("Zones")
	check(areas.kind_picker.selected == 1 and areas.launcher_destination == "Zones" and areas.panel.visible,"Zone route reuses area controller with zone kind")
	hud.update_state(true,true,{})
	hud.navigation.Zones.pressed.emit()
	check(ui.host.active == null and not areas.panel.visible and not scene._interaction.construction_active,"zone launcher closes its own mode and releases map input")
	for destination in ["Stockpiles","Zones"]:
		ui.open_destination(destination)
		areas._detach_draft(); areas.new_area()
		var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
		root.push_input(escape)
		check(ui.host.active == null and not areas.panel.visible and not scene._interaction.construction_active,"top-level Escape closes %s and releases map input" % destination)
	ui.open_destination("Stockpiles")
	check(areas.kind_picker.selected == 0 and areas.mode == "paint" and areas.panel.visible,"Stockpile route switches out of zone mode")
	hud.update_state(true,true,{})
	hud.navigation.Stockpiles.show()
	await process_frame
	hud.update_state(true,true,{})
	hud.navigation.Stockpiles.show()
	hud.layout(hud.logical_view_size()); areas._process(0)
	var anchor: Rect2 = hud.launcher_rect("Stockpiles")
	check(anchor.has_area() and is_equal_approx(areas.paint_view.tools.position.x,anchor.position.x),"paint tools use actual HUD launcher anchor: %s / %s visible=%s" % [anchor,areas.paint_view.tools.position,areas.paint_view.tools.visible])
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
