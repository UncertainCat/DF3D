extends Control
# Native three-column settings layout; every state and leaf caption is observed.
var art = preload("res://scripts/original_ui.gd").new()
var state
var columns: Array[VBoxContainer] = []
var scrolls: Array[ScrollContainer] = []
var native_scrolls: Array = []
var headers: Array[Button] = []
var toggles: Dictionary = {}
var search: LineEdit
var rendered_rows: Array = [[],[],[]]
var category_art: Dictionary = {}
var row_cache: Array = [{},{},{}]
var retained_scroll: Array[int] = [0,0,0]
var scroll_generation: Array[int] = [0,0,0]
var page_rows := 16
var column_widths := [280,256,328]
var layout_pending: Array[bool] = [false,false,false]

func restore_scroll(column: int, generation: int, offset: int) -> void:
	# The new VBox must receive its minimum size before ScrollContainer can
	# admit the old offset. Setting it during rebuild clamps against old bounds.
	await get_tree().process_frame
	await get_tree().process_frame
	if scroll_generation[column] == generation:
		scrolls[column].scroll_vertical = offset
		layout_pending[column] = false

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
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		var native_bar = preload("res://scripts/area_location_scrollbar.gd").new()
		add_child(native_bar); native_bar.configure(source)
		native_bar.position = Vector2(x + width - 16,44)
		native_bar.size = Vector2(16,576); native_bar.page = 16
		native_bar.row_changed.connect(func(first):
			# Explicit input supersedes restoration from an older page/layout.
			scroll_generation[column] += 1; layout_pending[column] = false
			retained_scroll[column] = first * 36
			scroll.scroll_vertical = first * 36)
		native_scrolls.append(native_bar)
		var list := VBoxContainer.new(); list.add_theme_constant_override("separation",0)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list); columns.append(list)
		scroll.get_v_scroll_bar().value_changed.connect(func(value):
			if int(state.receipts[column].get("settings_count",-1)) < 0:
				var bar := scroll.get_v_scroll_bar()
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
	search.add_theme_font_size_override("font_size",12)
	search.placeholder_text = "..."; search.max_length = 0
	var field := art.make_style("UNIT_SELECTOR_UNASSIGNED",8)
	field.set_texture_margin(SIDE_TOP,12); field.set_texture_margin(SIDE_BOTTOM,12)
	field.set_content_margin(SIDE_TOP,0); field.set_content_margin(SIDE_BOTTOM,0)
	field.set_content_margin(SIDE_LEFT,16); field.set_content_margin(SIDE_RIGHT,8)
	field.draw_center = false
	for style in ["normal","focus","read_only"]: search.add_theme_stylebox_override(style,field)
	search.right_icon = art.texture("WORK_ORDERS_DETAILS")
	search.size.y = 36
	search.text_submitted.connect(func(value): state.search(value))
	search.text_changed.connect(func(value): state.queue_search(value))
	add_child(search)
	state.changed.connect(render)
	render()

func layout(view: Vector2, available_height := INF, available_width := INF) -> void:
	# Native settings keeps the first two columns fixed and gives the remaining
	# width to items. Rows occupy three 12px cells; sixteen cells are reserved.
	var next_width := maxi(40,floori(view.x / 8) * 8 - 872)
	if is_finite(available_width): next_width = mini(next_width,maxi(40,floori((available_width-612)/8)*8))
	var height := maxf(96,minf(view.y-120,available_height))
	var next_page := mini(maxi(1,(floori(view.y / 12)-16)/3),maxi(1,floori((height-48)/36)))
	if next_width == column_widths[2] and next_page == page_rows and is_equal_approx(custom_minimum_size.y,height): return
	column_widths[2] = next_width; page_rows = next_page; state.viewport_rows = page_rows
	custom_minimum_size = Vector2(600 + next_width,height)
	search.size.x = maxf(0,next_width - 104)
	search.visible = next_width > 104
	for column in 3:
		scrolls[column].size.y = page_rows * 36
		native_scrolls[column].size.y = page_rows * 36
		native_scrolls[column].page = page_rows
		native_scrolls[column].position.x = scrolls[column].position.x + column_widths[column] - 16
	row_cache = [{},{},{}]
	render()

static func leaf_caption(value: String, cells: int) -> String:
	# Native screen captures: narrow positive widths clip; four or more cells
	# use three literal dots. Negative native widths leave the string intact.
	if cells < 0 or value.length() <= cells: return value
	return value.left(cells) if cells < 4 else value.left(cells-3)+"..."

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
	if state.area.is_empty(): retained_scroll = [0,0,0]
	var busy: bool = state.busy()
	for index in headers.size():
		var column := index / 2
		headers[index].visible = column != 1 or not state.category in ["coins","corpses","wood"]
		headers[index].disabled = busy or (column == 1 and state.category.is_empty()) or (column == 2 and state.leaf.is_empty())
	search.editable = not state.mutating and not state.failed and not state.leaf.is_empty()
	if search.text != state.search_text:
		# Normalize while typing, preserving the corresponding insertion point and
		# selection after native input filtering removes unsupported characters.
		var caret: int = state.normalize_search(search.text.left(search.caret_column)).length()
		var selected := search.has_selection()
		var start: int = state.normalize_search(search.text.left(search.get_selection_from_column())).length() if selected else 0
		var end: int = state.normalize_search(search.text.left(search.get_selection_to_column())).length() if selected else 0
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
		var total: int = state.rows[column].size()
		if column == 0:
			total = 0
			for row in state.rows[0]:
				if int(row.kind) == 1: total += 1
		elif column == 2:
			total = maxi(total,int(state.receipts[column].get("settings_count",-1)))
		native_scrolls[column].set_rows(total,scrolls[column].scroll_vertical / 36)
		scrolls[column].size.x = column_widths[column] - (16 if total > page_rows else 0)
		var snapshot := {"rows":state.rows[column],"category":state.category,"subcategory":state.subcategory,
			"start":state.row_starts[column],"total":total}
		if row_cache[column] == snapshot:
			for line in columns[column].get_children():
				for control in line.get_children():
					if control is Button: control.disabled = busy
			continue
		row_cache[column] = snapshot.duplicate(true)
		# Native navigation/search retains the scroll offset. An asynchronous
		# reply can leave the column empty long enough for Godot to clamp it to
		# zero; retain its last populated offset across that temporary gap.
		if not state.area.is_empty() and not rendered_rows[column].is_empty():
			var bar := scrolls[column].get_v_scroll_bar()
			var displayed := mini(retained_scroll[column],maxi(0,int(bar.max_value - bar.page)))
			# Native keeps an offset beyond a short search's visible range and
			# restores it when the result grows again. Only adopt a changed
			# displayed position, not the layout's automatic range clamp.
			if scrolls[column].scroll_vertical != displayed:
				retained_scroll[column] = scrolls[column].scroll_vertical
		var previous_scroll: int = retained_scroll[column]
		for child in columns[column].get_children(): columns[column].remove_child(child); child.queue_free()
		rendered_rows[column] = []
		add_spacer(column,state.row_starts[column])
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
			# DF's owned row builder already formats the caption, including its
			# CP437 capitalization. Unicode recasing changes native glyphs.
			if column == 2:
				label.text = leaf_caption(label.text,column_widths[2]/8-5-(2 if total > page_rows else 0))
			label.position = Vector2(56 if column == 0 else 8,0)
			label.size = Vector2(([208,208][column] - (48 if column == 0 else 0)) if column < 2 else maxi(0,column_widths[2] - 16 - (16 if total > page_rows else 0)),36)
			label.add_theme_font_size_override("font_size",12); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.clip_text = true; label.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(label)
			if column == 0:
				var picture := TextureRect.new(); picture.texture = art.texture(category_art.get(str(row.key),""))
				picture.position = Vector2(2,2); picture.size = Vector2(32,32)
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(picture)
			if int(row.kind) in [1,2]:
				# Native status icons share the row's selection target. They are
				# indicators, not separate category/sublist bulk-edit buttons.
				var icon := TextureRect.new(); icon.name = "Status"
				icon.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
				icon.offset_left = -40; icon.offset_right = -8
				icon.texture = art.texture({1:"STOCKPILE_OFF",2:"STOCKPILE_ON",3:"STOCKPILE_PARTIAL"}.get(int(row.state),""))
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
		add_spacer(column,maxi(0,total - state.row_starts[column] - rendered_rows[column].size()))
		scroll_generation[column] += 1
		layout_pending[column] = true
		restore_scroll(column,scroll_generation[column],previous_scroll)

func add_spacer(column: int, count: int) -> void:
	if count <= 0: return
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.y = count * 36
	columns[column].add_child(spacer)

func _process(_delta: float) -> void:
	if state == null or not is_visible_in_tree(): return
	for column in 3:
		native_scrolls[column].set_rows(native_scrolls[column].count,scrolls[column].scroll_vertical / 36)
	# A drag may move again while a read is outstanding. Reconcile the latest
	# viewport once that ticket finishes instead of losing its final position.
	if not layout_pending[2]: state.seek(2,scrolls[2].scroll_vertical / 36,page_rows)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	for column in 3:
		if not scrolls[column].get_rect().has_point(point): continue
		var bar = native_scrolls[column]
		bar.move_to(bar.first + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1) * (bar.page if event.shift_pressed else 1))
		get_viewport().set_input_as_handled()
		return
