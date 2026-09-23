extends HBoxContainer
# Client-owned designation options; the bridge receives values, never UI state.
const GROUPS = {"Dig":[1,15,9,2,16], "Chop trees":[10], "Gather plants":[12], "Smooth":[6,7,18,17], "Remove":[8]}
const ART = {1:"BUTTON_DIG_DIG_INACTIVE",15:"BUTTON_DIG_STAIRS_INACTIVE",9:"BUTTON_DIG_RAMP_INACTIVE",2:"BUTTON_DIG_CHANNEL_INACTIVE",16:"BUTTON_DIG_REMOVE_STAIRS_RAMPS_INACTIVE",10:"BUTTON_DES_CHOP_INACTIVE",12:"BUTTON_DES_GATHER_INACTIVE",6:"BUTTON_DES_SMOOTH_SMOOTH_INACTIVE",7:"BUTTON_DES_SMOOTH_ENGRAVE_INACTIVE",18:"BUTTON_DES_SMOOTH_TRACK_INACTIVE",17:"BUTTON_DES_SMOOTH_FORTIFY_INACTIVE",8:"BUTTON_DES_ERASE"}
var hud
var advanced := false
var family := "Dig"
var _signature: Array = []
var buttons: Dictionary = {}

func refresh() -> void:
	var interaction = hud.interaction
	var selected: int = interaction.tool_picker.selected
	for group in GROUPS:
		if selected in GROUPS[group]: family = group
	var signature := [selected, family, advanced, interaction.priority.value, interaction.marker_only, interaction.mining_mode]
	if signature == _signature: return
	_signature = signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	add_theme_constant_override("separation", 24)
	var operations := _group()
	for index in GROUPS[family]:
		var id: int = index
		var button := _icon_button(operations, interaction.TOOLS[id], ART[id], func(): hud.choose_tool(id)) as Button
		if id == 18: button.tooltip_text = "Carve track: drag between endpoints; change elevation with PgUp/PgDn to follow ramps"
		if id == 15: button.tooltip_text = "Stairs: drag and change elevation with PgUp/PgDn before releasing"
		button.set_meta("tool_index", id)
		buttons[id] = button
		hud.set_icon_active(button, selected == id)
	if family == "Remove":
		theme = hud.ui.theme
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return
	var expand := _icon_button(self, "Hide advanced options" if advanced else "Show advanced options", "BUTTON_CLOSE_LEFT" if advanced else "BUTTON_OPEN_RIGHT", func():
		advanced = not advanced
		refresh()) as Button
	expand.name = "Advanced"
	if advanced:
		if family == "Dig":
			var modes := _group()
			var mode_art := ["ALL", "AUTO", "ONLY_ORE_GEM", "ONLY_GEM"]
			var mode_names := ["All", "Automining veins", "Ores/gems only", "Gems only"]
			for index in 4:
				var mode: int = index
				var button := _icon_button(modes, mode_names[index], "BUTTON_DIG_MODE_"+mode_art[index]+"_INACTIVE", func():
					interaction.mining_mode = mode
					refresh()) as Button
				hud.set_icon_active(button, interaction.mining_mode == mode)
		var priorities := _group()
		for value in range(1,8):
			var p: int = value
			var button := _icon_button(priorities, "Priority %d%s" % [p, " (highest)" if p == 1 else (" (lowest)" if p == 7 else "")], "BUTTON_PRIORITY_%d_INACTIVE" % p, func():
				interaction.priority.value = p
				interaction.set_show_priorities(true)
				refresh()) as Button
			hud.set_icon_active(button, int(interaction.priority.value) == p)
		var plans := _group()
		var marker := _icon_button(plans, "Blueprint only", "BUTTON_DES_BLUEPRINT_INACTIVE", func():
			interaction.marker_only = not interaction.marker_only
			refresh()) as Button
		hud.set_icon_active(marker, interaction.marker_only)
		var activate := _icon_button(plans, "Convert blueprint to standard", "BUTTON_DES_FROM_BLUEPRINT_INACTIVE", func(): hud.choose_tool(19)) as Button
		hud.set_icon_active(activate, selected == 19)
		var hold := _icon_button(plans, "Convert standard to blueprint", "BUTTON_DES_TO_BLUEPRINT_INACTIVE", func(): hud.choose_tool(20)) as Button
		hud.set_icon_active(hold, selected == 20)
	theme = hud.ui.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reset_size()

func _group() -> HBoxContainer:
	var panel := PanelContainer.new()
	var style = hud.ui.compact_panel() if hud.world.has_method("ui_texture") else StyleBoxEmpty.new()
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side, 0)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",0)
	panel.add_child(row)
	return row

func _icon_button(parent: Node, title: String, art: String, callback: Callable) -> Button:
	var button: Button = hud.icon_button(parent, title, art, callback)
	if button.icon != null:
		button.custom_minimum_size.x = maxf(32, button.icon.get_width())
	return button
