extends Control
# Native stockpile type panel. Semantic requests and draft ownership stay in areas.gd.
signal preset_selected(preset: int)
signal control_selected(key: String)
const Data = preload("res://scripts/area_menu_data.gd")
var art = preload("res://scripts/original_ui.gd").new()
var data: Dictionary = Data.read()
var preset_buttons: Array[Button] = []
var controls: Dictionary = {}
var heading: Label
var warning: Label
var footer: Label

func configure(source) -> void:
	art.configure(source)
	theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(312, 432)
	mouse_filter = Control.MOUSE_FILTER_STOP
	heading = caption("", Vector2(8, 0), Vector2(264, 36))
	controls.rename = icon_button("UNIT_SHEET_CUSTOMIZE", Vector2(280, 0), "Rename")
	controls.rename.pressed.connect(func(): control_selected.emit("rename"))
	for index in data.presets.size():
		var row: Dictionary = data.presets[index]
		var point := Vector2((index / 10) * 112, 36 + (index % 10) * 36)
		var button := Button.new()
		button.position = point; button.size = Vector2(112, 36)
		button.flat = true; button.tooltip_text = str(row.label)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		add_child(button); preset_buttons.append(button)
		button.pressed.connect(func(): preset_selected.emit(int(row.preset)))
		var picture := TextureRect.new(); picture.name = "Icon"
		var frame := TextureRect.new(); frame.name = "Frame"
		frame.texture = art.texture("STOCKPILE_TYPE_INACTIVE"); frame.size = Vector2(32,36)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(frame)
		picture.texture = art.texture(str(row.icon).replace("STOCKPILE_ICON_", "STOCKPILE_ICON_SIGNLESS_")); picture.size = Vector2(32, 36)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(picture)
		var label := Label.new(); label.name = "Caption"; label.text = str(row.label)
		if label.text == "Bars and Blocks": label.text = "Bars and\nBlocks"
		if label.text == "Finished Goods": label.text = "Finished\nGoods"
		label.position = Vector2(40, 0); label.size = Vector2(72, 36)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(label)
	var positions := {"repaint":Vector2(248,36), "remove":Vector2(280,36),
		"links_only":Vector2(248,72), "links":Vector2(280,72), "containers":Vector2(280,108)}
	for row in data.stockpile_controls:
		var key := str(row.key)
		var button := icon_button(str(row.icon), positions[key], "")
		button.pressed.connect(func(): control_selected.emit(key))
		controls[key] = button
	footer = caption(str(data.text.stockpile_footer.label), Vector2(8,408), Vector2(304,12))
	warning = caption("Warning: stockpile has no type.", Vector2(8,420), Vector2(304,12))
	warning.add_theme_color_override("font_color", Color("ff8000"))

func panel_style() -> StyleBox:
	var style := art.make_style("HOVER_RECTANGLE", 8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	style.set_content_margin(SIDE_LEFT,6); style.set_content_margin(SIDE_RIGHT,6)
	style.set_content_margin(SIDE_TOP,10); style.set_content_margin(SIDE_BOTTOM,10)
	return style

func caption(text: String, point: Vector2, dimensions: Vector2) -> Label:
	var label := Label.new(); label.text = text; label.position = point; label.size = dimensions
	label.add_theme_font_size_override("font_size",12)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label)
	# Text assigned before inheriting the native bitmap font can retain the
	# default font minimum height; apply exact bounds after theme resolution.
	label.set_deferred("size",dimensions)
	return label

func icon_button(token: String, point: Vector2, hint: String) -> Button:
	var button := Button.new(); button.position = point; button.size = Vector2(32,36)
	button.tooltip_text = hint
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var icon := TextureRect.new(); icon.name = "Icon"; icon.texture = art.texture(token)
	icon.size = Vector2(32,36); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon); add_child(button)
	return button

func display(area: Dictionary, enabled: bool) -> void:
	heading.text = str(area.get("name", ""))
	var mask := int(area.get("categories", 0))
	warning.visible = mask == 0
	for index in preset_buttons.size():
		var button := preset_buttons[index]
		button.disabled = not enabled
		# The bridge reports category flags, not a remembered preset identity.
		# Highlight only the observed single category (or None), never infer All
		# from its importer-specific category mask or infer detailed filter state.
		var key := str(data.presets[index].get("key", ""))
		var selected := int(data.presets[index].preset) == 19 and mask == 0
		for category in data.categories:
			if str(category.key) == key and mask == (1 << int(category.bit)): selected = true
		button.get_node("Caption").add_theme_color_override("font_color", Color("00ff00") if selected and mask != 0 else Color("dddddd"))
		button.get_node("Frame").texture = art.texture("STOCKPILE_TYPE_ACTIVE" if selected else "STOCKPILE_TYPE_INACTIVE")
		button.modulate = Color.WHITE if enabled else Color(0.5,0.5,0.5)
	for button in controls.values():
		button.disabled = not enabled
		button.modulate = Color.WHITE if enabled else Color(0.5,0.5,0.5)
	controls.links_only.get_node("Icon").texture = art.texture("STOCKPILE_TAKE_FROM_LINKS_ONLY" if bool(area.get("links_only",false)) else "STOCKPILE_TAKE_FROM_ANYWHERE")
