extends Control
# Native three-column settings layout; every state and leaf caption is observed.
var art = preload("res://scripts/original_ui.gd").new()
var state
var columns: Array[VBoxContainer] = []
var scrolls: Array[ScrollContainer] = []
var headers: Array[Button] = []
var toggles: Dictionary = {}
var search: LineEdit
var rendered_rows: Array = [[],[],[]]
var category_art: Dictionary = {}
var row_cache: Array = [{},{},{}]

func configure(source, model) -> void:
	state = model; art.configure(source); theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(928,680)
	var data: Dictionary = preload("res://scripts/area_menu_data.gd").read()
	for row in data.categories: category_art[str(row.key)] = str(row.icon)
	for column in 3:
		var x: float = [8,312,592][column]
		var width: float = [280,256,328][column]
		for value in [2,1]:
			var button := Button.new(); button.text = "All" if value == 2 else "None"
			button.position = Vector2(x + (0 if value == 2 else 48),0); button.size = Vector2(40,36)
			button.add_theme_font_size_override("font_size",12)
			var header_style := art.make_style("HORIZONTAL_OPTION_CONFIRM" if value == 2 else "HORIZONTAL_OPTION_REMOVE",8)
			header_style.set_texture_margin(SIDE_TOP,12); header_style.set_texture_margin(SIDE_BOTTOM,12)
			for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: header_style.set_content_margin(side,0)
			for style in ["normal","hover","pressed","disabled"]: button.add_theme_stylebox_override(style,header_style)
			button.pressed.connect(func(): state.edit(column,[4,3,2][column],value))
			add_child(button); headers.append(button)
		var scroll := ScrollContainer.new(); scroll.position = Vector2(x,48)
		scroll.size = Vector2(width,576); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll); scrolls.append(scroll)
		var bar := scroll.get_v_scroll_bar()
		bar.custom_minimum_size.x = 16
		var track := art.make_style("SCROLLBAR",0)
		track.set_texture_margin(SIDE_TOP,12); track.set_texture_margin(SIDE_BOTTOM,12)
		var thumb := art.make_style("SCROLLBAR_SMALL_SCROLLER",0)
		thumb.set_texture_margin(SIDE_TOP,12); thumb.set_texture_margin(SIDE_BOTTOM,12)
		bar.add_theme_stylebox_override("scroll",track)
		bar.add_theme_stylebox_override("scroll_focus",track)
		for style in ["grabber","grabber_highlight","grabber_pressed"]: bar.add_theme_stylebox_override(style,thumb)
		var list := VBoxContainer.new(); list.add_theme_constant_override("separation",0)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list); columns.append(list)
		scroll.get_v_scroll_bar().value_changed.connect(func(value):
			if value > 0 and value + bar.page >= bar.max_value - 36: state.more(column))
	for index in 2:
		var key: String = ["organic","inorganic"][index]
		var button := Button.new(); button.position = Vector2(176 + index * 40,0); button.size = Vector2(32,36)
		button.pressed.connect(func():
			for row in state.rows[0]:
				if str(row.key) == key: state.select(0,row))
		for style in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(style,StyleBoxEmpty.new())
		var icon := TextureRect.new(); icon.name = "Icon"; icon.size = Vector2(32,36)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
		add_child(button); toggles[key] = button
	search = LineEdit.new(); search.position = Vector2(696,0); search.size = Vector2(224,36)
	search.placeholder_text = "..."; search.max_length = 128
	var field := art.make_style("UNIT_SELECTOR_UNASSIGNED",8)
	field.set_texture_margin(SIDE_TOP,12); field.set_texture_margin(SIDE_BOTTOM,12)
	field.set_content_margin(SIDE_TOP,0); field.set_content_margin(SIDE_BOTTOM,0)
	field.set_content_margin(SIDE_LEFT,8); field.set_content_margin(SIDE_RIGHT,8)
	field.draw_center = false
	search.add_theme_stylebox_override("normal",field); search.add_theme_stylebox_override("focus",field)
	search.right_icon = art.texture("WORK_ORDERS_DETAILS")
	search.size.y = 36
	search.text_submitted.connect(func(value): state.search(value))
	search.text_changed.connect(func(value): state.queue_search(value))
	add_child(search)
	state.changed.connect(render)
	render()

func row_style(value: int, selected: bool) -> StyleBox:
	var token := "BUTTON_CATEGORY_RECTANGLE"
	if value == 1: token += "_OFF"
	elif value == 2: token += "_ON"
	if selected: token += "_SELECTED"
	var style := art.make_style(token,8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	return style

func render() -> void:
	if state == null: return
	var busy: bool = state.busy()
	for index in headers.size():
		var column := index / 2
		headers[index].visible = column != 1 or not state.category in ["coins","corpses","wood"]
		headers[index].disabled = busy or (column == 1 and state.category.is_empty()) or (column == 2 and state.leaf.is_empty())
	search.editable = not state.mutating and not state.failed and not state.leaf.is_empty()
	if search.text != state.search_text:
		# Normalize while typing without moving the insertion point or dropping
		# selection. Uppercase expansion can change string length.
		var caret := search.text.left(search.caret_column).to_upper().length()
		var selected := search.has_selection()
		var start := search.text.left(search.get_selection_from_column()).to_upper().length() if selected else 0
		var end := search.text.left(search.get_selection_to_column()).to_upper().length() if selected else 0
		search.set_text(state.search_text)
		search.caret_column = mini(caret,search.text.length())
		if selected: search.select(start,end)
	for key in toggles:
		var observed := false
		for row in state.rows[0]:
			if str(row.key) == key:
				observed = true
				toggles[key].get_node("Icon").texture = art.texture("CUSTOM_STOCKPILE_" + str(key).to_upper() + ("_ON" if int(row.state) == 2 else "_OFF"))
		toggles[key].disabled = busy or not observed
	for column in 3:
		var snapshot := {"rows":state.rows[column],"category":state.category,"subcategory":state.subcategory}
		if row_cache[column] == snapshot:
			for line in columns[column].get_children():
				for control in line.get_children():
					if control is Button: control.disabled = busy
			continue
		row_cache[column] = snapshot.duplicate(true)
		# Preserve scroll positions while applying authoritative new row states.
		var previous_scroll: int = scrolls[column].scroll_vertical
		for child in columns[column].get_children(): columns[column].remove_child(child); child.queue_free()
		rendered_rows[column] = []
		for row in state.rows[column]:
			if column == 0 and int(row.kind) != 1: continue
			var line := Control.new(); line.custom_minimum_size = Vector2(0,36)
			columns[column].add_child(line)
			var button := Button.new(); button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			button.disabled = busy
			var selected: bool = str(row.key) == state.category or str(row.key) == state.subcategory
			for key in ["normal","disabled"]: button.add_theme_stylebox_override(key,row_style(int(row.state),selected))
			for key in ["hover","pressed"]: button.add_theme_stylebox_override(key,row_style(int(row.state),true))
			button.pressed.connect(func(): state.select(column,row))
			line.add_child(button); rendered_rows[column].append(button)
			button.tooltip_text = str(row.label)
			var label := Label.new(); label.text = str(row.label)
			if not label.text.is_empty(): label.text = label.text.left(1).to_upper()+label.text.substr(1)
			label.position = Vector2(56 if column == 0 else 8,0)
			label.size = Vector2([208,208,312][column] - (48 if column == 0 else 0),36)
			label.add_theme_font_size_override("font_size",12); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.clip_text = true; label.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(label)
			if column == 0:
				var picture := TextureRect.new(); picture.texture = art.texture(category_art.get(str(row.key),""))
				picture.position = Vector2(2,2); picture.size = Vector2(32,32)
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(picture)
			if int(row.kind) in [1,2]:
				var toggle := Button.new(); toggle.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
				toggle.offset_left = -40; toggle.offset_right = -8; toggle.disabled = busy
				for key in ["normal","hover","pressed","disabled","focus"]: toggle.add_theme_stylebox_override(key,StyleBoxEmpty.new())
				var icon := TextureRect.new(); icon.size = Vector2(32,36)
				icon.texture = art.texture({1:"STOCKPILE_OFF",2:"STOCKPILE_ON",3:"STOCKPILE_PARTIAL"}.get(int(row.state),""))
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; toggle.add_child(icon)
				toggle.pressed.connect(func(): state.edit(column,1,1 if int(row.state) == 2 else 2,str(row.key)))
				line.add_child(toggle)
		scrolls[column].set_deferred("scroll_vertical",previous_scroll)
