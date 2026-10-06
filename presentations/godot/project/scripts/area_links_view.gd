extends PanelContainer
signal pick_requested(give: bool)
signal unlink_requested(row: Dictionary)
signal more_requested
signal done
var art = preload("res://scripts/original_ui.gd").new()
var body: Control
var prompt: Label
var close: Button
var add_buttons: Array[Button] = []
var scroll: ScrollContainer
var rows_box: VBoxContainer
var cached_rows: Array = []

func configure(source) -> void:
	art.configure(source); theme = art.theme; texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body = Control.new(); body.custom_minimum_size = Vector2(312,396); add_child(body)
	for index in 2:
		var button := icon_button("STOCKPILE_CONNECTIONS_ADD_GIVE_LINK" if index == 0 else "STOCKPILE_CONNECTIONS_ADD_TAKE_LINK")
		button.position = Vector2(index * 32,0)
		button.pressed.connect(func(): pick_requested.emit(index == 0))
		body.add_child(button); add_buttons.append(button)
	prompt = Label.new(); prompt.position = Vector2(0,0); prompt.size = Vector2(208,36)
	prompt.add_theme_font_size_override("font_size",12); body.add_child(prompt)
	close = Button.new(); close.position = Vector2(216,0); close.size = Vector2(96,36)
	close.add_theme_font_size_override("font_size",12)
	var style := art.make_style("HORIZONTAL_OPTION_REMOVE",8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	for state in ["normal","hover","pressed"]: close.add_theme_stylebox_override(state,style)
	close.pressed.connect(func(): done.emit()); body.add_child(close)
	scroll = ScrollContainer.new(); scroll.position = Vector2(0,72); scroll.size = Vector2(312,324)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	rows_box = VBoxContainer.new(); rows_box.add_theme_constant_override("separation",0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(rows_box)
	scroll.get_v_scroll_bar().value_changed.connect(func(value):
		var bar := scroll.get_v_scroll_bar()
		if value > 0 and value + bar.page >= bar.max_value - 36: more_requested.emit())

func icon_button(token: String) -> Button:
	var button := Button.new(); button.size = Vector2(32,36)
	for state in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var icon := TextureRect.new(); icon.size = Vector2(32,36); icon.texture = art.texture(token)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
	return button

func display(rows: Array, picking: bool, give: bool, enabled: bool) -> void:
	body.custom_minimum_size.y = 96 if picking else 396
	prompt.visible = picking
	prompt.text = "Select a stockpile or\nworkshop to " + ("give to." if give else "take from.")
	close.text = "Cancel" if picking else "Done"
	for button in add_buttons: button.visible = not picking; button.disabled = not enabled
	scroll.visible = not picking
	if cached_rows != rows:
		cached_rows = rows.duplicate(true)
		for child in rows_box.get_children(): rows_box.remove_child(child); child.queue_free()
		for row in rows:
			var line := Control.new(); line.custom_minimum_size = Vector2(0,36); rows_box.add_child(line)
			var token := "STOCKPILE_CONNECTIONS_" + ("WORKSHOP_" if int(row.kind) == 2 else "") + ("GIVE_LINK" if int(row.direction) == 1 else "TAKE_LINK")
			var direction := icon_button(token); direction.mouse_filter = Control.MOUSE_FILTER_IGNORE; line.add_child(direction)
			var label := Label.new(); label.position = Vector2(56,0); label.size = Vector2(216,36)
			label.text = str(row.name); label.clip_text = true; label.tooltip_text = str(row.name)
			label.add_theme_font_size_override("font_size",12); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; line.add_child(label)
			var remove := icon_button("STOCKPILE_CONNECTIONS_REMOVE")
			remove.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE); remove.offset_left = -32; remove.offset_right = 0
			remove.pressed.connect(func(): unlink_requested.emit(row)); line.add_child(remove)
	for line in rows_box.get_children(): line.get_child(2).disabled = not enabled
