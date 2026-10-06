extends PanelContainer
signal done
signal details_requested(target: Dictionary)
var art = preload("res://scripts/original_ui.gd").new()
var state
var remove: Button
var create_buttons: Array[Button] = []
var choices: Array[Button] = []
var rows_box: VBoxContainer
var scroll: ScrollContainer
var native_scroll
var cached: Array = []
var body: Control
var catalog_view: Control
var guild_professions: Dictionary = {}
const NATIVE_WHITE := Color8(255,255,255)
const NATIVE_YELLOW := Color8(255,225,17)
const GUILD_TIERS = ["meeting place","guildhall","grand guildhall"]
const LABELS = ["","Tavern","Temple","Library","Guildhall","Hospital"]
const ICONS = ["","ZONE_TAVERN","ZONE_TEMPLE","ZONE_LIBRARY","ZONE_GUILDHALL","ZONE_HOSPITAL"]

func configure(source, model) -> void:
	state = model; art.configure(source); theme = art.theme
	var labels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://panels/area_location_labels.json"))
	for row in labels.get("guild_professions",[]): guild_professions[int(row.profession)] = str(row.label)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body = Control.new(); body.custom_minimum_size = Vector2(312,396); add_child(body)
	catalog_view = preload("res://scripts/area_location_catalog_view.gd").new()
	add_child(catalog_view); catalog_view.configure(source,state,self); catalog_view.hide()
	var label := Label.new(); label.text = "Add or choose a location."; label.position = Vector2(8,0)
	label.size = Vector2(208,36); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",12); body.add_child(label)
	label.add_theme_color_override("font_color",NATIVE_WHITE)
	var cancel := button("Cancel",Vector2(216,0),Vector2(96,36),true); body.add_child(cancel)
	cancel.pressed.connect(func(): done.emit())
	remove = button("Remove current location assignment",Vector2(8,36),Vector2(296,36),true)
	body.add_child(remove); remove.pressed.connect(func(): state.assign(-1))
	for index in 5:
		var control := button(["New inn/tavern","New temple","New library","New guildhall","New hospital"][index],Vector2(8+(index%2)*160,72+(index/2)*36),Vector2(136,36))
		control.pressed.connect(func(): state.create(index+1))
		body.add_child(control); create_buttons.append(control)
	scroll = ScrollContainer.new(); scroll.position = Vector2(0,192); scroll.size = Vector2(312,180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rows_box = VBoxContainer.new(); rows_box.add_theme_constant_override("separation",0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(rows_box)
	native_scroll = preload("res://scripts/area_location_scrollbar.gd").new()
	body.add_child(native_scroll); native_scroll.configure(source)
	native_scroll.row_changed.connect(func(_first): apply_scroll(); apply_scroll.call_deferred())
	state.changed.connect(refresh)
	state.selection_finished.connect(func(): done.emit())
	refresh()

func apply_scroll() -> void:
	scroll.scroll_vertical = native_scroll.first*36

func layout_rows() -> void:
	scroll.queue_sort()
	apply_scroll.call_deferred()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not body.visible or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	if not scroll.get_global_rect().has_point(event.position): return
	native_scroll.move_to(native_scroll.first+(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)*(native_scroll.page if event.shift_pressed else 1))
	get_viewport().set_input_as_handled()

func panel_style() -> StyleBox:
	var style := art.make_style("HOVER_RECTANGLE",8)
	for side in [SIDE_LEFT,SIDE_RIGHT]: style.set_content_margin(side,8)
	for side in [SIDE_TOP,SIDE_BOTTOM]:
		style.set_texture_margin(side,12); style.set_content_margin(side,12)
	return style

func button(text: String, point: Vector2, extent: Vector2, red := false) -> Button:
	var control := Button.new(); control.text = text; control.position = point; control.size = extent
	control.add_theme_font_size_override("font_size",12)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: control.add_theme_color_override(key,NATIVE_WHITE)
	var style := art.make_style("HORIZONTAL_OPTION_REMOVE" if red else "HORIZONTAL_OPTION_INACTIVE",8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	for key in ["normal","hover","pressed","disabled"]: control.add_theme_stylebox_override(key,style)
	return control

func refresh() -> void:
	body.visible = state.catalog_kind == 0; catalog_view.visible = state.catalog_kind != 0
	if state.catalog_kind != 0:
		catalog_view.refresh(); return
	var assigned := int(state.area.get("location_id",-1)) >= 0
	remove.visible = assigned
	remove.disabled = state.busy() or not assigned
	var shift := 0 if assigned else -36
	scroll.position.y = 192+shift
	scroll.size.y = 180-shift
	native_scroll.page = 5 if assigned else 6
	native_scroll.position = Vector2(296,scroll.position.y)
	native_scroll.size = Vector2(16,scroll.size.y)
	native_scroll.set_rows(state.rows.size(),native_scroll.first)
	scroll.size.x = 296 if native_scroll.visible else 312
	for index in create_buttons.size():
		create_buttons[index].position.y = 72+(index/2)*36+shift
		create_buttons[index].disabled = state.busy()
	if cached != state.rows:
		cached = state.rows.duplicate(true)
		for control in choices: rows_box.remove_child(control); control.queue_free()
		choices.clear()
		for row in state.rows:
			var kind := int(row.get("location_kind",0))
			var control := Button.new(); control.custom_minimum_size = Vector2(288,36)
			var style := art.make_style("BUTTON_RECTANGLE",8)
			style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
			style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			for key in ["normal","hover","pressed","disabled","focus"]: control.add_theme_stylebox_override(key,style)
			var frame := Panel.new(); frame.size = Vector2(40,36)
			var inset := art.make_style("BUTTON_PICTURE_BOX",8)
			inset.set_texture_margin(SIDE_TOP,12); inset.set_texture_margin(SIDE_BOTTOM,12)
			frame.add_theme_stylebox_override("panel",inset); frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.add_child(frame)
			var icon := TextureRect.new(); icon.texture = art.texture(ICONS[kind]) if kind in range(1,6) else null
			icon.position = Vector2(2,2); icon.size = Vector2(32,32); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(icon)
			var religion := str(row.get("religion",""))
			var subtitle: String = row_subtitle(row)
			for line in 2:
				var label := Label.new(); label.name = "Name" if line == 0 else "Subtitle"
				label.set_meta("full_text",str(row.get("name","")) if line == 0 else subtitle)
				label.position = Vector2(56,12+line*12)
				label.clip_text = true; label.add_theme_font_size_override("font_size",12)
				label.add_theme_color_override("font_color",NATIVE_YELLOW if line == 1 and not religion.is_empty() else NATIVE_WHITE)
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(label)
				# Apply bounds after theme/minimum-size invalidations from the new text.
				label.set_deferred("size",Vector2(200,12))
			var details := Button.new(); details.name = "Details"; details.position = Vector2(256,0); details.size = Vector2(32,36)
			details.pressed.connect(func():
				if not state.busy():details_requested.emit(row.duplicate(true)))
			for key in ["normal","hover","pressed","disabled","focus"]: details.add_theme_stylebox_override(key,StyleBoxEmpty.new())
			var detail_icon := TextureRect.new(); detail_icon.texture = art.texture("ZONE_LOCATION_DETAILS")
			detail_icon.size = Vector2(32,36)
			detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; details.add_child(detail_icon); control.add_child(details)
			control.pressed.connect(func(): state.assign(int(row.id)))
			control.resized.connect(layout_row.bind(control))
			rows_box.add_child(control); choices.append(control)
			layout_row(control)
		layout_rows.call_deferred()
	for control in choices:
		control.disabled = state.busy()
		control.get_node("Details").disabled = state.busy()
	layout_rows.call_deferred()

func row_subtitle(row: Dictionary) -> String:
	var kind := int(row.get("location_kind",0))
	if kind == 4:
		var profession := str(guild_professions.get(int(row.get("guild_profession",-1)),""))
		var tier := int(row.get("location_tier",-1))
		if profession.is_empty() or tier < 0 or tier > 3: return ""
		return profession+(" "+GUILD_TIERS[tier] if tier < 3 else "")
	var religion := str(row.get("religion",""))
	return religion if not religion.is_empty() else (LABELS[kind] if kind in range(1,6) else "")

func layout_row(control: Button) -> void:
	# Native keeps an eight-pixel right inset; a visible scrollbar reduces the
	# row width and therefore the text space, not the icon or font size.
	var details := control.get_node("Details") as Button
	details.position.x = control.size.x-40
	var width := maxf(0,details.position.x-56)
	for key in ["Name","Subtitle"]:
		var label := control.get_node(key) as Label
		label.text = fit_line(str(label.get_meta("full_text")),width,true)
		label.set_deferred("size",Vector2(width,12))

func fit_line(value: String, width: float, location_row := false) -> String:
	# Native uses three ASCII periods; Label.ellipsis_char only accepts one
	# character, and the installed CP437 font has no Unicode ellipsis glyph.
	# Native truncation counts eight-pixel CP437 cells, including the exact
	# boundary, independently of a host font's fallback glyph metrics.
	var columns := maxi(0,int(width)/8)
	if columns < 3: return ""
	# The existing-location row begins truncating at 26 characters in its
	# 27-cell field (276 native profession/tier controls). Catalog hover text
	# uses the full field; do not apply this row-specific threshold there.
	return value if value.length() < columns-(1 if location_row else 0) else value.left(columns-3)+"..."
