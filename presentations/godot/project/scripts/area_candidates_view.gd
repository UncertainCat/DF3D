extends PanelContainer
signal focus_requested(tile: Vector3i)
var art = preload("res://scripts/original_ui.gd").new()
var state
var world
var body: Control
var search: LineEdit
var owner_search
var scroll: ScrollContainer
var rows_box: VBoxContainer
var headers: Array[Button] = []
var header_backgrounds: Array[Panel] = []
var choices: Array[Button] = []
var focus_buttons: Array[Button] = []
var portrait_slots: Array = []
var owner_frames: Array[Panel] = []
var picture = preload("res://scripts/native_unit_picture_frame.gd").new()
var remove: Button
var cached_rows: Array = []
var owner_selected := 0
var owner_receipt := 0
var strips: Dictionary = {}
var squad_prompt: Label
var squad_buttons: Array[Button] = []
var native_colors: Array[Color] = []
var owner_color_rows: Array = []
var owner_color_random := RandomNumberGenerator.new()
const NameColor = preload("res://scripts/native_name_color.gd")

func configure(source, model) -> void:
	owner_color_random.randomize()
	world = source; state = model; art.configure(source); theme = art.theme
	if world.has_method("assets_root"): native_colors = art.installed_palette(world.assets_root())
	if world.has_method("ui_texture"): picture.configure(world)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body = Control.new(); body.custom_minimum_size = Vector2(576,684); add_child(body)
	squad_prompt = Label.new(); squad_prompt.position = Vector2(8,0); squad_prompt.size = Vector2(544,36)
	squad_prompt.add_theme_font_size_override("font_size",12); squad_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(squad_prompt)
	for index in 4:
		var button := Button.new(); button.text = ["Name","Cat","Prof",""][index]
		button.position = Vector2([40,120,192,440][index],0); button.size = Vector2([80,72,80,32][index],12)
		button.add_theme_font_size_override("font_size",12)
		button.pressed.connect(func(): state.order(index+1))
		body.add_child(button); headers.append(button)
		var background := Panel.new(); background.position = Vector2(32,0)
		background.size = Vector2([48,40,48,0][index],12); background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.show_behind_parent = true; background.visible = index < 3
		button.add_child(background); header_backgrounds.append(background)
	scroll = ScrollContainer.new(); scroll.position = Vector2(0,24); scroll.size = Vector2(576,600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	var bar := scroll.get_v_scroll_bar(); bar.custom_minimum_size.x = 16
	var track := art.make_style("SCROLLBAR",0)
	track.set_texture_margin(SIDE_TOP,12); track.set_texture_margin(SIDE_BOTTOM,12)
	bar.add_theme_stylebox_override("scroll",track)
	var thumb := art.make_style("SCROLLBAR_SMALL_SCROLLER",0)
	thumb.set_texture_margin(SIDE_TOP,12); thumb.set_texture_margin(SIDE_BOTTOM,12)
	for key in ["grabber","grabber_highlight","grabber_pressed"]: bar.add_theme_stylebox_override(key,thumb)
	bar.value_changed.connect(func(value): if value > 0 and value+bar.page >= bar.max_value-36: state.more())
	rows_box = VBoxContainer.new(); rows_box.add_theme_constant_override("separation",0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(rows_box)
	remove = row_button("Remove assignment"); rows_box.add_child(remove)
	remove.pressed.connect(func(): state.assign_owner(-1))
	search = LineEdit.new(); search.position = Vector2(16,648); search.size = Vector2(312,36)
	search.max_length = 128; search.add_theme_font_size_override("font_size",12)
	search.text_changed.connect(func(value): state.queue_search(value)); body.add_child(search)
	var inset := StyleBoxTexture.new(); inset.texture = art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8); inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]: inset.set_texture_margin(side,12); inset.set_content_margin(side,0)
	inset.set_content_margin(SIDE_LEFT,8); inset.set_content_margin(SIDE_RIGHT,40)
	for key in ["normal","focus"]: search.add_theme_stylebox_override(key,inset)
	owner_search = preload("res://scripts/area_owner_filter.gd").new()
	owner_search.position = search.position; owner_search.size = search.size; owner_search.theme = art.theme
	body.add_child(owner_search); owner_search.configure(inset,native_colors)
	owner_search.edited.connect(state.queue_owner_search)
	state.changed.connect(refresh); refresh()

func row_style(selected: bool = false) -> StyleBoxTexture:
	var style := art.make_style("BUTTON_RECTANGLE_SELECTED" if selected else ("BUTTON_RECTANGLE" if state.kind == 1 else "BUTTON_RECTANGLE_DARK"),8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	style.set_content_margin(SIDE_LEFT,40); style.set_content_margin(SIDE_RIGHT,80 if state.kind == 2 else 144)
	return style

func style_row(button: Button, selected: bool) -> void:
	var style := row_style(selected)
	for key in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(key,style)

func row_button(text: String) -> Button:
	var button := Button.new(); button.custom_minimum_size = Vector2(352 if state.kind == 2 else 552,36)
	if state.kind == 1: button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.text = text
	button.add_theme_font_size_override("font_size",12)
	style_row(button,false)
	return button

func refresh() -> void:
	if owner_receipt != state.receipt or state.rows.is_empty():
		owner_selected = 0; owner_receipt = state.receipt
	body.custom_minimum_size = Vector2(564,400) if state.kind == 3 else Vector2(376 if state.kind == 2 else 576,684)
	scroll.position.y = 36 if state.kind == 3 else 24
	scroll.size = Vector2(body.custom_minimum_size.x,360 if state.kind == 3 else 600)
	squad_prompt.visible = state.kind == 3
	squad_prompt.text = "Select the squads to train here." if state.squad_mask == 2 else "Select how squads will use this space."
	search.visible = state.kind == 2
	owner_search.visible = state.kind == 1
	owner_search.set_bytes(state.query_bytes if state.query_bytes is PackedByteArray else state.query.to_utf8_buffer())
	remove.visible = state.can_remove_owner()
	if search.text != state.query: search.text = state.query
	search.editable = not state.failed and not state.mutating and not state.area.is_empty()
	owner_search.editable = search.editable
	for index in headers.size():
		headers[index].focus_mode = Control.FOCUS_NONE if state.kind == 1 else Control.FOCUS_ALL
		headers[index].visible = state.kind != 3 and (index < 3 or state.kind == 1)
		headers[index].disabled = not search.editable
		var active := "ACTIVE" if state.sort == index+1 else "INACTIVE"
		var descending: bool = state.sort_direction(index+1)
		var arrow_descending: bool = not descending if state.kind == 1 else descending
		headers[index].icon = strip(("SORT_DESCENDING_" if arrow_descending else "SORT_ASCENDING_")+active,4)
		var style := StyleBoxTexture.new(); style.texture = strip("SORT_TEXT_"+active,3)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
		style.set_texture_margin(SIDE_LEFT,8); style.set_texture_margin(SIDE_RIGHT,8)
		header_backgrounds[index].add_theme_stylebox_override("panel",style)
		var text_color := Color.BLACK if state.sort == index+1 else Color8(160,160,160)
		for key in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:
			headers[index].add_theme_color_override(key,text_color)
		for key in ["normal","hover","pressed","disabled","focus"]:
			headers[index].add_theme_stylebox_override(key,StyleBoxEmpty.new())
		headers[index].add_theme_constant_override("h_separation",0)
		headers[index].size = Vector2([80,72,80,32][index],12)
	remove.disabled = state.busy()
	if cached_rows != state.rows:
		cached_rows = state.rows.duplicate(true)
		for button in choices: rows_box.remove_child(button); button.queue_free()
		choices.clear()
		focus_buttons.clear()
		portrait_slots.clear()
		owner_frames.clear()
		owner_color_rows.clear()
		squad_buttons.clear()
		for row in state.rows:
			if state.kind == 3:
				add_squad(row); continue
			var label := ""
			if state.kind == 2:
				label = str(row.get("name",""))
				if not str(row.get("profession","")).is_empty(): label += "\n" + str(row.profession)
				if int(row.get("sex",-1)) in [0,1]: label += ", " + ("♀" if int(row.sex) == 0 else "♂")
				if bool(row.get("grazer",false)): label += "\nGrazer: requires pasture"
			var button := row_button(label); button.clip_text = true; button.tooltip_text = label
			button.pressed.connect(func():
				if state.kind == 2: state.toggle_animal(int(row.id))
				else: state.assign_owner(int(row.id)))
			rows_box.add_child(button); choices.append(button)
			if state.kind == 1 and row.get("owner_display") is Dictionary:
				add_owner_text(button,row.owner_display)
			var owner: bool = state.kind == 1
			var frame := Panel.new(); frame.position = Vector2.ZERO; frame.size = Vector2(40 if owner else 32,36)
			var frame_style := art.make_style("BUTTON_PICTURE_BOX",8)
			if owner: frame_style.texture = picture.texture(false)
			frame_style.set_texture_margin(SIDE_TOP,12); frame_style.set_texture_margin(SIDE_BOTTOM,12)
			frame.add_theme_stylebox_override("panel",frame_style)
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(frame)
			if owner: owner_frames.append(frame)
			if (owner and world.has_method("candidate_icon")) or (not owner and world.has_method("creature_portrait")):
				var portrait := TextureRect.new()
				portrait.texture = null if owner else world.creature_portrait(int(row.id))
				portrait.position = Vector2(2,2) if owner else Vector2.ZERO
				portrait.size = Vector2(32,32) if owner else Vector2(32,36)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_SCALE if owner else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(portrait)
				portrait_slots.append({"id":int(row.id),"view":portrait,"snapshot":owner,"recipe":row.get("sheet_icon",{}),"loaded":false})
			var focus := Button.new(); focus.position = Vector2(408,6); focus.size = Vector2(24,24)
			focus.tooltip_text = "Show on map"
			for key in ["normal","hover","pressed","disabled","focus"]: focus.add_theme_stylebox_override(key,StyleBoxEmpty.new())
			var focus_icon := TextureRect.new(); focus_icon.texture = art.texture("STOCKS_RECENTER")
			focus_icon.size = Vector2(24,24); focus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			focus.add_child(focus_icon); button.add_child(focus); focus_buttons.append(focus)
			focus.visible = state.kind == 1
			focus.set_meta("unit_id",int(row.id))
			focus.pressed.connect(func(): focus_unit(int(row.id)))
			var mood := int(row.get("mood",0))
			if state.kind == 1 and mood in range(1,8):
				var icon := TextureRect.new(); icon.texture = art.texture("BUTTON_STRESS_%d" % (7-mood))
				icon.position = Vector2(440,0); icon.size = Vector2(16,16)
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
			if state.kind == 2:
				var check := TextureRect.new()
				check.texture = art.texture("LABOR_WORKER_ASSIGNED" if bool(row.get("assigned",false)) else "LABOR_WORKER_UNASSIGNED")
				check.position = Vector2(280,0); check.size = Vector2(32,36)
				check.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(check)
	if state.kind == 1:
		style_row(remove,remove.visible and owner_selected == 0)
		for index in choices.size():
			var selected := index + (1 if remove.visible else 0) == owner_selected
			style_row(choices[index],selected)
			var frame_style: StyleBoxTexture = owner_frames[index].get_theme_stylebox("panel")
			frame_style.texture = picture.texture(selected)
	for button in choices: button.disabled = state.busy()
	for button in squad_buttons: button.disabled = state.busy() or bool(button.get_meta("unknown",false))
	for button in focus_buttons:
		button.disabled = state.busy() or unit_tile(int(button.get_meta("unit_id"))).x < 0
		button.modulate = Color(0.5,0.5,0.5) if button.disabled else Color.WHITE
	# A short bridge page must not strand the cursor below an absent scrollbar.
	if not state.busy() and state.cursor != 0 and state.rows.size() < 16: state.call_deferred("more")

# Local selection follows the native STANDARDSCROLL bindings. Receipt changes
# reset it; continuation pages retain the same receipt and selection.
func owner_pointer(event: InputEvent) -> void:
	if not is_visible_in_tree() or state.kind != 1 or not owner_search.has_focus(): return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	if owner_search.get_global_rect().has_point(event.position): return
	for header in headers:
		if header.visible and header.get_global_rect().has_point(event.position): return
	owner_search.release_focus()

func feed_owner_key(event: InputEvent) -> bool:
	if not is_visible_in_tree() or state.kind != 1 or not event is InputEventKey or not event.pressed: return false
	if event.keycode == KEY_F and event.ctrl_pressed and not (event.alt_pressed or event.meta_pressed or event.shift_pressed):
		if owner_search.editable and not event.echo: owner_search.grab_focus()
		return true
	if owner_search.has_focus():
		owner_search.feed_key(event); return true
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed: return false
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		if event.echo or state.busy(): return true
		if remove.visible and owner_selected == 0: state.assign_owner(-1)
		else:
			var index := owner_selected - (1 if remove.visible else 0)
			if index >= 0 and index < state.rows.size(): state.assign_owner(int(state.rows[index].id))
		return true
	var delta := 0
	match event.keycode:
		KEY_UP,KEY_8,KEY_KP_8: delta = -1
		KEY_DOWN,KEY_2,KEY_KP_2: delta = 1
		KEY_PAGEUP,KEY_9,KEY_KP_9: delta = -16
		KEY_PAGEDOWN,KEY_3,KEY_KP_3: delta = 16
	if delta == 0: return false
	if state.busy(): return true
	var count: int = choices.size() + (1 if remove.visible else 0)
	if count == 0: return true
	owner_selected = clampi(owner_selected + delta,0,count-1)
	refresh()
	var first := int(scroll.scroll_vertical / 36)
	if owner_selected < first: first = owner_selected
	elif owner_selected >= first + 16: first = owner_selected - 15
	scroll.scroll_vertical = first * 36
	return true

func add_owner_text(button: Button, display: Dictionary) -> void:
	# Native status occupies the first cell row; the two name lines follow it.
	# Absent records stay unknown, and native shortening is never repeated here.
	var colored: Array = []
	for index in 3:
		var line := Label.new(); line.name = ["OwnerStatus","OwnerFirst","OwnerSecond"][index]
		line.text = str(display.get(["status","first_line","second_line"][index],""))
		line.add_theme_font_size_override("font_size",12); line.clip_text = true
		# All four native status branches write fg2/bg0/bright1 (3a8730).
		if index == 0 and native_colors.size() == 16: line.add_theme_color_override("font_color",native_colors[10])
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(line)
		line.position = Vector2(40,index*12); line.size = Vector2(int(display.columns)*8,12)
		if index > 0:
			var background := ColorRect.new(); background.name = "GlyphBackground"
			background.mouse_filter = Control.MOUSE_FILTER_IGNORE; background.show_behind_parent = true
			background.size = Vector2(mini(line.text.length(),int(display.columns))*8,12)
			line.add_child(background); colored.append(line)
	owner_color_rows.append({"description":display.get("name_color",{}),"lines":colored,"last":[]})
	apply_owner_colors(Time.get_ticks_msec())

func _process(_delta: float) -> void:
	if is_visible_in_tree(): apply_owner_colors(Time.get_ticks_msec())

func apply_owner_colors(time_ms: int, fire_choice: int = -1) -> void:
	for row in owner_color_rows:
		var choice := fire_choice
		if choice < 0: choice = owner_color_random.randi_range(0,1) if int(row.description.get("effect",0)) == 3 else 0
		var color: Array = NameColor.choose(row.description,time_ms,choice) if native_colors.size() == 16 else []
		for line in row.lines: line.visible = not color.is_empty()
		if color.is_empty() or color == row.last: continue
		row.last = color.duplicate()
		for line in row.lines:
			line.add_theme_color_override("font_color",native_colors[int(color[0])+int(color[2])*8])
			var background: ColorRect = line.get_node("GlyphBackground")
			background.visible = int(color[1]) != 0
			background.color = native_colors[int(color[1])]

func add_squad(row: Dictionary) -> void:
	var button := row_button(str(row.get("name","")))
	button.clip_text = true; button.tooltip_text = str(row.get("name",""))
	var style: StyleBox = button.get_theme_stylebox("normal").duplicate()
	style.set_content_margin(SIDE_LEFT,56)
	for key in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(key,style)
	rows_box.add_child(button); choices.append(button)
	var entries := [[1,"SLEEP","Sleep"],[2,"TRAIN","Train"],[4,"INDIV_EQ","Store individual equipment"],[8,"SQUAD_EQ","Store squad equipment"]]
	for index in entries.size():
		var entry: Array = entries[index]
		if (int(entry[0]) & state.squad_mask) == 0: continue
		var control := Button.new(); control.size = Vector2(32,36)
		control.position = Vector2(520 if state.squad_mask == 2 else 424+index*32,0)
		control.tooltip_text = str(entry[2])
		for key in ["normal","hover","pressed","disabled","focus"]: control.add_theme_stylebox_override(key,StyleBoxEmpty.new())
		var use := int(row.get("squad_use",-1)); control.set_meta("unknown",use < 0)
		var icon := TextureRect.new(); icon.size = Vector2(32,36)
		icon.texture = art.texture("ZONE_SQUAD_"+str(entry[1])+("_ACTIVE" if use >= 0 and (use & int(entry[0])) != 0 else "_INACTIVE"))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(icon)
		control.pressed.connect(func(): state.toggle_squad(int(row.id),int(entry[0])))
		button.add_child(control); squad_buttons.append(control)

func unit_tile(id: int) -> Vector3i:
	return world.unit_tile(id) if world.has_method("unit_tile") else Vector3i(-1,-1,-1)

func focus_unit(id: int) -> void:
	if state.busy() or not is_visible_in_tree(): return
	var found := false
	for row in state.rows:
		if int(row.id) == id: found = true
	if not found: return
	# Resolve again at click time: a unit can leave the observed map after render.
	var tile := unit_tile(id)
	if tile.x >= 0 and tile.y >= 0 and tile.z >= 0: focus_requested.emit(tile)

func strip(key: String, count: int) -> Texture2D:
	if strips.has(key): return strips[key]
	if not world.has_method("ui_texture"): return null
	var first: Texture2D = world.ui_texture(key,0)
	if first == null: return null
	var cell := Vector2i(first.get_size())
	var image := Image.create(cell.x*count,cell.y,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for index in count:
		var part: Texture2D = world.ui_texture(key,index)
		if part != null: image.blit_rect(part.get_image(),Rect2i(Vector2i.ZERO,cell),Vector2i(cell.x*index,0))
	strips[key] = ImageTexture.create_from_image(image)
	return strips[key]
