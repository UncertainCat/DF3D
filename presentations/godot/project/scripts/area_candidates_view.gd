extends PanelContainer
signal focus_requested(tile: Vector3i)
var art = preload("res://scripts/original_ui.gd").new()
var state
var world
var body: Control
var search: LineEdit
var scroll: ScrollContainer
var rows_box: VBoxContainer
var headers: Array[Button] = []
var choices: Array[Button] = []
var focus_buttons: Array[Button] = []
var portrait_slots: Array = []
var remove: Button
var cached_rows: Array = []
var strips: Dictionary = {}
var squad_prompt: Label
var squad_buttons: Array[Button] = []

func configure(source, model) -> void:
	world = source; state = model; art.configure(source); theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body = Control.new(); body.custom_minimum_size = Vector2(576,684); add_child(body)
	squad_prompt = Label.new(); squad_prompt.position = Vector2(8,0); squad_prompt.size = Vector2(544,36)
	squad_prompt.add_theme_font_size_override("font_size",12); squad_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(squad_prompt)
	for index in 3:
		var button := Button.new(); button.text = ["Name","Cat","Prof"][index]
		button.position = Vector2(40+index*80,0); button.size = Vector2(80,12)
		button.add_theme_font_size_override("font_size",12)
		button.pressed.connect(func(): state.order(index+1))
		body.add_child(button); headers.append(button)
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
	state.changed.connect(refresh); refresh()

func row_button(text: String) -> Button:
	var button := Button.new(); button.custom_minimum_size = Vector2(352 if state.kind == 2 else 552,36)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.text = text
	button.add_theme_font_size_override("font_size",12)
	var style := art.make_style("BUTTON_RECTANGLE_DARK",8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	style.set_content_margin(SIDE_LEFT,40); style.set_content_margin(SIDE_RIGHT,80 if state.kind == 2 else 144)
	for key in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(key,style)
	return button

func refresh() -> void:
	body.custom_minimum_size = Vector2(564,400) if state.kind == 3 else Vector2(376 if state.kind == 2 else 576,684)
	scroll.position.y = 36 if state.kind == 3 else 24
	scroll.size = Vector2(body.custom_minimum_size.x,360 if state.kind == 3 else 600)
	squad_prompt.visible = state.kind == 3
	squad_prompt.text = "Select the squads to train here." if state.squad_mask == 2 else "Select how squads will use this space."
	search.visible = state.kind != 3
	remove.visible = state.kind == 1
	if search.text != state.query: search.text = state.query
	search.editable = not state.failed and not state.mutating and not state.area.is_empty()
	for index in headers.size():
		headers[index].visible = state.kind != 3
		headers[index].disabled = not search.editable
		var active := "ACTIVE" if state.sort == index+1 else "INACTIVE"
		headers[index].icon = strip(("SORT_DESCENDING_" if state.descending else "SORT_ASCENDING_")+active,4)
		var style := StyleBoxTexture.new(); style.texture = strip("SORT_TEXT_"+active,3)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
		style.set_texture_margin(SIDE_LEFT,8); style.set_texture_margin(SIDE_RIGHT,8)
		for key in ["normal","hover","pressed","disabled","focus"]: headers[index].add_theme_stylebox_override(key,style)
		headers[index].add_theme_constant_override("h_separation",0)
		headers[index].size = Vector2(80,12)
	remove.disabled = state.busy() or int(state.area.get("owner_id",-1)) < 0
	if cached_rows != state.rows:
		cached_rows = state.rows.duplicate(true)
		for button in choices: rows_box.remove_child(button); button.queue_free()
		choices.clear()
		focus_buttons.clear()
		portrait_slots.clear()
		squad_buttons.clear()
		for row in state.rows:
			if state.kind == 3:
				add_squad(row); continue
			var label := str(row.get("name",""))
			if not str(row.get("profession","")).is_empty(): label += ("\n" if state.kind == 2 else ", ") + str(row.profession)
			if int(row.get("sex",-1)) in [0,1]: label += ", " + ("♀" if int(row.sex) == 0 else "♂")
			if state.kind == 2 and bool(row.get("grazer",false)): label += "\nGrazer: requires pasture"
			var button := row_button(label); button.clip_text = true; button.tooltip_text = label
			button.pressed.connect(func():
				if state.kind == 2: state.toggle_animal(int(row.id))
				else: state.assign_owner(int(row.id)))
			rows_box.add_child(button); choices.append(button)
			var frame := Panel.new(); frame.position = Vector2.ZERO; frame.size = Vector2(32,36)
			var picture := art.make_style("BUTTON_PICTURE_BOX",8)
			picture.set_texture_margin(SIDE_TOP,12); picture.set_texture_margin(SIDE_BOTTOM,12)
			frame.add_theme_stylebox_override("panel",picture)
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(frame)
			if world.has_method("creature_portrait"):
				var portrait := TextureRect.new(); portrait.texture = world.creature_portrait(int(row.id))
				portrait.position = Vector2(0,0); portrait.size = Vector2(32,36)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(portrait)
				portrait_slots.append({"id":int(row.id),"view":portrait})
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
	for button in choices: button.disabled = state.busy()
	for button in squad_buttons: button.disabled = state.busy() or bool(button.get_meta("unknown",false))
	for button in focus_buttons:
		button.disabled = state.busy() or unit_tile(int(button.get_meta("unit_id"))).x < 0
		button.modulate = Color(0.5,0.5,0.5) if button.disabled else Color.WHITE
	# A short bridge page must not strand the cursor below an absent scrollbar.
	if not state.busy() and state.cursor != 0 and state.rows.size() < 16: state.call_deferred("more")

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
