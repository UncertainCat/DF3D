extends RefCounted
# One instance per controller: visibility remains its management polling gate.
signal destination_requested(destination: String)
const MAIN = ["Creatures", "Tasks", "Places", "Labor", "Work orders", "Nobles and administrators", "Objects", "Justice"]
const SUBTABS = {
	"Creatures": ["Residents", "Pets/Livestock", "Other", "Dead/Missing"],
	"Labor": ["Work Details", "Standing orders", "Kitchen", "Stone use"],
	"Places": ["Zones", "Locations", "Stockpiles", "Workshops", "Farm plots", "Siege engines"],
	"Objects": ["Artifacts", "Symbols", "Named objects", "Written content"],
	"Justice": ["Open cases", "Closed cases", "Cold cases", "Fortress guard", "Convicts", "Intelligence"]}

static func destination(caption: String) -> String:
	return str(SUBTABS[caption][0]) if SUBTABS.has(caption) else caption
var panel: PanelContainer
var body: Control
var main_tabs: HBoxContainer
var subtabs: HBoxContainer
var ui
var selected := "Residents"
var buttons: Dictionary = {}

func install(target: PanelContainer, source, destination: String):
	panel = target
	ui = preload("res://scripts/original_ui.gd").new()
	ui.configure(source)
	body = panel.get_child(0)
	panel.remove_child(body)
	panel.custom_minimum_size = Vector2.ZERO
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	# A horizontal scroll only appears at narrow window sizes; tabs never wrap
	# into an invented third hierarchy or force the frame outside the viewport.
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(tab_scroll)
	main_tabs = HBoxContainer.new()
	main_tabs.add_theme_constant_override("separation", 0)
	tab_scroll.add_child(main_tabs)
	subtabs = HBoxContainer.new()
	subtabs.add_theme_constant_override("separation", 0)
	box.add_child(subtabs)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	panel.theme = ui.theme
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var style: StyleBox
	var border: Texture2D = ui.texture("HOVER_RECTANGLE")
	if border != null:
		var original := StyleBoxTexture.new()
		original.texture = border
		original.set_texture_margin(SIDE_LEFT, 8)
		original.set_texture_margin(SIDE_RIGHT, 8)
		original.set_texture_margin(SIDE_TOP, 12)
		original.set_texture_margin(SIDE_BOTTOM, 12)
		style = original
	else:
		var fallback := StyleBoxFlat.new()
		fallback.bg_color = Color("1c1c1c")
		style = fallback
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 16)
	panel.add_theme_stylebox_override("panel", style)
	select(destination)

func tab_style(art: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ui.texture(art)
	style.set_texture_margin(SIDE_LEFT, 16)
	style.set_texture_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_LEFT, 16)
	style.set_content_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_TOP, 4)
	style.set_content_margin(SIDE_BOTTOM, 4)
	return style

func add_tab(parent: HBoxContainer, caption: String, active: bool, secondary := false):
	var button := Button.new()
	button.text = caption
	button.disabled = false
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	var prefix := "SHORT_SUBTAB" if secondary else "SHORT_TAB"
	var style := tab_style(prefix + ("_SELECTED" if active else ""))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("1c1c1c") if active else Color("dddddd"))
	button.pressed.connect(func(): destination_requested.emit(destination(caption)))
	button.visible = preload("res://scripts/ui_availability.gd").allows(destination(caption))
	parent.add_child(button)
	buttons[caption] = button

func select(destination: String):
	selected = destination
	buttons.clear()
	for row in [main_tabs, subtabs]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	var primary := destination
	for group in SUBTABS:
		if destination in SUBTABS[group]: primary = group
	for caption in MAIN: add_tab(main_tabs, caption, caption == primary)
	subtabs.visible = SUBTABS.has(primary)
	for caption in SUBTABS.get(primary, []): add_tab(subtabs, caption, caption == destination, true)

func layout(view: Vector2):
	var factor: float = preload("res://scripts/presentation_settings.gd").effective_scale(view)
	panel.get_parent().scale = Vector2(factor, factor)
	var rect: Rect2 = preload("res://scripts/hud_layout.gd").info_rect(view / factor)
	panel.position = rect.position
	panel.size = rect.size
