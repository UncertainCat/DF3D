extends SceneTree
const Preferences = preload("res://scripts/presentation_settings.gd")
const HUD = preload("res://scripts/fortress_hud.gd")
const InfoFrame = preload("res://scripts/native_info_frame.gd")
const HUDTest = preload("res://tests/fortress_hud_test.gd")
var failures: Array[String] = []

class World extends RefCounted:
	var assets
	func is_live(): return true
	func get_top_z(): return 143
	func ui_texture(selector: String, variant := -1): return assets.ui_texture(selector, variant)
	func ui_font_path(): return assets.ui_font_path()

func check(value: bool, reason: String):
	if not value: failures.append(reason); push_error(reason)

func _initialize(): call_deferred("run")

func run():
	root.size = Vector2i(1920, 1080)
	var path := ProjectSettings.globalize_path("res://../../../build/hud-scale-regression.cfg")
	OS.set_environment("DF3D_UI_SETTINGS_PATH", path)
	Preferences.loaded = true
	Preferences.ui_scale = 1.0
	Preferences.camera_mode = ""
	Preferences.targeting_grid = true
	Preferences.visual_style = "classic"
	var assets := Df3dWorld.new()
	root.add_child(assets)
	check(assets.load_assets(OS.get_environment("DF3D_DF_PATH")), "installed native interface assets load")
	var world := World.new()
	world.assets = assets
	var interaction := HUDTest.Interaction.new()
	root.add_child(interaction)
	interaction.panel.hide()
	interaction.tool_picker.hide()
	interaction.priority.hide()
	var rig = load("res://scripts/orbit_camera.gd").new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	var hud := HUD.new()
	hud.world = world
	hud.interaction = interaction
	hud.camera_rig = rig
	var host=load("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host);hud.ui_host=host
	root.add_child(hud)
	var style_events: Array = []
	hud.visual_style_changed.connect(func(value): style_events.append(value))
	check(hud.style_picker.selected == 0, "Cutouts defaults on")
	hud.style_picker.select(1)
	hud.style_picker.item_selected.emit(1)
	check(Preferences.visual_style == "billboard" and style_events == ["billboard"], "settings toggle updates graphics preference and emits once")
	var state := {"fortress_valid": true, "fort_name": "Chantmansion", "year":104, "year_tick":225600, "paused":true,
		"fortress_summary":{"available":true,"population":177,"stress_available":true,"stress_counts":[8,8,21,38,27,18,57],"elevation_offset":-129,"level_count":256,"resources_available":true,"resource_counts":[852,135,310,206,14,453,247]}}
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	root.add_child(canvas)
	var panel := PanelContainer.new()
	canvas.add_child(panel)
	panel.add_child(VBoxContainer.new())
	var frame := InfoFrame.new()
	frame.install(panel, world, "Residents")
	var destinations: Array = []
	frame.destination_requested.connect(func(destination): destinations.append(destination))
	panel.hide()
	check(hud.information.get_child_count() == 8, "all eight native Info slots retained")
	for index in HUD.INFO_SLOTS.size():
		var expected: String = HUD.INFO_SLOTS[index][0]
		check(hud.information.get_child(index) == hud.navigation[expected], "native Info order: " + expected)
	check(not hud.navigation.has("Production / farms"), "retired production menu remains absent")
	if hud.navigation.has("Trade"):
		check(hud.navigation["Trade"].get_parent() != hud.alerts, "DF3D utilities do not consume native alert rail")
	check(hud.navigation["Reports"].get_parent() == hud.root_control and hud.navigation["Petitions"].get_parent() == hud.root_control, "native report and petition controls have independent anchors")
	for value in [100, 125, 150]:
		hud.set_ui_scale_percent(value)
		hud.update_state(true, true, state)
		await process_frame
		await process_frame
		hud.update_state(true, true, state)
		await process_frame
		check(hud.scale_picker.value == value, "scale control reflects the saved requested value")
		check(root.size == Vector2i(1920,1080), "UI scale never resizes 3D viewport")
		check(hud.scale == Vector2.ONE * float(value) / 100.0, "HUD canvas transform scales geometry")
		check(not hud.navigation["Tasks"].disabled and not hud.navigation["Objects"].disabled, "unfinished destinations remain reachable after state refresh")
		var button: Button = hud.navigation["Citizens"]
		var physical_width: float = button.size.x * button.get_global_transform_with_canvas().get_scale().x
		check(physical_width >= 32.0 * value / 100.0, "native icon hit target scales with art")
		var capture := OS.get_environment("DF3D_HUD_CAPTURE")
		if not capture.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s-%d.png" % [capture,value])
		if value == 125 and not capture.is_empty():
			hud.toggle_settings()
			hud.update_state(true, true, state)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture + "-menu.png")
			hud.toggle_settings()
		panel.show()
		frame.layout(Vector2(root.size))
		await process_frame
		await process_frame
		frame.layout(Vector2(root.size))
		await process_frame
		check(canvas.scale == hud.scale, "Info frame shares HUD scale")
		var visible_rect: Rect2 = Rect2(panel.position * canvas.scale, panel.size * canvas.scale)
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(visible_rect), "scaled Info frame stays inside viewport")
		var tab: Button = frame.buttons["Labor"]
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = tab.get_global_transform_with_canvas() * (tab.size * 0.5)
		click.pressed = true
		root.push_input(click)
		click = click.duplicate()
		click.pressed = false
		root.push_input(click)
		check(destinations.size() == (value - 100) / 25 + 1 and destinations.back() == "Work Details", "physical mouse hit reaches scaled native tab")
		panel.hide()
	Preferences.ui_scale = 2.0
	check(is_equal_approx(Preferences.effective_scale(Vector2(960,640)), 4.0/3.0), "small windows fit controls without losing requested scale")
	Preferences.targeting_grid = false
	Preferences.camera_mode = "df"
	Preferences.move_speed = 35.0
	check(Preferences.save_preferences(path) == OK, "presentation preferences saved")
	Preferences.ui_scale = 1.0
	Preferences.targeting_grid = true
	Preferences.camera_mode = "free"
	Preferences.move_speed = 20.0
	Preferences.visual_style = "classic"
	Preferences.load_preferences(path)
	check(Preferences.ui_scale == 2.0 and not Preferences.targeting_grid and Preferences.camera_mode == "df" and Preferences.move_speed == 35.0, "scale/grid/camera preferences survive reload")
	check(Preferences.visual_style == "billboard", "Billboard preference survives reload")
	DirAccess.remove_absolute(path)
	canvas.free()
	hud.free()
	interaction.free()
	rig.free()
	assets.free()
	print("HUD_SCALE_PASS" if failures.is_empty() else "HUD_SCALE_FAIL")
	quit(0 if failures.is_empty() else 1)
