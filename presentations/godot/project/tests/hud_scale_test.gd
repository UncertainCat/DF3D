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
	Preferences.ui_auto_scale = true
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
	for startup_frame in 3: await process_frame
	check(Preferences.ui_auto_scale, "HUD startup preserves automatic scaling")
	hud.scale_picker.value_changed.emit(100.0)
	check(Preferences.ui_auto_scale, "disabled manual control cannot turn automatic scaling off")
	hud.auto_scale_toggle.button_pressed = false
	check(hud.heading.material == hud.ui.hud_material, "native text and art share the HUD reconstruction filter")
	var arriving_icon := TextureRect.new()
	hud.root_control.add_child(arriving_icon)
	check(arriving_icon.material == hud.ui.hud_material, "late notification/tool children inherit native filtering")
	arriving_icon.free()
	var font: FontFile = hud.ui.theme.default_font
	var font_image := font.get_texture_image(0,Vector2i(12,0),0)
	var clear_found := false
	for y in font_image.get_height():
		for x in font_image.get_width():
			var pixel := font_image.get_pixel(x,y)
			if pixel.a == 0:
				clear_found = true
				check(pixel.r == 0 and pixel.g == 0 and pixel.b == 0,"keyed glyph texels have native transparent-black RGB")
	check(clear_found,"installed bitmap contains transparent glyph background")
	check(not hud.texture_smoothing_toggle.button_pressed, "texture smoothing defaults off")
	hud.texture_smoothing_toggle.button_pressed = true
	check(Preferences.texture_smoothing, "texture smoothing toggle updates preference")
	check(not hud.native_world_toggle.button_pressed, "native world rendering defaults off")
	var native_events: Array = []
	hud.native_world_rendering_changed.connect(func(value): native_events.append(value))
	hud.native_world_toggle.button_pressed = true
	check(Preferences.native_world_rendering and native_events == [true], "native rendering toggle updates preference and dispatches")
	var style_events: Array = []
	hud.visual_style_changed.connect(func(value): style_events.append(value))
	check(hud.style_picker.selected == 0, "Cutouts defaults on")
	hud.style_picker.select(1)
	hud.style_picker.item_selected.emit(1)
	check(Preferences.visual_style == "billboard" and style_events == ["billboard"], "settings toggle updates graphics preference and emits once")
	var state := {"fortress_valid": true, "fort_name": "Chantmansion", "year":104, "year_tick":225600, "paused":true,
		"fortress_summary":{"available":true,"population":177,"stress_available":true,"stress_counts":[8,8,21,38,27,18,57],"elevation_offset":-129,"level_count":256,"resources_available":true,"bookkeeper_precision":0,"resource_counts":[852,135,310,206,14,453,247]}}
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
	check(hud.information.get_child_count() == 8, "eight native Info slots without DFHack adornments")
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
		check(hud.navigation["Tasks"].disabled and hud.navigation["Objects"].disabled, "unfinished destinations remain inert after state refresh")
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
	Preferences.texture_smoothing = false
	Preferences.native_world_rendering = false
	Preferences.load_preferences(path)
	check(Preferences.texture_smoothing, "texture smoothing survives reload")
	check(Preferences.native_world_rendering, "native rendering opt-in survives reload")
	check(Preferences.ui_scale == 2.0 and not Preferences.targeting_grid and Preferences.camera_mode == "df" and Preferences.move_speed == 35.0, "scale/grid/camera preferences survive reload")
	check(Preferences.visual_style == "billboard", "Billboard preference survives reload")
	check(not Preferences.ui_auto_scale, "explicit manual scale survives reload")
	var oracle = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/hud/automatic_scale.json"))
	hud.auto_scale_toggle.button_pressed = true
	for sample in oracle.cases:
		root.size=Vector2i(sample.viewport[0],sample.viewport[1])
		for frame_index in 4:
			hud.update_state(true,true,state)
			await process_frame
		var expected := Vector2(sample.cell[0]/8.0,sample.cell[1]/12.0)
		check(hud.scale.is_equal_approx(expected), "automatic scale matches native whole-pixel cells")
		check((hud.status_panel.position*hud.scale).is_equal_approx(Vector2(sample.header_origin[0],0)), "header preserves native horizontal centering and stays flush at top at %s (got %s)" % [root.size,hud.status_panel.position*hud.scale])
		check(hud.minimap_panel.position.y==0 and hud.playback.position.y==0 and hud.map_tools.position.y==24, "top controls stay flush independent of text-grid remainder")
		if root.size == Vector2i(1920,1080):
			# DF53.16 protected capture native-20261013-114704/w1920h1080.png.
			check(hud.actions.position * hud.scale == Vector2(700,1035), "native four-group toolbar anchor")
			check(hud.actions.size * hud.scale == Vector2(530,45), "native four-group toolbar footprint")
			check(hud.information.position * hud.scale == Vector2(0,1035), "native information rail anchor")
			check(hud.map_tools.position * hud.scale == Vector2(1630,30), "native map control anchor")
		check(hud.minimap_layer.scale==hud.scale, "automatic minimap and HUD share scale")
		frame.layout(Vector2(root.size))
		check(canvas.scale==hud.scale, "automatic Info panel uses both native cell axes")
		check(not hud.scale_picker.editable, "automatic scale makes manual percentage inactive")
		var capture := OS.get_environment("DF3D_HUD_CAPTURE")
		if not capture.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s-auto-%dx%d.png" % [capture,root.size.x,root.size.y])
	Preferences.display_configured=true
	Preferences.window_mode="fullscreen"
	Preferences.window_size=Vector2i(1920,1080)
	Preferences.save_preferences(path)
	Preferences.window_mode="windowed"
	Preferences.window_size=Vector2i(1600,900)
	Preferences.ui_auto_scale=false
	Preferences.load_preferences(path)
	check(Preferences.ui_auto_scale,"automatic preference survives reload")
	check(Preferences.display_configured and Preferences.window_mode=="fullscreen" and Preferences.window_size==Vector2i(1920,1080),"display preferences survive reload")
	var display = preload("res://scripts/window_settings.gd").new()
	root.add_child(display)
	display.mode_picker.select(0)
	display.apply_settings()
	for i in 4: await process_frame
	check(display.pending and Preferences.window_mode=="fullscreen", "display preview does not persist before confirmation")
	display._process(16.0)
	for i in 4: await process_frame
	check(not display.pending and Preferences.window_mode=="fullscreen", "display timeout reverts without changing saved mode")
	display.mode_picker.select(0)
	display.apply_settings()
	for i in 4: await process_frame
	display.keep_changes()
	check(not display.pending and Preferences.window_mode=="windowed", "Keep changes persists display selection")
	display.free()
	DirAccess.remove_absolute(path)
	canvas.free()
	hud.free()
	interaction.free()
	rig.free()
	assets.free()
	print("HUD_SCALE_PASS" if failures.is_empty() else "HUD_SCALE_FAIL")
	quit(0 if failures.is_empty() else 1)
