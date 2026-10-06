extends CanvasLayer
signal panel_requested(title: String)
var ui_host
signal level_step_requested(delta: int)
signal notification_requested(group: Dictionary)
signal notification_dismissal_requested(group: Dictionary)
signal notification_dismissed(group: Dictionary)
signal visual_style_changed(style: String)
signal recovery_requested
signal info_requested(destination: String)
# Presentation-only navigation. Existing controllers retain command ownership.
const Availability = preload("res://scripts/ui_availability.gd")
const Preferences = preload("res://scripts/presentation_settings.gd")
const Layout = preload("res://scripts/hud_layout.gd")
const INFO_SLOTS = [["Citizens", "CREATURES"], ["Tasks", "TASKS"], ["Places", "PLACES"], ["Labor", "LABOR"], ["Work orders", "WORK_ORDERS"], ["Nobles and administrators", "NOBLES"], ["Objects", "OBJECTS"], ["Justice", "JUSTICE"]]
const OriginalUI = preload("res://scripts/original_ui.gd")
const Interaction = preload("res://scripts/interaction.gd")
var world
var interaction
var camera_rig
var session_controls
var native_options
var audio_panel
var ui
var enabled := false
var entered := false
var session: Dictionary = {}
var navigation: Dictionary = {}
var moon: TextureRect
var top: Control
var actions: HBoxContainer
var information: HBoxContainer
var alerts: VBoxContainer
var red_alert
var notification_rail
var status_panel: PanelContainer
var play_button: Button
var playback: HBoxContainer
var minimap_panel: PanelContainer
var native_help
var minimap_column: VBoxContainer
var minimap
var minimap_layer:CanvasLayer
var minimap_slot:Control
var level_controls: VBoxContainer
var level_steps: HBoxContainer
var level_down: Button
var level_up: Button
var tools: HBoxContainer
var labor_menu: PanelContainer
var settings: PanelContainer
var heading: Label
var date: Label
var population: Label
var moods: HBoxContainer
var mood_counts: Array[Label] = []
const RESOURCE_NAMES = ["Food", "Drink", "Seeds", "Meat", "Fish", "Plant", "Other"]
# Label colors follow the original header; values keep the original UI font color.
const RESOURCE_COLORS = [Color.WHITE, Color8(255,225,17), Color8(215,155,45), Color8(255,113,17), Color8(18,254,207), Color8(19,253,101), Color8(192,192,192)]
var resources: HBoxContainer
var resource_counts: Array[Label] = []
var summary_spacer: Control
var level_picker: SpinBox
var summary: Dictionary = {}
var level: Label
var pause: Button
var camera_picker: OptionButton
var style_picker: OptionButton
var game_menu: PanelContainer
var help_panel: PanelContainer
var free_help: Label
var scale_toggle: CheckButton
var settings_button: Button
var command_feedback: Label
var root_control: Control
var active_launcher := ""
var _layout_key: Array = []
var layout_count := 0
# update_state runs every frame; the state pass only reruns when an input changed.
var _state_key: Array = []
var state_pass_count := 0
var scale_picker: SpinBox
var scale_note: Label
var grid_toggle: CheckButton
var speed_picker: SpinBox
var utility_buttons: Array[Button] = []

func _ready():
	Preferences.load_preferences()
	layer = 1
	add_to_group("fortress_hud")
	ui = OriginalUI.new()
	ui.configure(world)
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	status_panel = preload("res://scripts/native_header_frame.gd").new()
	root_control.add_child(status_panel)
	top = Control.new()
	status_panel.add_child(top)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_FILL
	top.add_child(heading)
	population = Label.new()
	population.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(population)
	moods = HBoxContainer.new()
	moods.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	moods.add_theme_constant_override("separation", 0)
	top.add_child(moods)
	for index in 7:
		var box = VBoxContainer.new()
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_theme_constant_override("separation",0)
		moods.add_child(box)
		var icon = TextureRect.new()
		icon.texture = ui.texture("BUTTON_STRESS_%d" % index)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		box.add_child(icon)
		var count = Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(count)
		count.custom_minimum_size.x = 16
		count.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mood_counts.append(count)
	add_launcher(top, "Stocks", "")
	navigation["Stocks"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	navigation["Stocks"].custom_minimum_size = Vector2(72, 32)
	resources = HBoxContainer.new()
	resources.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resources.add_theme_constant_override("separation", 16)
	top.add_child(resources)
	for index in 7:
		var column = VBoxContainer.new()
		column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		column.add_theme_constant_override("separation",0)
		column.custom_minimum_size.x = 40
		resources.add_child(column)
		var title = Label.new()
		title.text = RESOURCE_NAMES[index]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.custom_minimum_size.y = 24
		title.add_theme_color_override("font_color", RESOURCE_COLORS[index])
		column.add_child(title)
		var count = Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(count)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		resource_counts.append(count)
	# Keep fortress identity and population together; only the space before
	# the calendar grows. Further authoritative summary groups belong here.
	summary_spacer = Control.new()
	summary_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(summary_spacer)
	date = Label.new()
	top.add_child(date)
	moon = TextureRect.new()
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.custom_minimum_size = Vector2(32, 32)
	moon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(moon)
	playback = HBoxContainer.new()
	root_control.add_child(playback)
	playback.add_theme_constant_override("separation", 0)
	pause = icon_button(playback, "Pause", "BUTTON_PAUSE_ACTIVE", func(): set_paused(true))
	play_button = icon_button(playback, "Play", "BUTTON_PLAY_INACTIVE", func(): set_paused(false))
	for button in [pause, play_button]:
		button.custom_minimum_size = Vector2(16, 24)
		button.tooltip_text = ""
	# Reserve native gear/help slots; their native destinations remain unfinished.
	var routes_pending := Control.new()
	routes_pending.custom_minimum_size = Vector2(32, 24)
	playback.add_child(routes_pending)
	information = HBoxContainer.new()
	root_control.add_child(information)
	information.add_theme_constant_override("separation", 4)
	for entry in INFO_SLOTS:
		var caption: String = entry[0]
		var icon := "BUTTON_INFO_" + str(entry[1])
		if caption == "Labor": navigation[caption] = icon_button(information, caption, icon, toggle_labor)
		elif caption in ["Citizens", "Work orders", "Nobles and administrators"]: add_launcher(information, caption, icon)
		else:
			navigation[caption] = icon_button(information, caption, icon, func(): info_requested.emit(caption))
	for caption in INFO_SLOTS:
		navigation[caption[0]].visible = Availability.allows_launcher(caption[0])
	labor_menu = PanelContainer.new()
	root_control.add_child(labor_menu)
	var labor_tabs = HBoxContainer.new()
	labor_menu.add_child(labor_tabs)
	icon_button(labor_tabs, "Work details", "", func():
		labor_menu.hide()
		launch("Work Details"))
	icon_button(labor_tabs, "Kitchen", "", func():
		labor_menu.hide()
		launch("Kitchen"))
	icon_button(labor_tabs, "Back", "", func(): labor_menu.hide())
	labor_menu.hide()
	alerts = VBoxContainer.new()
	root_control.add_child(alerts)
	alerts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_launcher(root_control, "Petitions", "")
	add_launcher(root_control, "Reports", "ANNOUNCEMENT_OPEN_ALL_ANNOUNCEMENTS")
	red_alert = preload("res://scripts/red_alert_launcher.gd").new()
	red_alert.world = world
	root_control.add_child(red_alert)
	red_alert.group_requested.connect(func(group): notification_requested.emit(group))
	red_alert.dismissal_requested.connect(func(group): notification_dismissal_requested.emit(group))
	notification_rail = preload("res://scripts/notification_rail.gd").new()
	notification_rail.visible = Availability.allows_launcher("Reports")
	notification_rail.world = world
	notification_rail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	alerts.add_child(notification_rail)
	notification_rail.group_requested.connect(func(group): notification_requested.emit(group))
	notification_rail.group_dismissed.connect(func(group): notification_dismissed.emit(group))
	actions = HBoxContainer.new()
	root_control.add_child(actions)
	# A launcher selects its family's first tool (TOOL_FAMILIES order) and toggles back to inspect.
	for entry in [["Dig", "BUTTON_DIG_DIG_INACTIVE"], ["Chop trees", "BUTTON_DES_CHOP_INACTIVE"], ["Gather plants", "BUTTON_DES_GATHER_INACTIVE"], ["Smooth", "BUTTON_DES_SMOOTH_INACTIVE"], ["Remove", "BUTTON_DES_ERASE"]]:
		var family: String = entry[0]
		var index: int = Interaction.TOOL_FAMILIES[family][0]
		var b = icon_button(actions, family, entry[1], func():
			var current: int = interaction.tool_picker.selected
			choose_tool(Interaction.Tool.INSPECT_ITEMS if current in Interaction.TOOL_FAMILIES[family] or (current in Interaction.BLUEPRINT_TOOLS and tools.family == family) else index))
		navigation[entry[0]] = b
	add_launcher(actions,"Build / construction","BUTTON_BUILDING_INACTIVE")
	add_launcher(actions,"Stockpiles","BUTTON_STOCKPILE_INACTIVE")
	add_launcher(actions,"Zones","BUTTON_ZONE_INACTIVE")
	tools = preload("res://scripts/designation_toolbar.gd").new()
	tools.hud = self
	root_control.add_child(tools)
	minimap_panel = preload("res://scripts/native_minimap_frame.gd").new()
	minimap_panel.configure(ui)
	root_control.add_child(minimap_panel)
	native_help=preload("res://scripts/native_hover_view.gd").new()
	root_control.add_child(native_help);native_help.configure(world);native_help.z_index=1
	native_help.showing_changed.connect(func(showing):
		minimap_panel.visible=not showing
		minimap_layer.visible=entered and not showing)
	minimap_column = VBoxContainer.new()
	minimap_column.add_theme_constant_override("separation",0)
	minimap_panel.add_child(minimap_column)
	minimap = preload("res://scripts/fortress_minimap.gd").new()
	minimap.world = world
	minimap.camera_rig = camera_rig
	minimap.interaction = interaction
	minimap_slot=Control.new();minimap_slot.custom_minimum_size=Vector2(192,192)
	minimap_slot.mouse_filter=Control.MOUSE_FILTER_IGNORE
	minimap_column.add_child(minimap_slot)
	minimap_layer=CanvasLayer.new();minimap_layer.layer=2;add_child(minimap_layer)
	minimap_layer.add_child(minimap)
	level = Label.new()
	level.add_theme_font_size_override("font_size",12)
	level.add_theme_color_override("font_color",Color.WHITE)
	level_controls = VBoxContainer.new()
	level_controls.add_theme_constant_override("separation",0)
	minimap_column.add_child(level_controls)
	level_controls.add_child(level)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_steps = HBoxContainer.new()
	level_controls.add_child(level_steps)
	# Native elevation uses the overview strip; the old numeric stepper is unsourced.
	level_steps.hide()
	level_down = icon_button(level_steps, "-", "", func(): step_level(-1))
	level_down.tooltip_text = ""
	level_picker = SpinBox.new()
	level_picker.step = 1
	level_picker.custom_minimum_size.x = 76
	level_picker.value_changed.connect(select_elevation)
	level_steps.add_child(level_picker)
	level_up = icon_button(level_steps, "+", "", func(): step_level(1))
	level_up.tooltip_text = ""
	command_feedback = Label.new()
	command_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	command_feedback.custom_minimum_size.x = 280
	command_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_control.add_child(command_feedback)
	settings_button = icon_button(root_control, "DF3D", "BUTTON_SETTINGS", toggle_settings)
	settings_button.hide() # Custom settings are not the native gear destination.
	settings = PanelContainer.new()
	root_control.add_child(settings)
	var menu_scroll := ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings.add_child(menu_scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	menu_scroll.add_child(box)
	section_title(box, "DF3D settings")
	icon_button(box, "Close", "", toggle_settings)
	section_title(box, "Display")
	var scale_row := HBoxContainer.new()
	box.add_child(scale_row)
	var scale_label := Label.new()
	scale_label.text = "Interface scale"
	scale_row.add_child(scale_label)
	scale_picker = SpinBox.new()
	scale_picker.custom_minimum_size.x = 112
	scale_picker.min_value = 75
	scale_picker.max_value = 200
	scale_picker.step = 5
	scale_picker.suffix = "%"
	scale_picker.value = Preferences.ui_scale * 100.0
	scale_picker.value_changed.connect(set_ui_scale_percent)
	scale_row.add_child(scale_picker)
	scale_note = Label.new()
	box.add_child(scale_note)
	grid_toggle = CheckButton.new()
	grid_toggle.text = "Show targeting grid"
	grid_toggle.button_pressed = Preferences.targeting_grid
	grid_toggle.toggled.connect(func(value):
		Preferences.targeting_grid = value
		save_preferences())
	box.add_child(grid_toggle)
	style_picker = OptionButton.new()
	for title in ["Cutouts", "Billboard"]: style_picker.add_item(title)
	style_picker.select(["classic", "billboard"].find(Preferences.visual_style))
	style_picker.tooltip_text = "Cutouts: flat sprites with depth. Billboard: character sprites always face the camera."
	style_picker.item_selected.connect(func(index):
		Preferences.visual_style = ["classic", "billboard"][index]
		save_preferences()
		visual_style_changed.emit(Preferences.visual_style))
	labeled_control(box, "Visual style", style_picker)
	RenderingServer.global_shader_parameter_set("actor_animation_strength", Preferences.animation_strength)
	scale_toggle = CheckButton.new()
	scale_toggle.text = "Truescale"
	scale_toggle.tooltip_text = "Scale other creatures relative to dwarves. Dwarves retain their original sprite size, except babies."
	scale_toggle.button_pressed = Preferences.truescale
	RenderingServer.global_shader_parameter_set("actor_truescale", Preferences.truescale)
	scale_toggle.toggled.connect(func(value):
		Preferences.truescale = value
		RenderingServer.global_shader_parameter_set("actor_truescale", value)
		save_preferences())
	box.add_child(scale_toggle)
	var combat_toggle := CheckButton.new()
	combat_toggle.text = "Combat effects"
	combat_toggle.button_pressed = Preferences.combat_effects
	combat_toggle.toggled.connect(func(value):
		Preferences.combat_effects = value
		save_preferences())
	box.add_child(combat_toggle)
	section_title(box, "Camera")
	camera_picker = OptionButton.new()
	camera_picker.tooltip_text = "F4 cycles DF / Isometric / Free. F5 enters or leaves Walk near the current focus."
	for title in ["DF", "Isometric", "Free", "Walk"]: camera_picker.add_item(title)
	camera_picker.item_selected.connect(func(index):
		if enabled:
			camera_rig.set_mode(["df", "isometric", "free", "walk"][index])
			refresh_camera())
	labeled_control(box, "View", camera_picker)
	var speed_row := HBoxContainer.new()
	box.add_child(speed_row)
	var speed_label := Label.new()
	speed_label.text = "Camera move speed"
	speed_row.add_child(speed_label)
	speed_picker = SpinBox.new()
	speed_picker.custom_minimum_size.x = 96
	speed_picker.min_value = 5
	speed_picker.max_value = 80
	speed_picker.step = 5
	speed_picker.value = Preferences.move_speed
	speed_picker.value_changed.connect(func(value):
		Preferences.move_speed = value
		camera_rig.move_speed = value
		save_preferences())
	speed_row.add_child(speed_picker)
	section_title(box, "Audio")
	if audio_panel != null: audio_panel.embed_settings(box)
	else: section_title(box, "Audio unavailable")
	var troubleshooting := VBoxContainer.new()
	var expand := CheckButton.new()
	expand.text = "Troubleshooting"
	expand.toggled.connect(func(value): troubleshooting.visible = value)
	box.add_child(expand)
	box.add_child(troubleshooting)
	icon_button(troubleshooting, "Close interface panels (F10)", "", func(): recovery_requested.emit())

	troubleshooting.hide()
	settings.hide()
	# Session/gameplay actions are deliberately separate from Godot settings.
	game_menu = PanelContainer.new()
	root_control.add_child(game_menu)
	var game_box := VBoxContainer.new()
	game_menu.add_child(game_box)
	section_title(game_box, "Game")
	icon_button(game_box, "Close", "", toggle_game_menu)
	if session_controls != null:
		icon_button(game_box, "Save game", "", func():
			session_controls.panel.visible = not session_controls.panel.visible)
	for caption in ["Trade"]:
		var utility := icon_button(game_box, caption, "", func():
			game_menu.hide()
			launch(caption))
		utility.visible = Availability.allows(caption)
		utility.set_meta("utility", true)
		navigation[caption] = utility
		utility_buttons.append(utility)
	game_menu.hide()
	help_panel = PanelContainer.new()
	root_control.add_child(help_panel)
	var help_box := VBoxContainer.new()
	help_panel.add_child(help_box)
	icon_button(game_box, "Camera help", "", toggle_help)
	icon_button(help_box, "Close help", "", toggle_help)
	free_help = Label.new() # Text is set by refresh_camera() for the active mode.
	help_box.add_child(free_help)
	section_title(help_box, "F4 cycle camera · F10 recover interface")
	help_panel.hide()
	ui.apply(self)
	# Native header uses the installed8x12 cells; inherited16px text clips
	# identity/calendar and forces the count rows below the48px header.
	for label in [heading,population,date]+mood_counts+resource_counts:
		label.add_theme_font_size_override("font_size",12)
		label.add_theme_constant_override("line_spacing",0)
		label.add_theme_color_override("font_color",Color.WHITE)
	for column in resources.get_children():
		column.get_child(0).add_theme_font_size_override("font_size",12)
	minimap_panel.configure(ui)
	var petition_art: Texture2D = ui.texture("PETITIONS_LIGHT")
	if petition_art != null:
		var petition_style := StyleBoxTexture.new()
		petition_style.texture = petition_art
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			petition_style.set_texture_margin(side, 8)
			petition_style.set_content_margin(side, 8)
		for side in [SIDE_TOP, SIDE_BOTTOM]:
			petition_style.set_texture_margin(side, 12)
			petition_style.set_content_margin(side, 4)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			navigation["Petitions"].add_theme_stylebox_override(state, petition_style)
		navigation["Petitions"].text = "PETITIONS"

	var frame: StyleBox = native_frame()
	settings.add_theme_stylebox_override("panel", frame.duplicate())
	game_menu.add_theme_stylebox_override("panel", frame.duplicate())
	help_panel.add_theme_stylebox_override("panel", frame.duplicate())
	status_panel.configure(ui)

	camera_rig.move_speed = Preferences.move_speed
	if Preferences.camera_mode != "" and OS.get_environment("DF3D_CAM_MODE").is_empty():
		camera_rig.set_mode(Preferences.camera_mode)
	camera_rig.mode_changed.connect(func():
		if camera_rig.get_mode() == "walk":
			Preferences.visual_style = "billboard"
			style_picker.select(1)
			visual_style_changed.emit("billboard")
			scale_toggle.button_pressed = true
			interaction.cancel_selection()
		refresh_camera()
		# Walk needs a chosen, loaded floor; do not resume it before terrain loads.
		if camera_rig.get_mode() != "walk": Preferences.camera_mode = camera_rig.get_mode()
		save_preferences())
	refresh_camera()
	visible = false
	if ui_host != null:
		# Panel dismissal must enable the next click immediately, independently
		# of the periodic fortress-state refresh.
		ui_host.input_gate_changed.connect(func(): update_state(enabled,entered,session))

func icon_button(parent: Node, title: String, art: String, callback: Callable) -> Button:
	var b = Button.new()
	b.name = title.validate_node_name()
	b.tooltip_text = title
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
	if not art.is_empty(): b.icon = ui.texture(art)
	if b.icon == null: b.text = title
	else:
		b.set_meta("native_normal", b.icon)
		var active_name = art.replace("_INACTIVE", "_ACTIVE") if art.ends_with("_INACTIVE") else art + "_ACTIVE"
		b.set_meta("native_active", ui.texture(active_name))
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.mouse_entered.connect(func(): b.modulate = Color(1.2, 1.2, 1.2))
		b.mouse_exited.connect(func(): b.modulate = Color.WHITE)
	b.custom_minimum_size = Vector2(32, 36)
	return b

func add_launcher(parent: Node, title: String, art: String):
	navigation[title] = icon_button(parent, title, art, func(): launch(title))
	navigation[title].visible = Availability.allows_launcher(title)

func toggle_labor():
	if not enabled or interaction.construction_active or menu_open(): return
	launch("Work Details")

func launch(title: String):
	if not Availability.allows(title): return
	if Availability.READ_LAUNCHERS.has(title):
		if enabled and not interaction.construction_active and not menu_open(): info_requested.emit(Availability.READ_LAUNCHERS[title])
		return
	if not enabled or (interaction.construction_active and title != owned_launcher()) or menu_open(): return
	labor_menu.hide()
	interaction.cancel_selection()
	panel_requested.emit(title)
	active_launcher = owned_launcher()

func owned_launcher() -> String:
	if ui_host == null or not is_instance_valid(ui_host.active): return ""
	return str(ui_host.active.launcher_destination) if "launcher_destination" in ui_host.active else ""

func launcher_rect(title: String) -> Rect2:
	if not navigation.has(title) or not navigation[title].is_visible_in_tree(): return Rect2()
	var button: Control = navigation[title]
	var transform := button.get_global_transform_with_canvas()
	return Rect2(transform * Vector2.ZERO,button.size * transform.get_scale())

func choose_tool(index: int):
	if not enabled or interaction.construction_active or menu_open(): return
	interaction.select_tool(index)
	rebuild_tools()

func rebuild_tools():
	tools.refresh()

func set_paused(value: bool):
	if not enabled or interaction.construction_active or menu_open() or not world.is_live(): return
	if bool(session.get("paused", false)) != value: interaction._pause(value)

func toggle_pause():
	if not enabled or interaction.construction_active or menu_open(): return
	interaction._pause(not bool(session.get("paused", false)))

func step_level(delta: int):
	if enabled and elevation_available():
		level_step_requested.emit(delta)

func select_elevation(value: float):
	if enabled and elevation_available() and summary.get("available", false):
		var local_level := clampi(int(value) - int(summary.elevation_offset), 0, int(summary.level_count) - 1)
		level_step_requested.emit(local_level - world.get_top_z())

func elevation_available() -> bool:
	return not interaction.construction_active or (ui_host != null and ui_host.allows_elevation_input())

func toggle_settings():
	if not entered: return
	game_menu.hide()
	help_panel.hide()
	settings.visible = not settings.visible
	sync_menu_gate()
	if session_controls != null and not settings.visible: session_controls.panel.hide()

func refresh_camera():
	var df: bool = camera_rig.is_df_mode()
	style_picker.disabled = camera_rig.get_mode() == "walk"
	scale_toggle.disabled = camera_rig.get_mode() == "walk"
	camera_picker.select(["df", "isometric", "free", "walk"].find(camera_rig.get_mode()))
	free_help.text = "Walk: click map to look · WASD move · Shift faster\nSpace jump · Walk off edges to drop · Q descend stairs · Esc release · F4 return" if camera_rig.get_mode() == "walk" else "RMB orbit (Free) · MMB pan · wheel zoom\nWASD move · QE height · F4 cycle camera"
	free_help.visible = not df

# Native rendered Food/Drink controls: protected captures 20260929-145258/145456.
# Precision is the achieved bookkeeping value, not the requested nobles setting.
static func native_resource_count(value: int, precision: int) -> String:
	if value < 0 or precision < 0: return ""
	if value == 0: return "None"
	if precision >= 100000: return str(value)
	var exact_limit := 10
	for threshold in [100, 1000, 10000]:
		if precision >= threshold: exact_limit *= 10
	if value <= exact_limit: return str(value)
	var magnitude: int = 1
	while value > magnitude * exact_limit: magnitude *= 10
	var rounded: int = ((value + magnitude / 2) / magnitude) * magnitude
	# The pinned native formatter wraps signed int32 at the extreme count edge.
	if rounded > 2147483647: rounded -= 4294967296
	return "~%d" % rounded

# DF53.16 native header width matrix (fixtures/reports/alert_entries.json).
static func native_moon_art(phase: int) -> String:
	if phase < 0 or phase > 27: return ""
	if phase == 0 or phase == 27: return "MOON_FULL_MOON"
	if phase <= 4: return "MOON_WANING_GIBBOUS"
	if phase <= 8: return "MOON_WANING_HALF_MOON"
	if phase <= 12: return "MOON_WANING_CRESCENT"
	if phase <= 14: return "MOON_NEW_MOON"
	if phase <= 18: return "MOON_WAXING_CRESCENT"
	if phase <= 22: return "MOON_WAXING_HALF_MOON"
	return "MOON_WAXING_GIBBOUS"

static func native_header_groups(columns: int) -> Dictionary:
	return {"moods": columns >= 133, "resources": clampi((columns - 132) / 7, 0, 7)}

static func fortress_identity(state: Dictionary) -> String:
	var lines: PackedStringArray = []
	for key in ["fort_original_name", "fort_name"]:
		var value := str(state.get(key, ""))
		if not value.is_empty(): lines.append(value)
	var rank := int(state.get("fortress_rank", -1))
	if state.get("fortress_capital", false): lines.append("Capital")
	elif rank >= 0 and rank < 6:
		lines.append(["Outpost", "Hamlet", "Village", "Town", "City", "Metropolis"][rank])
	return "\n".join(lines)

static func fortress_calendar(year: int, year_tick: int) -> String:
	var days: int = clampi(year_tick, 0, 403199) / 1200
	var day := days % 28 + 1
	var month: int = days / 28
	var suffix := "th"
	if day < 11 or day > 13:
		suffix = {1:"st", 2:"nd", 3:"rd"}.get(day % 10, "th")
	# DF53.16 native calendar matrix: only Mid- joins directly to the season.
	return "%d%s %s\n%s%s\nYear %d" % [day, suffix,
		preload("res://scripts/session_controls.gd").MONTHS[month],
		["Early ", "Mid-", "Late "][month % 3],
		["Spring", "Summer", "Autumn", "Winter"][month / 3], year]

func _feedback_text() -> String:
	if not "state" in interaction: return ""
	if not interaction.state.pending.is_empty(): return "Waiting for Dwarf Fortress..."
	return str(interaction.state.history.front()) if not interaction.state.history.is_empty() else ""

func update_state(play: bool, in_fort: bool, state: Dictionary):
	var view: Vector2 = get_viewport().get_visible_rect().size
	active_launcher = owned_launcher()
	var state_key := [play, in_fort, interaction.construction_active, elevation_available(), interaction.tool_picker.selected,
		interaction.shell_context_visible(), menu_open(), labor_menu.visible, world.get_top_z(), world.is_live(),
		_feedback_text(), session_controls != null and session_controls.blocks_commands(), view,
		Preferences.effective_scale(view), Preferences.ui_scale, active_launcher, ui_host.allows_minimap_input() if ui_host!=null else false,
		interaction.priority.value, interaction.marker_only, interaction.mining_mode, tools.advanced, tools.family]
	# The caller mutates one session dictionary in place; keep a copy for the comparison.
	if state_key == _state_key and state == session:
		if entered: layout(logical_view_size()) # Container sizes settle over frames.
		return
	_state_key = state_key
	state_pass_count += 1
	enabled = play
	entered = in_fort
	session = state.duplicate(true)
	visible = entered
	minimap_layer.visible=entered and not native_help.visible
	# Only the captured alert-group popup opts into map overdraw. Other panels
	# retain their previous composition until their native behavior is measured.
	minimap_layer.layer=11 if ui_host!=null and is_instance_valid(ui_host.active) and ui_host.active.has_method("allows_minimap_input") and ui_host.active.allows_minimap_input() else 2
	# Native Options retains the map above its frame; input stays blocked below.
	if native_options != null and native_options.visible: minimap_layer.layer=21
	if not entered:
		native_help.reset()
		minimap.set_allowed(false)
		minimap.data = {}
		settings.hide()
		game_menu.hide()
		help_panel.hide()
		labor_menu.hide()
		if ui_host != null: ui_host.set_overlay_blocked(false)
		notification_rail.update_groups({}, false)
		red_alert.update_state({},false)
		return
	if not enabled or interaction.construction_active or menu_open(): labor_menu.hide()
	var blocked: bool = not enabled or interaction.construction_active or menu_open() or labor_menu.visible
	minimap.set_allowed(enabled and not menu_open() and not labor_menu.visible and (ui_host.allows_minimap_input() if ui_host!=null else not interaction.construction_active))
	notification_rail.visible = Availability.allows_launcher("Reports")
	notification_rail.update_groups(state if notification_rail.visible else {}, not blocked and notification_rail.visible)
	red_alert.update_state(state if Availability.allows_launcher("Reports") else {},not blocked and Availability.allows_launcher("Reports"))
	if not interaction.construction_active: active_launcher = ""
	for key in navigation:
		var b = navigation[key]
		b.visible = Availability.allows_launcher(key)
		if key == "Petitions": b.visible = b.visible and bool(state.get("petition", {}).get("can_review", false))
		b.disabled = bool(b.get_meta("unsupported", false)) or ((not enabled or interaction.construction_active) if b.get_meta("utility", false) else blocked)
		if key == active_launcher: b.disabled = not enabled or menu_open() or labor_menu.visible
		set_icon_active(b, (key == "Labor" and labor_menu.visible) or key == active_launcher or (not interaction.construction_active and interaction.tool_picker.selected in Interaction.TOOL_FAMILIES.get(key, [])))
		if key == active_launcher:
			var lower = ui.texture("BUTTON_LOWER_MENU")
			if lower != null: b.icon = lower
		if key in tools.FAMILIES and not blocked and (interaction.tool_picker.selected in Interaction.TOOL_FAMILIES[key] or (interaction.tool_picker.selected in Interaction.BLUEPRINT_TOOLS and tools.family == key)):
			var lower = ui.texture("BUTTON_LOWER_MENU")
			if lower != null: b.icon = lower
	pause.disabled = blocked or not world.is_live()
	play_button.disabled = pause.disabled
	settings_button.disabled = not entered
	level_down.disabled = not enabled or not elevation_available()
	level_up.disabled = not enabled or not elevation_available()
	heading.text = fortress_identity(state) if state.get("fortress_valid", false) else ""
	var moon_art := native_moon_art(int(state.get("moon_phase", -1))) if state.get("fortress_valid", false) else ""
	moon.texture = ui.texture(moon_art) if not moon_art.is_empty() else null
	date.text = fortress_calendar(int(state.get("year", 0)), int(state.get("year_tick", 0))) if state.get("fortress_valid", false) else ""
	pause.icon = ui.texture("BUTTON_PAUSE_ACTIVE" if state.get("paused", false) else "BUTTON_PAUSE_INACTIVE")
	play_button.icon = ui.texture("BUTTON_PLAY_INACTIVE" if state.get("paused", false) else "BUTTON_PLAY_ACTIVE")
	summary = state.get("fortress_summary", {})
	var has_summary: bool = summary.get("available", false)
	population.text = "Pop\n\n%d" % int(summary.population) if has_summary else ""
	var counts: Array = summary.get("stress_counts", [])
	for index in 7:
		mood_counts[index].text = str(counts[6 - index]) if summary.get("stress_available", false) and counts.size() == 7 else ""
	var stocks: Array = summary.get("resource_counts", [])
	for index in 7:
		resource_counts[index].text = native_resource_count(int(stocks[index]), int(summary.get("bookkeeper_precision", -1))) if has_summary and summary.get("resources_available", false) and stocks.size() == 7 else ""
		resource_counts[index].add_theme_color_override("font_color", Color8(160,160,160) if resource_counts[index].text == "None" else Color.WHITE)
	level_picker.visible = has_summary
	level_picker.editable = enabled and elevation_available()
	if has_summary:
		level.text = "Elevation %d" % (world.get_top_z() + int(summary.elevation_offset))
		level_picker.set_block_signals(true)
		level_picker.min_value = int(summary.elevation_offset)
		level_picker.max_value = int(summary.elevation_offset) + int(summary.level_count) - 1
		level_picker.set_value_no_signal(world.get_top_z() + int(summary.elevation_offset))
		level_picker.set_block_signals(false)
		level_down.disabled = not enabled or not elevation_available() or world.get_top_z() <= 0
		level_up.disabled = not enabled or not elevation_available() or world.get_top_z() >= int(summary.level_count) - 1
	else:
		level.text = "" # Raw model Z is not a native elevation caption.
	if "state" in interaction: command_feedback.text = _feedback_text()
	command_feedback.visible = not interaction.construction_active and not menu_open() and not labor_menu.visible
	tools.refresh()
	tools.visible = not blocked and interaction.tool_picker.selected not in Interaction.INSPECT_TOOLS
	interaction.panel.visible = enabled and not interaction.construction_active and not menu_open() and not labor_menu.visible and interaction.shell_context_visible()
	interaction.update_shell_context(view)
	if ui_host != null: ui_host.set_overlay_blocked(menu_open() or labor_menu.visible)
	apply_ui_scale()
	layout(logical_view_size())

func set_icon_active(button: Button, active: bool):
	if not button.has_meta("native_normal"): return
	var texture = button.get_meta("native_active") if active else null
	button.icon = texture if texture != null else button.get_meta("native_normal")

func blocks_camera() -> bool:
	return visible and (menu_open() or labor_menu.visible)

func layout(view: Vector2):
	native_help.layout(view)
	var key := [view, moon.texture != null, top.get_combined_minimum_size(), playback.size, actions.size,
		tools.size, information.size, labor_menu.size, command_feedback.size, settings.size, summary.get("available",false),
		summary.get("stress_available",false), hash(summary.get("resource_counts",[]))]
	if key == _layout_key: return
	_layout_key = key
	layout_count += 1
	var columns := int(view.x / 8)
	var x_remainder := floori(fposmod(view.x, 8) / 2)
	status_panel.position = Vector2(128 + x_remainder, floori(fposmod(view.y,12)/2))
	status_panel.size = Vector2(maxf(0, (columns - 53) * 8), 48)
	# Native DF53.16 text-cell anchors; width fixtures cover columns114..200.
	heading.position = Vector2(16, 0)
	heading.custom_minimum_size.x = 160
	heading.size = Vector2(160, 36)
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	population.position = Vector2(176, 0)
	population.size = Vector2(24, 36)
	moods.position = Vector2(208, 0)
	resources.position = Vector2(464, 0)
	navigation["Stocks"].position = Vector2((mini(66, columns - 68) - 17) * 8, 6)
	date.position = Vector2((columns - 69) * 8, 0)
	date.size = Vector2(128, 36)
	var groups := native_header_groups(columns)
	resources.visible = groups.resources > 0 and summary.get("available", false)
	for index in 7: resources.get_child(index).visible = index < groups.resources
	resources.reset_size()
	date.visible = columns >= 114
	moon.position = date.position + Vector2(-40, 2)
	moon.size = Vector2(32, 32)
	moon.visible = date.visible and moon.texture != null
	moods.visible = groups.moods and summary.get("stress_available", false)
	moods.reset_size()
	information.position = Vector2(4, view.y - information.size.y - 4)
	labor_menu.position = Vector2(4, information.position.y - labor_menu.size.y - 8)
	command_feedback.position = Vector2(8, information.position.y - command_feedback.size.y - 8)
	command_feedback.size.x = minf(300, view.x * 0.3)
	red_alert.position = Vector2(int(int(view.x)%8/2),72+int(int(view.y)%12/2))
	alerts.position = Layout.notification_rect(view).position
	navigation["Reports"].position = Vector2.ZERO
	navigation["Petitions"].position = Vector2(40, 88)
	notification_rail.custom_minimum_size = Vector2(40, maxf(80, Layout.notification_rect(view).size.y))
	var action_y := information.position.y - actions.size.y - 8 if view.x < 800 else view.y - actions.size.y - 8
	actions.position = Vector2(maxf(8, (view.x - actions.size.x) / 2), action_y)
	var tool_anchor: float = actions.position.x
	if navigation.has(tools.family): tool_anchor += navigation[tools.family].position.x
	var tool_scale: float = minf(1.0, (view.x - 16) / maxf(1.0, tools.size.x))
	tools.scale = Vector2.ONE * tool_scale
	tools.position = Vector2(clampf(tool_anchor, 8, maxf(8, view.x - tools.size.x * tool_scale - 8)), actions.position.y - tools.size.y * tool_scale - 2)
	minimap.visible = Layout.has_minimap(view)
	var overview_width := Layout.minimap_width(view)
	minimap.custom_minimum_size = Vector2(overview_width, overview_width)
	minimap.size=minimap.custom_minimum_size
	minimap_panel.reset_size()
	minimap_panel.position = Vector2(view.x - 200, floori(fposmod(view.y,12)/2))
	minimap.position=minimap_panel.position+Vector2(8,0)
	playback.position = Vector2((columns - 33) * 8 + x_remainder, floori(fposmod(view.y,12)/2))
	settings.size = Vector2(minf(420, view.x - 32), minf(520, view.y - 88))
	settings.position = Vector2(maxf(8, view.x - settings.size.x - 24), 76)
	game_menu.position = Vector2(maxf(8, view.x - game_menu.size.x - 24), 76)
	help_panel.position = Vector2(maxf(8, view.x - help_panel.size.x - 24), 76)


static func info_rect(view: Vector2) -> Rect2:
	return Layout.info_rect(view)

func native_frame() -> StyleBox:
	var texture: Texture2D = ui.texture("HOVER_RECTANGLE")
	if texture == null:
		var fallback := StyleBoxFlat.new()
		fallback.bg_color = Color("1c1c1c")
		return fallback
	var result := StyleBoxTexture.new()
	result.texture = texture
	for side in [SIDE_LEFT, SIDE_RIGHT]: result.set_texture_margin(side, 8)
	for side in [SIDE_TOP, SIDE_BOTTOM]: result.set_texture_margin(side, 12)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: result.set_content_margin(side, 12)
	return result

func logical_view_size() -> Vector2:
	return get_viewport().get_visible_rect().size / ui_scale_value()

func ui_scale_value() -> float:
	return Preferences.effective_scale(get_viewport().get_visible_rect().size)

func notification_rect() -> Rect2:
	return Layout.notification_rect(logical_view_size())

func elevation_rect() -> Rect2:
	return Layout.elevation_rect(logical_view_size(), minimap_panel.get_rect().end.y)

func apply_ui_scale():
	var factor := ui_scale_value()
	scale = Vector2(factor, factor)
	minimap_layer.scale=scale
	root_control.size = logical_view_size()
	scale_note.text = "" if is_equal_approx(factor, Preferences.ui_scale) else "Fits this window at %d%%" % roundi(factor * 100)
	scale_note.visible = not scale_note.text.is_empty()

func set_ui_scale_percent(value: float):
	Preferences.ui_scale = clampf(value / 100.0, 0.75, 2.0)
	scale_picker.set_value_no_signal(Preferences.ui_scale * 100.0)
	apply_ui_scale()
	_layout_key.clear()
	layout(logical_view_size())
	save_preferences()

func save_preferences():
	var result := Preferences.save_preferences()
	if result != OK: scale_note.text = "Could not save presentation settings"

func section_title(parent: Node, title: String):
	var label := Label.new()
	label.text = title
	parent.add_child(label)

func labeled_control(parent: Node, title: String, control: Control):
	var row := HBoxContainer.new()
	parent.add_child(row)
	section_title(row, title)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)

func menu_open() -> bool:
	return settings.visible or game_menu.visible or help_panel.visible or (native_options != null and native_options.visible)

func toggle_game_menu():
	if not entered: return
	settings.hide()
	help_panel.hide()
	game_menu.visible = not game_menu.visible
	sync_menu_gate()

func toggle_help():
	if not entered: return
	settings.hide()
	game_menu.hide()
	help_panel.visible = not help_panel.visible
	sync_menu_gate()

func close_menus():
	settings.hide()
	game_menu.hide()
	help_panel.hide()
	labor_menu.hide()
	sync_menu_gate()

func sync_menu_gate():
	layer = 20 if menu_open() else 1
	if ui_host != null: ui_host.set_overlay_blocked(menu_open() or labor_menu.visible)
	else: interaction.cancel_selection()

func _input(event: InputEvent):
	if visible and (settings.visible or game_menu.visible or help_panel.visible) and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menus()
		get_viewport().set_input_as_handled()
