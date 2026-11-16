extends PanelContainer
signal focus_requested(tile: Vector3i)
var art = preload("res://scripts/original_ui.gd").new()
var state
var cage_layout:=false
var world
var native_help
var body: Control
var owner_search
var owner_scrollbar = preload("res://scripts/reports_scrollbar.gd").new()
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
var viewport_rows := 66
var viewport_columns := 150
var strips: Dictionary = {}
var squad_prompt: Label
var squad_buttons: Array[Button] = []
var squad_symbols = preload("res://scripts/native_squad_symbol.gd").new()
var native_colors: Array[Color] = []
var owner_color_rows: Array = []
var owner_color_random := RandomNumberGenerator.new()
const Contract = preload("res://scripts/management_contract.gd")
const NameColor = preload("res://scripts/native_name_color.gd")

func configure(source, model) -> void:
	owner_color_random.randomize()
	world = source; state = model; art.configure(source); theme = art.theme
	squad_symbols.configure(source)
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
	bar.changed.connect(apply_owner_scroll)
	var track := art.make_style("SCROLLBAR",0)
	track.set_texture_margin(SIDE_TOP,12); track.set_texture_margin(SIDE_BOTTOM,12)
	bar.add_theme_stylebox_override("scroll",track)
	var thumb := art.make_style("SCROLLBAR_SMALL_SCROLLER",0)
	thumb.set_texture_margin(SIDE_TOP,12); thumb.set_texture_margin(SIDE_BOTTOM,12)
	for key in ["grabber","grabber_highlight","grabber_pressed"]: bar.add_theme_stylebox_override(key,thumb)
	bar.value_changed.connect(func(value): if state.kind == 3 and value > 0 and value+bar.page >= bar.max_value-36: state.more())
	owner_scrollbar.clamp_interior_thumb = true
	owner_scrollbar.configure(source); owner_scrollbar.position = Vector2(560,24)
	owner_scrollbar.size = Vector2(16,600); owner_scrollbar.page = 16
	owner_scrollbar.input_allowed = func(): return state.kind in [1,2,3] and not state.busy()
	owner_scrollbar.row_changed.connect(func(first):
		if state.kind == 3: state.squad_first = first
		apply_owner_scroll())
	body.add_child(owner_scrollbar); owner_scrollbar.hide()
	visibility_changed.connect(func(): if not is_visible_in_tree(): owner_scrollbar.dragging = false)
	rows_box = VBoxContainer.new(); rows_box.add_theme_constant_override("separation",0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(rows_box)
	remove = row_button("Remove assignment"); rows_box.add_child(remove)
	remove.pressed.connect(func(): state.assign_owner(-1))
	var inset := StyleBoxTexture.new(); inset.texture = art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8); inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]: inset.set_texture_margin(side,12); inset.set_content_margin(side,0)
	inset.set_content_margin(SIDE_LEFT,8); inset.set_content_margin(SIDE_RIGHT,40)
	owner_search = preload("res://scripts/area_owner_filter.gd").new()
	owner_search.position = Vector2(16,648); owner_search.size = Vector2(312,36); owner_search.theme = art.theme
	body.add_child(owner_search); owner_search.configure(inset,native_colors)
	owner_search.edited.connect(state.queue_owner_search)
	bind_owner_help(owner_search,false)
	state.changed.connect(refresh); state.facts_changed.connect(refresh_owner_facts); refresh()

func panel_style() -> StyleBox:
	var style := art.make_style("HOVER_RECTANGLE",8)
	for side in [SIDE_LEFT,SIDE_RIGHT]: style.set_content_margin(side,8)
	for side in [SIDE_TOP,SIDE_BOTTOM]:
		style.set_texture_margin(side,12); style.set_content_margin(side,12)
	return style

func bind_owner_help(control: Control, recenter: bool) -> void:
	if native_help == null: return
	var owner := control.get_instance_id()
	control.mouse_entered.connect(func():
		if recenter:
			if not control.disabled: native_help.enter_owner_recenter(owner)
		elif owner_search.editable: native_help.enter_owner_filter(owner))
	control.mouse_exited.connect(func():native_help.leave(owner))
	control.visibility_changed.connect(func():
		if not control.is_visible_in_tree(): native_help.leave(owner))
	control.tree_exiting.connect(func():native_help.leave(owner))

func row_style(selected: bool = false) -> StyleBoxTexture:
	var style := art.make_style("BUTTON_RECTANGLE_SELECTED" if selected else "BUTTON_RECTANGLE",8)
	style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
	style.set_content_margin(SIDE_LEFT,40); style.set_content_margin(SIDE_RIGHT,80 if state.kind == 2 else 144)
	return style

func bind_containment_help(button: Button, relation: int) -> void:
	if native_help == null or relation not in [1,2,3,4]: return
	var target := Control.new(); target.name = "AnimalContainmentHover"
	# Approved native bug correction: retain the native 4x3-cell bounds at the
	# drawn indicator, instead of swapping their X/Y coordinates.
	target.position = Vector2(248 if cage_layout else 240,0); target.size = Vector2(32,36)
	target.mouse_filter = Control.MOUSE_FILTER_PASS; button.add_child(target)
	target.set_meta("relation",relation)
	var owner := target.get_instance_id()
	target.mouse_entered.connect(func():
		if not button.disabled: native_help.enter_containment(owner,relation))
	target.mouse_exited.connect(func(): native_help.leave(owner))
	target.visibility_changed.connect(func():
		if not target.is_visible_in_tree(): native_help.leave(owner))
	target.tree_exiting.connect(func(): native_help.leave(owner))

func style_row(button: Button, selected: bool) -> void:
	var style := row_style(selected)
	for key in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(key,style)

func row_button(text: String) -> Button:
	var button := Button.new(); button.custom_minimum_size = Vector2((344 if cage_layout else 352) if state.kind == 2 else 552,36)
	if state.kind == 3 and state.rows.size() > 10: button.custom_minimum_size.x = 536
	if state.kind in [1,2]: button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.text = text
	button.add_theme_font_size_override("font_size",12)
	style_row(button,false)
	return button

func layout(view: Vector2) -> void:
	var rows:=floori(view.y/12)
	var columns:=floori(view.x/8)
	if rows!=viewport_rows or columns!=viewport_columns:
		viewport_rows=rows
		viewport_columns=columns
		owner_scrollbar.dragging=false
		refresh()
	var inset:=fposmod(view.y,12)*0.5-4
	# Containers propagate reduced row minima after their deferred layout pass.
	if state.kind == 1: scroll.size.x = maxi(456,(viewport_columns-80)*8)
	position=Vector2(368,52+inset) if state.kind==2 else Vector2(370,54+inset)
	size=Vector2(576,420) if state.kind==3 else Vector2(392 if state.kind==2 else maxi(468,(viewport_columns-77)*8+4),(viewport_rows-66)*12+(708 if state.kind==2 else 704))
	if cage_layout:
		position.x=(viewport_columns-146)*8
		size.x=384

func page_rows() -> int:
	return maxi(1,floori(float(viewport_rows-16)/3))

func refresh() -> void:
	if owner_receipt != state.receipt or state.rows.is_empty():
		owner_selected = 0; owner_receipt = state.receipt
		owner_scrollbar.set_rows(0); owner_scrollbar.dragging = false; scroll.scroll_vertical = 0
	body.custom_minimum_size = Vector2(564,400) if state.kind == 3 else Vector2(376 if state.kind == 2 else maxi(456,(viewport_columns-78)*8),(viewport_rows-9)*12)
	if cage_layout:body.custom_minimum_size.x=368
	owner_search.position.y=(viewport_rows-12)*12
	scroll.position.y = 36 if state.kind == 3 else 24
	scroll.size = Vector2(360 if state.kind == 2 else maxi(456,(viewport_columns-80)*8),page_rows()*36) if state.kind in [1,2] else Vector2(536 if state.rows.size()>10 else 552,360)
	owner_scrollbar.position = Vector2(544,36) if state.kind == 3 else Vector2(360 if state.kind == 2 else maxi(456,(viewport_columns-80)*8),24)
	owner_scrollbar.size.y = 360 if state.kind == 3 else (viewport_rows-16)*12
	owner_scrollbar.page = 10 if state.kind == 3 else mini(page_rows(),maxi(1,state.rows.size()+(1 if state.can_remove_owner() else 0)-owner_scrollbar.first))
	var standalone_scroll:bool = state.kind != 3
	if owner_scrollbar.use_standalone_sheet != standalone_scroll:
		owner_scrollbar.use_standalone_sheet = standalone_scroll; owner_scrollbar.textures.clear()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	squad_prompt.visible = state.kind == 3
	squad_prompt.text = "Select the squads to train here." if state.squad_mask == 2 else "Select how squads will use this space."
	owner_search.visible = state.kind in [1,2]
	owner_search.set_bytes(state.query_bytes if state.query_bytes is PackedByteArray else state.query.to_utf8_buffer())
	remove.visible = state.can_remove_owner()
	owner_scrollbar.set_rows(state.rows.size()+(1 if remove.visible else 0),state.squad_first if state.kind == 3 else owner_scrollbar.first)
	owner_scrollbar.visible = state.cursor == 0 and owner_scrollbar.count > owner_scrollbar.page
	if state.busy(): owner_scrollbar.dragging = false
	owner_search.editable = not state.failed and not state.mutating and not state.area.is_empty()
	if not owner_search.editable and native_help != null: native_help.leave(owner_search.get_instance_id())
	for index in headers.size():
		headers[index].focus_mode = Control.FOCUS_NONE if state.kind == 1 else Control.FOCUS_ALL
		headers[index].visible = state.kind != 3 and (index < 3 or state.kind == 1)
		headers[index].disabled = not owner_search.editable
		var active := "ACTIVE" if state.sort == index+1 else "INACTIVE"
		var descending: bool = state.sort_direction(index+1)
		var arrow_descending: bool = not descending
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
		# State replaces immutable row snapshots. Share their recipes rather than
		# duplicating nested appearance arrays for change detection.
		cached_rows = state.rows.duplicate()
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
			var button := row_button(label); button.clip_text = true; button.tooltip_text = label
			var unit_id := int(row.id)
			button.pressed.connect(state.toggle_animal.bind(int(row.get("entity",0)),unit_id) if state.kind == 2 else state.assign_owner.bind(unit_id))
			rows_box.add_child(button); choices.append(button)
			if state.kind == 1 and row.get("owner_display") is Dictionary:
				add_owner_text(button,row.owner_display)
			if state.kind == 2 and row.get("animal_display") is Dictionary:
				add_animal_text(button,row.animal_display)
			if state.kind == 2 and row.get("animal_item_color") is Dictionary:
				add_animal_item_text(button,str(row.get("name","")),row.animal_item_color)
			var owner: bool = state.kind == 1
			var selector_icon: bool = owner or state.kind == 2
			var frame := Panel.new(); frame.position = Vector2.ZERO; frame.size = Vector2(40 if selector_icon else 32,36)
			var frame_style := art.make_style("BUTTON_PICTURE_BOX",8)
			if selector_icon: frame_style.texture = picture.texture(false)
			frame_style.set_texture_margin(SIDE_TOP,12); frame_style.set_texture_margin(SIDE_BOTTOM,12)
			frame.add_theme_stylebox_override("panel",frame_style)
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(frame)
			owner_frames.append(frame)
			if world.has_method("candidate_icon") and selector_icon:
				var portrait := TextureRect.new()
				portrait.texture = null
				portrait.position = Vector2(2,2)
				portrait.size = Vector2(32,32)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_SCALE
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(portrait)
				portrait_slots.append({"id":int(row.id),"view":portrait,"snapshot":true,"recipe":row.get("sheet_icon",{}),"loaded":false})
			var focus := Button.new(); focus.position = Vector2(408,6); focus.size = Vector2(24,24)
			for key in ["normal","hover","pressed","disabled","focus"]: focus.add_theme_stylebox_override(key,StyleBoxEmpty.new())
			var focus_icon := TextureRect.new(); focus_icon.texture = art.texture("STOCKS_RECENTER")
			focus_icon.size = Vector2(24,24); focus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			focus.add_child(focus_icon); button.add_child(focus); focus_buttons.append(focus)
			focus.visible = state.kind == 1
			focus.set_meta("unit_id",int(row.id))
			focus.pressed.connect(focus_unit.bind(unit_id))
			bind_owner_help(focus,true)
			var mood := int(row.get("mood",0))
			if state.kind == 1:
				var icon := TextureRect.new(); icon.name = "OwnerStress"
				icon.visible = mood in range(1,8)
				if icon.visible: icon.texture = art.texture("BUTTON_STRESS_%d" % (7-mood))
				icon.position = Vector2(440,0); icon.size = Vector2(16,16)
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
			if state.kind == 2:
				var check := TextureRect.new(); check.name = "AnimalAssigned"
				check.texture = art.texture("LABOR_WORKER_ASSIGNED" if bool(row.get("assigned",false)) else "LABOR_WORKER_UNASSIGNED")
				check.position = Vector2(288 if cage_layout else 280,0); check.size = Vector2(32,36)
				check.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(check)
				update_animal_status(button,row)
	if state.kind == 1:
		# Native rows stretch independently of their fixed name/status columns.
		# At minimum width the list retains its own minimum beyond the frame.
		remove.custom_minimum_size.x = maxi(456,(viewport_columns-81)*8)
		remove.size.x = remove.custom_minimum_size.x
		style_row(remove,remove.visible and owner_selected == 0)
		for index in choices.size():
			choices[index].custom_minimum_size.x = remove.custom_minimum_size.x
			choices[index].size.x = remove.custom_minimum_size.x
			var selected := index + (1 if remove.visible else 0) == owner_selected
			style_row(choices[index],selected)
			var frame_style: StyleBoxTexture = owner_frames[index].get_theme_stylebox("panel")
			frame_style.texture = picture.texture(selected)
	if state.kind == 2:
		for index in choices.size():
			style_row(choices[index],index == owner_selected)
			var frame_style: StyleBoxTexture = owner_frames[index].get_theme_stylebox("panel")
			frame_style.texture = picture.texture(index == owner_selected,cage_layout and bool(state.rows[index].get("assigned",false)))
	for button in choices:
		button.disabled = state.busy()
		var hover = button.get_node_or_null("AnimalContainmentHover")
		if button.disabled and hover != null and native_help != null: native_help.leave(hover.get_instance_id())
	for button in squad_buttons:
		button.disabled = state.busy() or bool(button.get_meta("unknown",false))
		if button.disabled and native_help != null: native_help.leave(button.get_instance_id())
	for button in focus_buttons:
		button.disabled = state.busy() or unit_tile(int(button.get_meta("unit_id"))).x < 0
		if button.disabled and native_help != null: native_help.leave(button.get_instance_id())
		button.modulate = Color(0.5,0.5,0.5) if button.disabled else Color.WHITE
	# A short bridge page must not strand the cursor below an absent scrollbar.
	if state.kind == 3 and not state.busy() and state.cursor != 0: state.call_deferred("more")
	# The retained first row survives assignment receipts; apply after deferred
	# container sizing so a newly arrived list cannot clamp the scroll to zero.
	call_deferred("apply_owner_scroll")

func apply_owner_scroll() -> void:
	if state.kind in [1,2]:
		# Native resize retains the first row and counts only remaining rows in
		# the page, leaving unused space below a short tail.
		owner_scrollbar.page = mini(page_rows(),maxi(1,owner_scrollbar.count-owner_scrollbar.first))
		scroll.size.y = owner_scrollbar.page * 36
		owner_scrollbar.queue_redraw()
	scroll.scroll_vertical = owner_scrollbar.first * 36

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or state.kind not in [1,2,3] or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	var local: Vector2 = body.get_global_transform_with_canvas().affine_inverse() * event.position
	var bounds := Rect2(0,24,owner_scrollbar.position.x+16,owner_scrollbar.size.y)
	if state.kind == 3: bounds = Rect2(-8,-12,576,420)
	if not bounds.has_point(local): return
	if not state.busy():
		owner_scrollbar.move_to(owner_scrollbar.first+(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)*(owner_scrollbar.page if event.shift_pressed else 1))
	get_viewport().set_input_as_handled()

# Local selection follows the native STANDARDSCROLL bindings. Receipt changes
# reset it; continuation pages retain the same receipt and selection.
func owner_pointer(event: InputEvent) -> void:
	if not is_visible_in_tree() or state.kind not in [1,2] or not owner_search.has_focus(): return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	if owner_search.get_global_rect().has_point(event.position): return
	for header in headers:
		if header.visible and header.get_global_rect().has_point(event.position): return
	owner_search.release_focus()

func feed_animal_key(event: InputEvent) -> bool:
	if not is_visible_in_tree() or state.kind != 2 or not event is InputEventKey or not event.pressed: return false
	if event.keycode == KEY_F and event.ctrl_pressed and not (event.alt_pressed or event.meta_pressed or event.shift_pressed):
		if owner_search.editable and not event.echo: owner_search.grab_focus()
		return true
	if owner_search.has_focus():
		owner_search.feed_key(event); return true
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed: return false
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		if not event.echo and not state.busy() and owner_selected >= 0 and owner_selected < state.rows.size():
			var row: Dictionary = state.rows[owner_selected]
			state.toggle_animal(int(row.get("entity",0)),int(row.id))
		return true
	var delta := 0
	match event.keycode:
		KEY_UP,KEY_8,KEY_KP_8: delta = -1
		KEY_DOWN,KEY_2,KEY_KP_2: delta = 1
		KEY_PAGEUP,KEY_9,KEY_KP_9: delta = -owner_scrollbar.page
		KEY_PAGEDOWN,KEY_3,KEY_KP_3: delta = owner_scrollbar.page
	if delta == 0: return false
	if state.busy() or choices.is_empty(): return true
	owner_selected = clampi(owner_selected+delta,0,choices.size()-1)
	refresh()
	var first: int = owner_scrollbar.first
	if owner_selected < first: first = owner_selected
	elif owner_selected >= first+owner_scrollbar.page: first = owner_selected-owner_scrollbar.page+1
	owner_scrollbar.move_to(first)
	return true

func feed_owner_key(event: InputEvent) -> bool:
	if state.kind == 2: return feed_animal_key(event)
	if not is_visible_in_tree() or state.kind != 1 or not event is InputEventKey or not event.pressed: return false
	if event.keycode == KEY_F and event.ctrl_pressed and not (event.alt_pressed or event.meta_pressed or event.shift_pressed):
		if owner_search.editable and not event.echo: owner_search.grab_focus()
		return true
	if owner_search.has_focus():
		owner_search.feed_key(event); return true
	if event.keycode == KEY_C and event.ctrl_pressed and not (event.alt_pressed or event.meta_pressed or event.shift_pressed):
		if not event.echo and not state.busy():
			var index := owner_selected - (1 if remove.visible else 0)
			if index >= 0 and index < state.rows.size(): focus_unit(int(state.rows[index].id))
		return true
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
		KEY_PAGEUP,KEY_9,KEY_KP_9: delta = -owner_scrollbar.page
		KEY_PAGEDOWN,KEY_3,KEY_KP_3: delta = owner_scrollbar.page
	if delta == 0: return false
	if state.busy(): return true
	var count: int = choices.size() + (1 if remove.visible else 0)
	if count == 0: return true
	owner_selected = clampi(owner_selected + delta,0,count-1)
	refresh()
	var first: int = owner_scrollbar.first
	if owner_selected < first: first = owner_selected
	elif owner_selected >= first + owner_scrollbar.page: first = owner_selected - owner_scrollbar.page + 1
	owner_scrollbar.move_to(first)
	return true

func add_animal_item_text(button: Button, text: String, color: Dictionary) -> void:
	if native_colors.size() != 16: return
	var line := Label.new(); line.name = "AnimalItemName"; line.text = text
	line.add_theme_font_size_override("font_size",12)
	line.position = Vector2(40,12); line.size = Vector2(text.length()*8,12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(line)
	line.add_theme_color_override("font_color",native_colors[int(color.foreground)+int(color.bright)*8])
	var background := ColorRect.new(); background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent = true; background.size = line.size
	background.visible = int(color.background) != 0; background.color = native_colors[int(color.background)]
	line.add_child(background)

func add_animal_text(button: Button, display: Dictionary) -> void:
	var colored: Array = []
	var first_row := 1 if bool(display.combined_fits) or str(display.warning).is_empty() else 0
	for index in 2:
		var line := Label.new(); line.name = "AnimalFirst" if index == 0 else "AnimalSecond"
		line.text = str(display.first_line if index == 0 else display.second_line)
		line.add_theme_font_size_override("font_size",12); line.clip_text = true
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(line)
		line.position = Vector2(40,(first_row+index)*12); line.size = Vector2(int(display.columns)*8,12)
		var background := ColorRect.new(); background.name = "GlyphBackground"
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE; background.show_behind_parent = true
		background.size = Vector2(mini(line.text.length(),int(display.columns))*8,12)
		line.add_child(background); colored.append(line)
	var warning := Label.new(); warning.name = "AnimalWarning"; warning.text = str(display.warning)
	warning.add_theme_font_size_override("font_size",12); warning.clip_text = true
	warning.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(warning)
	warning.position = Vector2(48,24); warning.size = Vector2((int(display.columns)-1)*8,12)
	if native_colors.size() == 16: warning.add_theme_color_override("font_color",native_colors[10])
	owner_color_rows.append({"button":button,"description":display.name_color,"lines":colored,"last":[]})
	apply_owner_colors(Time.get_ticks_msec())

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
	owner_color_rows.append({"button":button,"description":display.get("name_color",{}),"lines":colored,"last":[]})
	apply_owner_colors(Time.get_ticks_msec())

func update_animal_status(button: Button, row: Dictionary) -> void:
	var old_indicator := button.get_node_or_null("AnimalStatus") as TextureRect
	if old_indicator != null: old_indicator.hide(); old_indicator.texture = null
	var status: Dictionary = row.get("animal_status",{})
	var status_kind := int(status.get("kind",0))
	if status_kind in [1,2,3,5] or (status_kind == 4 and ((row.has("animal_container") and world.has_method("animal_container_icon")) or (row.has("animal_restraint") and world.has_method("animal_restraint_icon")))):
		var indicator := button.get_node_or_null("AnimalStatus") as TextureRect
		if indicator == null:
			indicator = TextureRect.new(); indicator.name = "AnimalStatus"; button.add_child(indicator)
		if status_kind == 5: indicator.texture = art.texture("MISSING_BUILDING")
		elif status_kind == 4 and row.has("animal_restraint"): indicator.texture = world.animal_restraint_icon(row.animal_restraint)
		elif status_kind == 4: indicator.texture = world.animal_container_icon(row.animal_container)
		else: indicator.texture = art.texture(["UNIT_SELECTOR_PASTURE","UNIT_SELECTOR_PIT","UNIT_SELECTOR_POND"][status_kind-1])
		indicator.position = Vector2(250 if cage_layout else 242,2); indicator.size = Vector2(32,32)
		indicator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; indicator.stretch_mode = TextureRect.STRETCH_SCALE
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE; indicator.show()

	var relation := int(status.get("containment",0)) if status_kind == 4 else 0
	var hover := button.get_node_or_null("AnimalContainmentHover")
	var visible_status := button.get_node_or_null("AnimalStatus") as TextureRect
	if visible_status == null or not visible_status.visible: relation = 0
	if hover != null and int(hover.get_meta("relation",0)) != relation:
		button.remove_child(hover); hover.queue_free(); hover = null
	if hover == null and relation in [1,2,3,4]: bind_containment_help(button,relation)

func refresh_animal_facts() -> void:
	if choices.size() != state.rows.size(): return
	for index in state.rows.size():
		if state.rows[index].id != cached_rows[index].id or state.rows[index].get("entity") != cached_rows[index].get("entity"): return
	for index in state.rows.size():
		var row: Dictionary = state.rows[index]; var previous: Dictionary = cached_rows[index]
		if row == previous: continue
		var button: Button = choices[index]
		if row.get("animal_display") != previous.get("animal_display") or row.get("animal_item_color") != previous.get("animal_item_color") or row.get("name") != previous.get("name"):
			owner_color_rows = owner_color_rows.filter(func(value): return value.button != button)
			for name in ["AnimalFirst","AnimalSecond","AnimalWarning","AnimalItemName"]:
				var child = button.get_node_or_null(name)
				if child != null: button.remove_child(child); child.queue_free()
			if row.get("animal_display") is Dictionary: add_animal_text(button,row.animal_display)
			if row.get("animal_item_color") is Dictionary: add_animal_item_text(button,str(row.get("name","")),row.animal_item_color)
		button.get_node("AnimalAssigned").texture = art.texture("LABOR_WORKER_ASSIGNED" if bool(row.get("assigned",false)) else "LABOR_WORKER_UNASSIGNED")
		if row.get("animal_status") != previous.get("animal_status") or row.get("animal_container") != previous.get("animal_container") or row.get("animal_restraint") != previous.get("animal_restraint"):
			update_animal_status(button,row)
		if index < portrait_slots.size():
			var slot: Dictionary = portrait_slots[index]
			if slot.recipe != row.get("sheet_icon",{}):
				slot.recipe = row.get("sheet_icon",{}); slot.loaded = false; slot.view.texture = null
		cached_rows[index] = row

func refresh_owner_facts() -> void:
	if state.kind == 2: refresh_animal_facts(); return
	if state.kind != 1 or choices.size() != state.rows.size(): return
	for index in state.rows.size():
		var row: Dictionary = state.rows[index]
		if int(row.id) != int(cached_rows[index].id): return
	for index in state.rows.size():
		var row: Dictionary = state.rows[index]
		if row == cached_rows[index]: continue
		var display: Dictionary = row.get("owner_display",{})
		var button: Button = choices[index]
		for line_index in 3:
			var line := button.get_node_or_null(["OwnerStatus","OwnerFirst","OwnerSecond"][line_index]) as Label
			if line == null: continue
			line.text = str(display.get(["status","first_line","second_line"][line_index],""))
			line.size.x = int(display.get("columns",0))*8
			if line_index > 0: line.get_node("GlyphBackground").size.x = mini(line.text.length(),int(display.get("columns",0)))*8
		if not display.is_empty() and not button.has_node("OwnerFirst"): add_owner_text(button,display)
		for colored in owner_color_rows:
			if colored.button == button:
				colored.description = display.get("name_color",{}); colored.last = []
		var stress := button.get_node("OwnerStress") as TextureRect
		var mood := int(row.get("mood",0))
		stress.visible = mood in range(1,8)
		stress.texture = art.texture("BUTTON_STRESS_%d" % (7-mood)) if stress.visible else null
		for slot in portrait_slots:
			if int(slot.id) == int(row.id) and slot.recipe != row.get("sheet_icon",{}):
				slot.recipe = row.get("sheet_icon",{}); slot.loaded = false
		cached_rows[index] = row
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
	# Native3ac445..3ac4cf: this picker keeps54 cells (52 with a scrollbar),
	# replacing the final three with dots on overflow. DF2UTF preserves
	# one codepoint per source CP437 cell. Use controls overdraw the name afterward.
	var caption := str(row.get("name",""))
	var scrollbar_width := 16 if state.rows.size() > 10 else 0
	var limit := 52 if scrollbar_width > 0 else 54
	if caption.length() > limit: caption = caption.left(limit-3)+"..."
	var button := row_button(caption)
	button.clip_text = true; button.focus_mode = Control.FOCUS_NONE
	for key in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:
		button.add_theme_color_override(key,Color.WHITE)
	var style: StyleBox = button.get_theme_stylebox("normal").duplicate()
	style.set_content_margin(SIDE_LEFT,56)
	style.set_content_margin(SIDE_RIGHT,8)
	for key in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(key,style)
	rows_box.add_child(button); choices.append(button)
	var entries := [[1,"SLEEP"],[2,"TRAIN"],[4,"INDIV_EQ"],[8,"SQUAD_EQ"]]
	if row.get("squad_symbol") is Dictionary:
		var symbol := TextureRect.new(); symbol.name = "SquadSymbol"
		symbol.position = Vector2(0,2); symbol.size = Vector2(32,32)
		symbol.texture = squad_symbols.texture(row.squad_symbol)
		symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(symbol)
	for index in entries.size():
		var entry: Array = entries[index]
		if (int(entry[0]) & state.squad_mask) == 0: continue
		var control := Button.new(); control.size = Vector2(32,36)
		control.focus_mode = Control.FOCUS_NONE
		control.position = Vector2((520 if state.squad_mask == 2 else 424+index*32)-scrollbar_width,0)
		control.set_meta("squad_use",int(entry[0]))
		for key in ["normal","hover","pressed","disabled","focus"]: control.add_theme_stylebox_override(key,StyleBoxEmpty.new())
		var use := int(row.get("squad_use",-1)); control.set_meta("unknown",use < 0)
		var icon := TextureRect.new(); icon.size = Vector2(32,36)
		icon.texture = art.texture("ZONE_SQUAD_"+str(entry[1])+("_ACTIVE" if use >= 0 and (use & int(entry[0])) != 0 else "_INACTIVE"))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(icon)
		control.pressed.connect(func(): state.toggle_squad(int(row.id),int(entry[0])))
		button.add_child(control); squad_buttons.append(control)
		bind_squad_help(control,int(entry[0]))

func bind_squad_help(control: Button, use: int) -> void:
	if native_help == null: return
	var owner := control.get_instance_id()
	control.mouse_entered.connect(func():
		if not control.disabled: native_help.enter_squad_use(owner,use))
	control.mouse_exited.connect(func(): native_help.leave(owner))
	control.visibility_changed.connect(func():
		if not control.is_visible_in_tree(): native_help.leave(owner))
	control.tree_exiting.connect(func(): native_help.leave(owner))

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
