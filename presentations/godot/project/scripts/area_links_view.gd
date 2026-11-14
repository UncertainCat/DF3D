extends PanelContainer
signal pick_requested(give: bool)
signal unlink_requested(row: Dictionary)
signal done
var art = preload("res://scripts/original_ui.gd").new()
var stockpile_only:=false
var body: Control
var prompt: Label
var close: Button
var add_buttons: Array[Button] = []
var scroll: ScrollContainer
var rows_box: VBoxContainer
var cached_rows: Array = []
var scrollbar = preload("res://scripts/area_location_scrollbar.gd").new()

func configure(source) -> void:
	art.configure(source); theme = art.theme; texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body = Control.new(); body.custom_minimum_size = Vector2(312,396); add_child(body)
	for index in 2:
		var button := icon_button(("STOCKPILE_CONNECTIONS_WORKSHOP_" if stockpile_only else "STOCKPILE_CONNECTIONS_") + ("ADD_GIVE_LINK" if index == 0 else "ADD_TAKE_LINK"))
		button.position = Vector2(index * 32,0)
		button.pressed.connect(func(): pick_requested.emit(index == 0))
		body.add_child(button); add_buttons.append(button)
	prompt = Label.new(); prompt.position = Vector2(0,0); prompt.size = Vector2(208,36)
	prompt.add_theme_font_size_override("font_size",12); body.add_child(prompt)
	if stockpile_only:
		prompt.add_theme_color_override("font_color",Color.WHITE);prompt.add_theme_constant_override("line_spacing",0)
	close = Button.new(); close.position = Vector2(216,0); close.size = Vector2(96,36)
	close.add_theme_font_size_override("font_size",12)
	if stockpile_only:
		for color in ["font_color","font_hover_color","font_pressed_color"]:close.add_theme_color_override(color,Color.WHITE)
	var style := art.make_style("HORIZONTAL_OPTION_REMOVE",8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	for state in ["normal","hover","pressed"]: close.add_theme_stylebox_override(state,style)
	close.pressed.connect(func(): done.emit()); body.add_child(close)
	scroll = ScrollContainer.new(); scroll.position = Vector2(0,72); scroll.size = Vector2(312,324)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rows_box = VBoxContainer.new(); rows_box.add_theme_constant_override("separation",0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(rows_box)
	body.add_child(scrollbar); scrollbar.configure(source)
	scrollbar.position = Vector2(296,72); scrollbar.size = Vector2(16,324); scrollbar.page = 9
	scrollbar.row_changed.connect(func(_first): _apply_scroll())
	visibility_changed.connect(func(): if not is_visible_in_tree(): scrollbar.dragging = false)
	scrollbar.hide()

func _apply_scroll() -> void:
	scroll.scroll_vertical = scrollbar.first * 36

func reset_scroll() -> void:
	scrollbar.set_rows(0); scrollbar.dragging = false; _apply_scroll()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not scroll.visible or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	var local: Vector2 = body.get_global_transform_with_canvas().affine_inverse() * event.position
	if not Rect2(0,72,312,324).has_point(local): return
	scrollbar.move_to(scrollbar.first + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1) * (9 if event.shift_pressed else 1))
	get_viewport().set_input_as_handled()

func icon_button(token: String) -> Button:
	var button := Button.new(); button.size = Vector2(32,36)
	for state in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var icon := TextureRect.new(); icon.size = Vector2(32,36); icon.texture = art.texture(token)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
	return button

func display(rows: Array, picking: bool, give: bool, enabled: bool) -> void:
	body.custom_minimum_size.y = 96 if picking else 396
	prompt.visible = picking
	prompt.text = ("Select a stockpile to\n" if stockpile_only else "Select a stockpile or\nworkshop to ") + ("give to." if give else "take from.")
	close.text = "Cancel" if picking else "Done"
	for button in add_buttons: button.visible = not picking; button.disabled = not enabled
	scroll.visible = not picking
	scrollbar.set_rows(rows.size(),scrollbar.first)
	scrollbar.visible = not picking and rows.size() > 9
	if picking: scrollbar.dragging = false
	scroll.size.x = 296 if rows.size() > 9 else 312
	if cached_rows != rows:
		cached_rows = rows.duplicate(true)
		for child in rows_box.get_children(): rows_box.remove_child(child); child.queue_free()
		for row in rows:
			var line := Control.new(); line.custom_minimum_size = Vector2(0,36); rows_box.add_child(line)
			var background := art.make_style("BUTTON_RECTANGLE",8)
			background.set_texture_margin(SIDE_TOP,12); background.set_texture_margin(SIDE_BOTTOM,12)
			background.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			line.draw.connect(func(): line.draw_style_box(background,Rect2(Vector2.ZERO,line.size)))
			line.resized.connect(line.queue_redraw)
			var token := ("STOCKPILE_CONNECTIONS_WORKSHOP_" if stockpile_only else "STOCKPILE_CONNECTIONS_") + ("GIVE_LINK" if int(row.direction) == 1 else "TAKE_LINK")
			var direction := icon_button(token); direction.mouse_filter = Control.MOUSE_FILTER_IGNORE; line.add_child(direction)
			var label := Label.new(); label.position = Vector2(56,0); label.size = Vector2(216,36)
			if stockpile_only:label.add_theme_color_override("font_color",Color.WHITE)
			label.text = str(row.name); label.clip_text = true; label.tooltip_text = str(row.name)
			label.add_theme_font_size_override("font_size",12); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; line.add_child(label)
			var remove := icon_button("STOCKPILE_CONNECTIONS_REMOVE")
			remove.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE); remove.offset_left = -40 if stockpile_only else -32; remove.offset_right = -8 if stockpile_only else 0
			remove.pressed.connect(func(): unlink_requested.emit(row)); line.add_child(remove)
	for line in rows_box.get_children():
		line.get_child(2).disabled = not enabled
		line.get_child(1).size.x = scroll.size.x-88
	_apply_scroll.call_deferred()
