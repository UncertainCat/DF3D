extends Control
# Native selector labels are mapped from captured game text. DFHack's sort
# overlay Search/Hide established controls are not part of this native surface.
var state
var owner_view
var scroll: ScrollContainer
var native_scroll
var rows_box: VBoxContainer
var detail: Label
var choices: Array[Button] = []
var cached: Array = []
var cached_kind := 0
var guild_labels: Dictionary = {}
var sphere_labels: Dictionary = {}
# Supported native captures agree with data/init/colors.txt (WHITE, LCYAN, YELLOW).
const NATIVE_WHITE := Color8(255,255,255)
const NATIVE_CYAN := Color8(18,254,207)
const NATIVE_YELLOW := Color8(255,225,17)

func configure(source, model, view) -> void:
	state = model; owner_view = view
	custom_minimum_size = Vector2(312,396)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://panels/area_location_labels.json"))
	for row in data.guilds: guild_labels[int(row.profession)] = str(row.label)
	for row in data.spheres: sphere_labels[int(row.id)] = str(row.label)
	var back: Button = owner_view.button("Back",Vector2(216,0),Vector2(96,36),true)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		back.add_theme_color_override(key,NATIVE_WHITE)
	add_child(back); back.pressed.connect(func(): owner_view.done.emit())
	scroll = ScrollContainer.new(); scroll.position = Vector2(0,36); scroll.size = Vector2(296,360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rows_box = VBoxContainer.new(); rows_box.add_theme_constant_override("separation",0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(rows_box)
	native_scroll = preload("res://scripts/area_location_scrollbar.gd").new()
	add_child(native_scroll); native_scroll.position = Vector2(296,36); native_scroll.configure(source)
	native_scroll.row_changed.connect(func(_first):
		detail.text = ""; apply_scroll(); apply_scroll.call_deferred())
	detail = Label.new(); detail.position = Vector2(336,48); detail.size = Vector2(256,336)
	detail.add_theme_font_size_override("font_size",12); detail.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(detail)
	detail.add_theme_constant_override("line_spacing",0)
	detail.add_theme_color_override("font_color",NATIVE_WHITE)
	visibility_changed.connect(func(): if not visible: detail.text = "")

func apply_scroll() -> void:
	# Catalog replies can precede ScrollContainer's updated extent. The native
	# row position owns scrolling; apply it again after the queued layout pass.
	scroll.scroll_vertical = native_scroll.first*36

func layout_rows() -> void:
	scroll.queue_sort()
	apply_scroll.call_deferred()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	if not scroll.get_global_rect().has_point(event.position): return
	native_scroll.move_to(native_scroll.first+(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)*(10 if event.shift_pressed else 1))
	get_viewport().set_input_as_handled()

func title(row: Dictionary) -> String:
	if state.catalog_kind == 4: return str(guild_labels.get(int(row.profession),""))
	return "(No particular deity)" if int(row.kind) == 1 else str(row.name)

func caption(count: int, singular: String, plural: String, none: String) -> String:
	return none if count == 0 else "%d %s" % [count,singular if count == 1 else plural]

func row_title(row: Dictionary) -> String:
	# Native's fixed 29-cell field replaces its last three cells when the name
	# reaches the field boundary, including names exactly 29 glyphs long.
	var value := title(row)
	return value.left(26)+"..." if value.length() >= 29 else value

func metadata(row: Dictionary) -> String:
	var lines: Array[String] = []
	if state.catalog_kind == 4:
		lines.append(caption(int(row.workers),"worker","workers","No workers"))
		if int(row.guild_id) < 0: lines.append("No established guild")
		else:
			lines.append("Guild:"); lines.append(owner_view.fit_line(str(row.guild_name),160))
			lines.append(caption(int(row.members),"member","members","No members"))
	else:
		lines.append(caption(int(row.worshippers),"worshipper","worshippers","No worshippers"))
		if int(row.kind) == 3: lines.append("Worship")
		for deity in row.deities:
			if int(row.kind) == 3: lines.append(owner_view.fit_line(str(deity.name),160))
			for sphere in deity.spheres:
				var label := str(sphere_labels.get(int(sphere),""))
				if not label.is_empty(): lines.append(label)
	return "\n".join(lines)

func refresh() -> void:
	if cached_kind != state.catalog_kind or cached != state.catalog_rows:
		cached_kind = state.catalog_kind; cached = state.catalog_rows.duplicate(true); detail.text = ""
		for control in choices: rows_box.remove_child(control); control.queue_free()
		choices.clear(); scroll.scroll_vertical = 0
		native_scroll.set_rows(state.catalog_rows.size())
		scroll.size.x = 312 if state.catalog_rows.size() <= 10 else 296
		for index in state.catalog_rows.size():
			var row: Dictionary = state.catalog_rows[index]
			var control := Button.new(); control.custom_minimum_size = Vector2(288,36)
			var style = owner_view.art.make_style("BUTTON_RECTANGLE",8)
			style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
			style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			for key in ["normal","hover","pressed","disabled","focus"]: control.add_theme_stylebox_override(key,style)
			var frame := Panel.new(); frame.size = Vector2(40,36); frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var inset = owner_view.art.make_style("BUTTON_PICTURE_BOX",8)
			inset.set_texture_margin(SIDE_TOP,12); inset.set_texture_margin(SIDE_BOTTOM,12); frame.add_theme_stylebox_override("panel",inset); control.add_child(frame)
			var icon := TextureRect.new(); icon.texture = owner_view.art.texture("ZONE_SHRINE" if state.catalog_kind == 2 else "ZONE_GUILDHALL")
			icon.position = Vector2(2,2); icon.size = Vector2(32,32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(icon)
			var name_label := Label.new(); name_label.name = "Name"; name_label.position = Vector2(56,12); name_label.add_theme_font_size_override("font_size",12)
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(name_label)
			name_label.add_theme_color_override("font_color",NATIVE_WHITE)
			if state.catalog_kind == 4 or int(row.get("kind",1)) == 3: name_label.add_theme_color_override("font_color",NATIVE_YELLOW)
			elif int(row.get("kind",1)) == 2: name_label.add_theme_color_override("font_color",NATIVE_CYAN)
			var indicator := Label.new(); indicator.position = Vector2(56,24); indicator.add_theme_font_size_override("font_size",12)
			indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(indicator)
			indicator.add_theme_color_override("font_color",NATIVE_WHITE)
			if state.catalog_kind == 2 and row.has_temple: indicator.text = "Have temple"
			if state.catalog_kind == 4 and row.has_meeting_place: indicator.text = "Have meeting place"
			control.pressed.connect(func(): state.choose_catalog(index))
			control.mouse_entered.connect(func(): detail.text = metadata(row))
			control.mouse_exited.connect(func(): detail.text = "")
			rows_box.add_child(control); choices.append(control)
			name_label.text = row_title(row)
		layout_rows.call_deferred()
	for control in choices: control.disabled = state.busy() or state.catalog_cursor != 0
