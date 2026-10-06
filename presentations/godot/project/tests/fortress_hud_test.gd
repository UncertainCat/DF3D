extends SceneTree
var calls: Array = []
class LowerView extends Node:
	var ui_host
	var modal_input := true
	var panel := Control.new()
	var elevation_allowed := false
	func allows_elevation_input(): return elevation_allowed
	func set_play_enabled(_value): pass
	func close_panel(): panel.hide();ui_host.release(self)
class World extends RefCounted:
	var top_z := 12
	var assets
	func is_live(): return true
	func get_top_z(): return top_z
	func ui_texture(selector: String, variant := -1): return assets.ui_texture(selector, variant)
	func ui_font_path(): return assets.ui_font_path()
class Interaction extends Node:
	var state = preload("res://scripts/interaction_state.gd").new()
	var construction_active := false
	var shell_blocked := false
	var shell_enabled := true
	func set_play_enabled(value): panel.visible=value
	var panel := PanelContainer.new()
	var tool_picker := OptionButton.new()
	var priority := SpinBox.new()
	var marker_only := false
	var mining_mode := 0
	var show_priorities := false
	var show_traffic := false
	func set_show_priorities(v): show_priorities = v
	func set_show_traffic(v): show_traffic = v
	var selection := -1
	var pauses: Array = []
	var cancelled := 0
	const TOOLS = preload("res://scripts/interaction.gd").TOOLS
	func _ready():
		add_child(panel)
		add_child(tool_picker)
		add_child(priority)
		for title in TOOLS: tool_picker.add_item(title)
	func select_tool(index):
		selection = index
		tool_picker.select(index)
	func cancel_selection(): cancelled += 1
	func shell_context_visible(): return false
	func update_shell_context(_size): pass
	func _pause(value): pauses.append(value)
class Audio extends Node:
	signal changed
	var volumes := {"Master": 0.8, "Music": 0.5, "UI": 0.7, "SFX": 0.65}
	var muted := false
	var music_paused := false
	var now_playing := "Test track"
	func set_muted(value):
		muted = value
		changed.emit()
	func set_volume(bus, value):
		volumes[bus] = value
		changed.emit()
	func cue(_name): pass
	func pause_music(value): music_paused = value
	func next_track(): pass
func _initialize(): call_deferred("run")
func run():
	var assets := Df3dWorld.new()
	root.add_child(assets)
	assert(assets.load_assets(OS.get_environment("DF3D_DF_PATH")), "Installed interface assets load")
	var rig = load("res://scripts/orbit_camera.gd").new()
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	var i = Interaction.new()
	root.add_child(i)
	var audio := Audio.new()
	root.add_child(audio)
	var audio_panel = load("res://scripts/audio_panel.gd").new()
	audio_panel.audio = audio
	root.add_child(audio_panel)
	var hud = load("res://scripts/fortress_hud.gd").new()
	hud.audio_panel = audio_panel
	hud.world = World.new()
	hud.world.assets = assets
	hud.interaction = i
	hud.camera_rig = rig
	var host=load("res://scripts/ui_host.gd").new();host.interaction=i;root.add_child(host);hud.ui_host=host
	hud.panel_requested.connect(func(title):calls.append(title))
	root.add_child(hud)
	assert(hud.level_down.tooltip_text.is_empty() and hud.level_up.tooltip_text.is_empty() and hud.level_picker.tooltip_text.is_empty())
	assert(hud.notification_rail.visible, "Reports notification rail is enabled for RC2")
	assert(hud.settings.is_ancestor_of(audio_panel.volume_controls), "Volume controls embedded in settings")
	audio_panel.mute.button_pressed = true
	assert(audio.muted)
	audio_panel.sliders.Music.value = 0.25
	assert(is_equal_approx(audio.volumes.Music, 0.25))
	audio.set_volume("Music", 0.6)
	assert(is_equal_approx(audio_panel.sliders.Music.value, 0.6), "External audio changes reconcile without feedback loops")
	audio_panel.sliders.SFX.value = 0.3
	assert(is_equal_approx(audio.volumes.SFX, 0.3), "SFX settings use their own audio bus")
	var calendar_fixture = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/reports/alert_entries.json"))
	for row in calendar_fixture.hud_width_native.rows:
		var groups = hud.native_header_groups(int(row.columns))
		assert(groups.moods == row.moods and groups.resources == row.resource_count)
	for row in calendar_fixture.hud_moon_native.rows:
		assert(hud.native_moon_art(int(row.phase)) == row.art)
	assert(hud.native_moon_art(-1).is_empty() and hud.native_moon_art(28).is_empty())
	var identity = calendar_fixture.hud_identity_native
	for row in identity.rows:
		assert(hud.fortress_identity({"fort_original_name": identity.original_name, "fort_name": identity.translated_name, "fortress_rank": row.rank, "fortress_capital": row.king_arrived}) == identity.original_name + "\n" + identity.translated_name + "\n" + row.caption)
	assert(hud.fortress_identity({}).is_empty())
	assert(hud.fortress_identity({"fortress_rank": -1}).is_empty())
	for row in calendar_fixture.hud_calendar_native.rows:
		assert(hud.fortress_calendar(int(row.year), int(row.year_tick)) == row.text)
	assert(hud.fortress_calendar(104, 225600) == "21st Limestone\nEarly Autumn\nYear 104")
	for day in [11, 12, 13]:
		assert(hud.fortress_calendar(104, (day - 1) * 1200).begins_with("%dth Granite" % day))
	assert(hud.fortress_calendar(104, 403199) == "28th Obsidian\nLate Winter\nYear 104")
	var state = {"fortress_valid": true, "fort_name": "Chantmansion", "year": 104, "year_tick": 168260, "paused": true}
	hud.update_state(true, true, state)
	hud.update_state(true, true, state)  # settle side effects of the first pass
	assert(hud.heading.text == "Chantmansion" and hud.level.text.is_empty() and hud.population.text.is_empty())
	for count in hud.mood_counts: assert(count.text.is_empty())
	var unnamed:Dictionary=state.duplicate(true);unnamed.erase("fort_name")
	hud.update_state(true,true,unnamed);assert(hud.heading.text.is_empty())
	hud.update_state(true,true,state)

	state["moon_phase"] = 1
	hud.update_state(true,true,state)
	hud.layout(Vector2(960,600))
	assert(hud.moon.texture == hud.ui.texture("MOON_WANING_GIBBOUS") and hud.moon.visible)
	state.erase("moon_phase")
	hud.update_state(true,true,state)
	assert(hud.moon.texture == null and not hud.moon.visible)
	var passes: int = hud.state_pass_count
	hud.update_state(true, true, state)
	assert(hud.state_pass_count == passes, "unchanged inputs skip the HUD state pass")
	state["paused"] = false
	hud.update_state(true, true, state)
	assert(hud.state_pass_count == passes + 1, "an in-place session change reruns the HUD state pass")
	state["paused"] = true
	hud.update_state(true, true, state)
	for title in ["Stocks", "Petitions", "Trade", "Tasks", "Places", "Objects", "Justice"]:
		assert(not hud.navigation[title].visible, "Hidden HUD entry: " + title)
	assert(hud.navigation.Reports.visible and not hud.notification_rail.visible, "Reports is exposed; empty notification rail stays hidden")
	i.state.submitted(42, "Dig")
	hud.update_state(true, true, state)
	assert(hud.command_feedback.text == "Waiting for Dwarf Fortress...")
	i.state.receive([{"seq":42,"status":0,"message":"1 of 1 tiles"}])
	hud.update_state(true, true, state)
	assert(hud.command_feedback.text.begins_with("Accepted #42"), "HUD displays acceptance, not the older Sent message")
	i.state.submitted(43, "Dig")
	i.state.receive([{"seq":43,"status":1,"message":"not diggable"}])
	hud.update_state(true, true, state)
	assert(hud.command_feedback.text.begins_with("Rejected #43") and "not diggable" in hud.command_feedback.text, "HUD displays the latest rejection reason")
	for hidden in ["Stockpiles / zones", "Production / farms"]:
		assert(not hud.navigation.has(hidden), "Intentionally hidden action absent from HUD")
	assert(hud.navigation["Build / construction"].visible,"Construction is exposed for RC2")
	assert(hud.navigation["Build / construction"].get_parent() == hud.actions and hud.navigation["Build / construction"].get_index() == hud.navigation.Remove.get_index()+1,"Build occupies native slot after Remove")
	assert(hud.navigation.Stockpiles.get_index() == hud.navigation["Build / construction"].get_index()+1 and hud.navigation.Zones.get_index() == hud.navigation.Stockpiles.get_index()+1,"Stockpile and Zone follow Build in native order")
	assert(not hud.navigation.Stockpiles.visible and not hud.navigation.Zones.visible,"Areas launchers stay hidden pending acceptance")
	hud.navigation["Labor"].pressed.emit()
	assert(not hud.labor_menu.visible, "Read-only Labor does not reopen the legacy editor")
	var reachable: Array = [0, 14]
	for group in ["Dig", "Smooth", "Chop trees", "Gather plants", "Remove"]:
		hud.navigation[group].pressed.emit()
		for button in hud.tools.buttons.values():
			if button.has_meta("tool_index"):
				var index = button.get_meta("tool_index")
				button.pressed.emit()
				assert(i.selection == index, "Tool button selects its semantic ID")
				if not index in reachable: reachable.append(index)
	assert(reachable.size() == 14, "Native operations reachable; legacy individual stair and family clear buttons retired")
	hud.choose_tool(15)
	assert(i.selection == 15 and hud.tools.get_child_count() > 0, "Single stairs tool selects vertical-span command")
	hud.pause.pressed.emit()
	assert(i.pauses.is_empty(), "Native pause is idempotent while paused")
	hud.play_button.pressed.emit()
	assert(i.pauses == [false], "Native play requests resume")
	i.pauses.clear()
	hud.toggle_pause()
	assert(i.pauses == [false], "Pause button derives resume from native state")
	i.construction_active = true
	hud.update_state(true, true, state)
	hud.launch("Citizens")
	hud.choose_tool(1)
	hud.toggle_pause()
	assert(calls.size() == 0 and i.selection == 15 and i.pauses.size() == 1, "Open controller owns navigation; cannot bypass petition Back")
	i.construction_active = false
	hud.update_state(false, true, state)
	hud.launch("Reports")
	hud.choose_tool(1)
	assert(calls.size() == 0 and i.selection == 15, "Saving and disabled play block actions")
	hud.update_state(true, true, state)
	var levels: Array = []
	hud.level_step_requested.connect(func(value): levels.append(value))
	hud.step_level(1)
	assert(levels == [1])
	state["fortress_summary"] = {"available":true,"population":177,"stress_available":true,"stress_counts":[8,8,21,38,27,18,57],"elevation_offset":-129,"level_count":256,"resources_available":true,"bookkeeper_precision":0,"resource_counts":[852,135,310,206,14,453,247]}
	hud.update_state(true, true, state)
	for index in 7: assert(hud.resource_counts[index].text == ["~900","~100","~300","~200","~10","~500","~200"][index])
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../fixtures/hud/native_resource_counts.json")))
	assert(recorded.cases.size() == 546, "Native rounding reference is complete")
	for entry in recorded.cases:
		assert(hud.native_resource_count(int(entry.value), int(entry.precision)) == entry.text, "Native rendered count differs: %s" % entry)
	assert(hud.native_resource_count(135, -1) == "", "Missing precision does not invent a native count")
	state.fortress_summary.bookkeeper_precision = 1000
	hud.update_state(true, true, state)
	assert(hud.resource_counts[0].text == "852", "Precision-only changes refresh the HUD")
	state.fortress_summary.erase("bookkeeper_precision")
	hud.update_state(true, true, state)
	assert(hud.resource_counts[0].text == "", "Older snapshots do not assume lowest precision")
	state.fortress_summary.bookkeeper_precision = 0
	hud.update_state(true, true, state)
	assert(hud.population.text == "Pop\n\n177" and hud.mood_counts[0].text == "57" and hud.mood_counts[6].text == "8")
	assert(hud.level.text == "Elevation -117" and hud.level_picker.min_value == -129 and hud.level_picker.max_value == 126)
	hud.level_picker.value = -116
	assert(levels == [1, 1], "Elevation selection converts to internal local level exactly once")
	levels.pop_back()
	var placement := LowerView.new(); root.add_child(placement); placement.add_child(placement.panel)
	host.register(placement); host.activate(placement)
	assert(hud.play_button.disabled,"Modal ownership immediately disables HUD play")
	host.release(placement)
	assert(not hud.play_button.disabled,"Dismissal immediately enables HUD play before another update/frame")
	host.activate(placement)
	hud.update_state(true, true, state)
	hud.step_level(1)
	assert(levels == [1] and hud.level_up.disabled, "Modal views deny elevation unless they opt in")
	placement.elevation_allowed = true
	hud.update_state(true, true, state)
	assert(not hud.level_up.disabled and hud.level_picker.editable, "Placement opt-in invalidates cached HUD controls")
	hud.step_level(1); hud.select_elevation(-116)
	assert(levels == [1,1,1], "Placement allows both relative and absolute elevation navigation")
	levels.resize(1)
	placement.elevation_allowed = false
	hud.update_state(true, true, state)
	hud.select_elevation(-116)
	assert(levels == [1] and hud.level_up.disabled and not hud.level_picker.editable, "Material selection revokes elevation without reopening the panel")
	placement.elevation_allowed = true; host.set_overlay_blocked(true)
	hud.step_level(1)
	assert(levels == [1], "Overlay blocks a modal placement opt-in")
	host.set_overlay_blocked(false); host.close_active(); placement.free()
	hud.update_state(true, true, state)
	hud.layout(Vector2(640,480))
	assert(not hud.resources.visible and hud.population.tooltip_text.is_empty())
	assert(not hud.date.visible and hud.status_panel.position.x >= 0)
	hud.layout(Vector2(480,360))
	assert(not hud.moods.visible, "Small windows keep population and working picker without overflowing mood row")
	hud.layout(Vector2(1920,1080))
	assert(hud.moods.visible and hud.date.visible)
	# Container geometry is checked after sorting, including the actual button
	# row: viewport-only label assertions missed the old full-width +/- bars.
	for view in [Vector2i(1920,1080), Vector2i(960,640), Vector2i(640,480)]:
		root.size = view
		hud.layout(Vector2(view))
		await process_frame
		await process_frame
		hud.layout(Vector2(view))
		await process_frame
		await process_frame
		assert(not hud.resources.visible or view.x >= 1112)
		assert(hud.resources.get_child(2).visible == (view.x >= 1224))
		if hud.resources.visible: assert(hud.status_panel.get_global_rect().encloses(hud.resources.get_global_rect()), "Resource groups stay within header")
		if hud.resources.visible: assert(is_equal_approx(hud.resource_counts[0].global_position.y, hud.mood_counts[0].global_position.y), "Resource and mood count baselines align: %s %s at %s" % [hud.resource_counts[0].global_position.y, hud.mood_counts[0].global_position.y, view])
		if view.x >= 1800: assert(hud.playback.get_global_rect().end.x <= hud.minimap_panel.global_position.x, "Wide header/navigation stay left of minimap")
		assert(hud.heading.global_position.x == 144 and hud.population.global_position.x == 304, "Native fixed identity/population columns")
		if hud.moods.visible: assert(hud.moods.position.x - hud.population.get_rect().end.x <= 12, "Mood counts stay next to population")
		assert(hud.summary_spacer.get_index() > hud.moods.get_index() and hud.summary_spacer.get_index() < hud.date.get_index())
		assert(hud.status_panel.get_rect().end.x <= hud.playback.position.x, "Header stays clear of playback controls at %s: %s vs %s" % [view, hud.status_panel.get_rect(), hud.playback.position])
		assert(not hud.navigation["Stocks"].visible, "Unfinished Stocks stays hidden")
		assert(hud.navigation["Stocks"].get_index() > hud.moods.get_index() and hud.navigation["Stocks"].get_index() < hud.resources.get_index(), "Stocks follows native header grouping")
		if hud.moods.visible: assert(hud.status_panel.get_global_rect().encloses(hud.moods.get_global_rect()), "All mood counts fit in the header at %s: %s / %s" % [view, hud.status_panel.get_global_rect(), hud.moods.get_global_rect()])
		assert(not hud.level_steps.visible,"Unsourced stepper is not part of native minimap frame")
		assert(hud.minimap.size==Vector2(192,192))
		assert(hud.minimap_layer.layer==2 and hud.layer==1)
		assert(hud.minimap_panel.size==Vector2(200,216),"Native right frame geometry: %s" % hud.minimap_panel.size)
		assert(hud.minimap.position==hud.minimap_panel.position+Vector2(8,0))
		assert(hud.level_controls.size.y < 80 and hud.level_controls.get_rect().end.x <= view.x, "Elevation uses one compact input row inside the viewport")
	# Let container sorting settle, then ensure normal frame updates reuse layout.
	for frame in 6:
		hud.update_state(true, true, state)
		await process_frame
	var layouts: int = hud.layout_count
	var header_rect: Rect2 = hud.status_panel.get_rect()
	for frame in 12:
		hud.update_state(true, true, state)
		await process_frame
	assert(hud.layout_count == layouts and hud.status_panel.get_rect() == header_rect, "Idle HUD updates reuse settled layout")
	# Same-width count changes must refresh content even at compact widths.
	state.fortress_summary.resource_counts[0] = 453
	hud.update_state(true, true, state)
	assert(hud.resource_counts[0].text == "~500" and hud.population.tooltip_text.is_empty(), "Counts update without invented compact tooltip copy")
	hud.update_state(false, true, state)
	assert(hud.level_down.disabled and hud.level_up.disabled and not hud.level_picker.editable, "Cached geometry cannot delay save input blocking")
	hud.update_state(true, true, state)
	assert(not hud.level_down.disabled and not hud.level_up.disabled and hud.level_picker.editable, "Cached geometry cannot delay restored controls")
	state.fortress_summary.resources_available = false
	state.fortress_summary.resource_counts = []
	hud.update_state(true, true, state)
	for label in hud.resource_counts: assert(label.text.is_empty(), "Unavailable counts clear old stocks")
	hud.level_down.pressed.emit()
	assert(levels == [1, -1], "Compact down button keeps semantic navigation")
	levels.pop_back()
	hud.world.top_z = 0
	hud.update_state(true, true, state)
	assert(hud.level_down.disabled and not hud.level_up.disabled, "Bottom level cannot step below the map")
	hud.world.top_z = 255
	hud.update_state(true, true, state)
	assert(hud.level_up.disabled and not hud.level_down.disabled, "Top level cannot step above the map")
	hud.world.top_z = 12
	hud.update_state(true, true, state)
	hud.toggle_settings()
	hud.update_state(true, true, state)
	assert(not hud.level_down.disabled and not hud.level_up.disabled and hud.level_picker.editable, "Elevation controls remain on the HUD")
	assert(i.shell_blocked and rig.controls_blocked(), "Settings block map commands and camera")
	hud.step_level(-1)
	assert(levels == [1, -1], "Explicit elevation commands remain usable while map input is blocked")
	hud.launch("Citizens")
	assert(calls.size() == 0)
	hud.toggle_settings()
	hud.update_state(true, true, state)
	assert(hud.level_steps.get_parent() == hud.level_controls, "Elevation belongs to HUD, not settings")
	assert(not hud.Availability.allows("Production / farms"), "Removed production entry fails closed")
	for style in ["classic", "billboard"]:
		var index = ["classic", "billboard"].find(style)
		hud.style_picker.item_selected.emit(index)
		assert(hud.Preferences.visual_style == style, "Style dropdown selects distinct persisted mode")
	hud.camera_picker.item_selected.emit(1)
	assert(rig.get_mode() == "isometric" and hud.camera_picker.selected == 1)
	hud.toggle_game_menu()
	hud.update_state(true, true, state)
	assert(hud.blocks_camera() and i.shell_blocked)
	hud.toggle_game_menu()
	assert(not hud.game_menu.visible and calls.is_empty())
	hud.toggle_help()
	hud.update_state(true, true, state)
	assert(hud.blocks_camera() and not hud.settings.visible)
	hud.toggle_help()
	rig.set_df_mode(true)
	assert(not hud.free_help.visible and i.selection == 15, "DF hides 3D instructions without resetting selection")
	rig.set_df_mode(false)
	assert(hud.free_help.visible and i.selection == 15)
	root.size=Vector2i(1280,720)
	var below := CanvasLayer.new();below.layer=2;root.add_child(below)
	var lower := LowerView.new();root.add_child(lower);below.add_child(lower.panel);lower.panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.register(lower);host.activate(lower)
	var exposed := Button.new();exposed.text="Underlying editor action";exposed.position=Vector2(60,220);exposed.size=Vector2(240,50);lower.panel.add_child(exposed)
	var presses: Array=[];exposed.pressed.connect(func(): presses.append(true))
	hud.close_menus();exposed.grab_focus();hud.toggle_settings();hud.update_state(true,true,state)
	await process_frame
	assert(root.gui_get_focus_owner()!=exposed,"Overlay releases underlying GUI keyboard focus")
	assert(exposed.get_focus_mode_with_override() == Control.FOCUS_NONE, "Blocked editor descendants cannot accept focus")
	var focus_next := InputEventAction.new();focus_next.action="ui_focus_next";focus_next.pressed=true;root.push_input(focus_next,true)
	focus_next.pressed=false;root.push_input(focus_next,true)
	assert(root.gui_get_focus_owner()!=exposed,"Blocked editor descendants cannot regain GUI keyboard focus")
	var accept := InputEventAction.new();accept.action="ui_accept";accept.pressed=true;root.push_input(accept,true)
	accept.pressed=false;root.push_input(accept,true)
	assert(presses.is_empty(),"Keyboard accept cannot activate blocked editor button")
	var point := exposed.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	var press := InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=point;press.pressed=true;root.push_input(press,true)
	var release := InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=point;release.pressed=false;root.push_input(release,true)
	await process_frame
	assert(presses.is_empty(),"Overlay intercepts exposed lower-layer GUI button clicks")
	hud.close_menus()
	exposed.grab_focus()
	assert(root.gui_get_focus_owner()==exposed,"Closing overlay restores editor keyboard focus")
	root.push_input(motion,true);root.push_input(press,true);root.push_input(release,true)
	await process_frame
	assert(presses.size()==1,"Closing overlay restores lower-layer GUI interaction")
	host.close_active();below.free();lower.free()
	hud.update_state(false, false, {})
	assert(not hud.visible and not hud.settings.visible, "Loader hides fortress shell")
	hud.free()
	audio_panel.free()
	audio.free()
	host.free()
	i.free()
	rig.free()
	assets.free()
	print("FORTRESS_HUD_TEST_PASS")
	quit()
