extends Node
# Referenced views consume resident semantic publications; no transport ownership.
const Frame = preload("res://scripts/native_info_frame.gd")
const PAGES = ["Residents", "Work Details", "Work orders"]
signal focus_requested(tile: Vector3i)
signal inspect_requested(unit_id: int)
var world
var interaction
var ui_host
var modal_input := true
var panel: PanelContainer
var info_frame = Frame.new()
var play_enabled := true
var loading := false
var complete := false
var _resident_generation := -1
var epoch := 0
var page := "Residents"
var people: Array = []
var details: Array = []
var orders: Array = []
var selected_detail := -1
var rows: VBoxContainer
var detail_list: VBoxContainer
var split: HBoxContainer
var scroll: ScrollContainer
var search: LineEdit
var message: Label
var mode_label: Label
var refresh_button: Button
var _poll_time := 0.0
var resident_header: HBoxContainer
var footer: HBoxContainer
var footer_note: Label
var back_button: Button
var footer_inset: Control
var sort_key := ""
var sort_reverse := false
var selected_resident := -1
var resident_icons: Dictionary = {}
var resident_icon_controls: Dictionary = {}
const WORK_DETAIL_ART = ["MINERS","WOODCUTTERS","HUNTERS","PLANTERS","FISHERMEN","STONECUTTERS","ENGRAVERS","PLANT_GATHERERS","HAULERS","ORDERLIES","CUSTOM_1","CUSTOM_2","CUSTOM_3","CUSTOM_4","CUSTOM_5","CUSTOM_6","CUSTOM_7","CUSTOM_8","SIEGE_OPERATORS"]
var palette_loaded := false
var resident_icon_generations: Dictionary = {}
var resident_layout_width := -1.0
var resident_art_cache: Dictionary = {}

func label(parent: Node, text: String, expand := false) -> Label:
	var result := Label.new()
	result.text = text
	result.clip_text = true
	result.tooltip_text = text
	if expand: result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func _ready():
	var canvas := CanvasLayer.new(); canvas.layer = 2; add_child(canvas)
	panel = PanelContainer.new(); canvas.add_child(panel)
	var body := VBoxContainer.new(); panel.add_child(body)
	mode_label = label(body, "")
	resident_header = HBoxContainer.new(); resident_header.custom_minimum_size.y = 28; body.add_child(resident_header)
	split = HBoxContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(split)
	var left_scroll := ScrollContainer.new(); left_scroll.name = "Details"; left_scroll.custom_minimum_size.x = 250; left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; split.add_child(left_scroll)
	detail_list = VBoxContainer.new(); detail_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left_scroll.add_child(detail_list)
	scroll = ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; split.add_child(scroll)
	rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation", 2); scroll.add_child(rows)
	footer = HBoxContainer.new(); footer.custom_minimum_size.y = 64; footer.alignment = BoxContainer.ALIGNMENT_BEGIN; body.add_child(footer)
	footer.add_theme_constant_override("separation",0)
	footer_inset=Control.new();footer_inset.custom_minimum_size.x=16;footer.add_child(footer_inset)
	search = LineEdit.new(); search.placeholder_text = "Search"; search.custom_minimum_size.x = 260; footer.add_child(search)
	search.text_changed.connect(func(_text): render_rows())
	search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh_button = button(footer, "Refresh", refresh)
	footer_note = label(footer, "Read only", true)
	back_button = button(footer, "Back", close_panel)
	message = label(body, "")
	info_frame.install(panel, world, page)
	configure_residents()
	if world.has_method("ui_texture"): preload("res://scripts/creature_sheet_style.gd").scrollbar(scroll,world)
	panel.hide()

func set_info_page(value: String):
	if value not in PAGES: return
	var changed := page != value
	page = value
	info_frame.select(page)
	configure_residents()
	if changed:
		search.clear()
		selected_detail = -1
		if panel.visible: subscribe()

func open_panel():
	if not play_enabled: return
	if ui_host != null and not ui_host.activate(self): return
	interaction.cancel_selection()
	panel.show()
	subscribe()

func close_panel():
	world.demand_resident_info(0)
	if panel != null: panel.hide()
	if ui_host != null: ui_host.release(self)

func set_play_enabled(value: bool):
	play_enabled = value
	if not value: close_panel()

func subscribe():
	_resident_generation = -1
	world.demand_resident_info(PAGES.find(page)+1)
	read_resident_state()

func refresh():
	world.refresh_resident_info()
	read_resident_state()

func read_resident_state():
	if not panel.visible: return
	var state: Dictionary = world.resident_info_state()
	if int(state.get("demand",0)) != PAGES.find(page)+1: return
	loading = bool(state.get("loading",false))
	complete = bool(state.get("complete",false))
	var observed := int(state.get("world_epoch",0))
	var generation := int(state.get("generation",0))
	if generation != _resident_generation or observed != epoch:
		_resident_generation = generation
		if observed != epoch: resident_icons.clear(); resident_icon_generations.clear()
		epoch = observed
		var records: Dictionary = state.get("rows",{})
		var old_revision := -1
		for detail in details:
			if int(detail.index) == selected_detail: old_revision = int(detail.get("revision",-1))
		people = records.get("citizens",[])
		if complete and not palette_loaded and world.has_method("assets_root"):
			preload("res://scripts/native_creature_text.gd").load_text(world); palette_loaded = true
		details = records.get("details",[])
		orders = records.get("orders",[])
		# Keep local selection only when the native definition revision still matches.
		var selection_valid := false
		for detail in details:
			if int(detail.index) == selected_detail and old_revision >= 0 and int(detail.get("revision",-2)) == old_revision: selection_valid = true
		if not selection_valid: selected_detail = -1
		render_rows()
	refresh_button.disabled = loading
	var error := str(state.get("error",""))
	message.text = error if not error.is_empty() else "Refreshing..." if loading and complete else "Loading..." if loading else "Not loaded" if not complete else ""
	if state.get("stale",false) and complete: message.text = "Showing previous data. " + message.text
	message.visible = not message.text.is_empty()

func clear_children(parent: Node):
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func row_box() -> HBoxContainer:
	var background := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("232323") if rows.get_child_count()%2 == 0 else Color("1c1c1c")
	for side in [SIDE_LEFT,SIDE_RIGHT]: style.set_content_margin(side,8)
	background.add_theme_stylebox_override("panel",style)
	rows.add_child(background)
	var row := HBoxContainer.new(); row.custom_minimum_size.y = 40; background.add_child(row)
	return row

func matches(text: String) -> bool:
	return search.text.is_empty() or text.to_lower().contains(search.text.to_lower())

func citizen_row(citizen: Dictionary, assigned := false):
	if not matches(str(citizen.get("name",""))+" "+str(citizen.get("profession",""))+" "+str(citizen.get("job",""))): return
	var row := row_box()
	label(row, str(citizen.get("name","")), true)
	if page == "Residents":
		var activity := label(row,str(citizen.get("job","")),true)
		activity.add_theme_color_override("font_color",Color.CYAN)
	else: label(row,"Assigned" if assigned else "",true)
	var focus := button(row,"Show",func():
		var tile: Vector3i = world.unit_tile(int(citizen.id))
		if tile.x < 0: message.text = "This resident is no longer visible on the map."; return
		focus_requested.emit(tile); close_panel())
	focus.disabled = not bool(citizen.get("can_focus",false))
	focus.tooltip_text = "Show on map" if not focus.disabled else str(citizen.get("reason","Not on map"))

func render_rows():
	if rows == null: return
	resident_layout_width = -1
	resident_icon_controls.clear()
	clear_children(rows); clear_children(detail_list)
	split.get_node("Details").visible = page == "Work Details"
	mode_label.visible = page == "Work Details"
	if page == "Residents":
		for citizen in sorted_residents(): resident_row(citizen)
	elif page == "Work Details":
		if selected_detail < 0 and not details.is_empty(): selected_detail = int(details[0].index)
		for detail in details:
			var index := int(detail.index)
			var b := button(detail_list,str(detail.name),func(): selected_detail = index; render_rows())
			b.clip_text = true; b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.tooltip_text = str(detail.name)
			b.toggle_mode = true; b.button_pressed = index == selected_detail
		if selected_detail < 0 and not details.is_empty(): selected_detail = int(details[0].index)
		mode_label.text = ""
		for detail in details:
			if int(detail.index) != selected_detail: continue
			var mode := int(detail.get("mode",0))
			mode_label.text = str(detail.name)+"    "+["Default","Everybody does this","Nobody does this","Only selected do this"][clampi(mode,0,3)]
			mode_label.tooltip_text = ", ".join(detail.get("labor_names",[]))
			for citizen in people: citizen_row(citizen,int(citizen.id) in detail.get("assigned_units",[]))
	elif page == "Work orders":
		for order in orders:
			if not matches(str(order.get("name",""))): continue
			var row := row_box()
			label(row,"Approved" if order.get("validated",false) else "Pending").custom_minimum_size.x = 100
			var name_label := label(row,"%s\n%d/%d" % [order.get("name",""),order.get("remaining",0),order.get("total",0)],true)
			name_label.add_theme_color_override("font_color",Color.CYAN)
			label(row,"Can use any shop" if int(order.get("workshop_id",-1)) < 0 else "Workshop #%d" % int(order.workshop_id),true)
			var conditions: Array = order.get("conditions",[])
			var descriptions: PackedStringArray = []
			for condition in conditions: descriptions.append(str(condition.get("description","")))
			name_label.tooltip_text = "\n".join(descriptions) if not descriptions.is_empty() else str(order.get("name",""))
	if rows.get_child_count() == 0 and page != "Residents": label(rows,"No matching entries" if complete else "Not loaded")

func _process(delta: float):
	if panel == null or not panel.visible: return
	info_frame.layout(get_viewport().get_visible_rect().size)
	if page == "Residents":
		var logical: Vector2 = get_viewport().get_visible_rect().size / panel.get_parent().scale
		# Our current HUD is taller than native's 48px header. Keep the roster
		# below it rather than concealing the population/resource readouts.
		panel.position = Vector2(32,72)
		var desired_width := maxf(560,logical.x-256)
		update_resident_widths(desired_width)
		panel.size = Vector2(desired_width,maxf(320,logical.y-108))
		update_resident_icons()
	_poll_time += delta
	if _poll_time < .1: return
	_poll_time = 0
	read_resident_state()

func _unhandled_input(event):
	if ui_host != null and not ui_host.allows_panel_input(self): return
	if panel != null and panel.visible and (event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed)):
		close_panel(); get_viewport().set_input_as_handled()

func configure_residents():
	if resident_header == null: return
	var active := page == "Residents"
	resident_header.visible = active
	footer_note.visible = not active; back_button.visible = not active; refresh_button.visible = not active
	footer_inset.visible = active
	search.placeholder_text = "" if active else "Search"
	if active:
		var inset := StyleBoxTexture.new();inset.texture=info_frame.ui.texture("BUTTON_FILTER")
		inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
		for side in [SIDE_TOP,SIDE_BOTTOM]: inset.set_texture_margin(side,12);inset.set_content_margin(side,0)
		inset.set_content_margin(SIDE_LEFT,8);inset.set_content_margin(SIDE_RIGHT,40)
		for state in ["normal","focus"]: search.add_theme_stylebox_override(state,inset)
	else:
		for state in ["normal","focus"]: search.remove_theme_stylebox_override(state)
	search.custom_minimum_size = Vector2(312 if active else 260,36 if active else 32)
	panel.add_theme_font_size_override("font_size",12 if active else 16)
	# Theme lookup on child widgets uses the panel's scoped theme, not overrides.
	panel.theme = info_frame.ui.theme.duplicate()
	panel.theme.default_font_size = 12 if active else 16
	rows.add_theme_constant_override("separation",0 if active else 2)
	clear_children(resident_header)
	var spacer := Control.new(); spacer.custom_minimum_size.x = 40; resident_header.add_child(spacer)
	for entry in [["Name","name"],["Prof","profession"]]:
		var key: String = entry[1]
		var b := button(resident_header,str(entry[0]),func(): set_resident_sort(key))
		b.custom_minimum_size = Vector2(64,16); b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = str(entry[0]); b.icon = resident_strip(("SORT_DESCENDING_" if sort_reverse else "SORT_ASCENDING_")+("ACTIVE" if sort_key==key else "INACTIVE"),4)
		var sort_style := StyleBoxTexture.new(); sort_style.texture=resident_strip("SORT_TEXT_ACTIVE" if sort_key==key else "SORT_TEXT_INACTIVE",3)
		for side in [SIDE_LEFT,SIDE_RIGHT]: sort_style.set_texture_margin(side,8); sort_style.set_content_margin(side,0)
		for side in [SIDE_TOP,SIDE_BOTTOM]: sort_style.set_content_margin(side,0)
		for state in ["normal","hover","pressed","focus"]: b.add_theme_stylebox_override(state,sort_style)
		b.add_theme_constant_override("h_separation",0)
	var gap := Control.new(); gap.custom_minimum_size.x = 160; resident_header.add_child(gap)
	var activity := button(resident_header,"",func(): set_resident_sort("job")); activity.tooltip_text = "Activity"; activity.icon = resident_strip("SORT_DESCENDING_INACTIVE",4); activity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal","hover","pressed","focus"]: activity.add_theme_stylebox_override(state,StyleBoxEmpty.new())

func set_resident_sort(key: String):
	sort_reverse = not sort_reverse if sort_key==key else false
	sort_key = key
	configure_residents(); render_rows()

func sorted_residents() -> Array:
	var result := people.duplicate()
	if sort_key.is_empty(): return result
	result.sort_custom(func(a,b):
		var left := str(a.get(sort_key,"")); var right := str(b.get(sort_key,""))
		if left==right: return int(a.id)<int(b.id)
		return left.naturalnocasecmp_to(right)>0 if sort_reverse else left.naturalnocasecmp_to(right)<0)
	return result

static func resident_mood(stress: int) -> int:
	# DFHack Units::stress_cutoffs, reversed to the original stress icon order.
	var cutoffs := [50000,25000,10000,-10000,-25000,-50000,-100000]
	for i in cutoffs.size():
		if stress>=cutoffs[i]: return 6-i
	return 0

func resident_art(parent: Node, texture: Texture2D, extent: Vector2) -> TextureRect:
	var art := TextureRect.new(); art.texture = texture; art.custom_minimum_size = extent
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER; parent.add_child(art)
	return art

func resident_action(parent: Node, art: String, tip: String, callback: Callable) -> TextureButton:
	var b := TextureButton.new(); b.tooltip_text = tip; b.texture_normal = resident_action_texture(art)
	b.ignore_texture_size = true; b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(24,24); b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(callback); parent.add_child(b)
	return b

func resident_row(citizen: Dictionary):
	if not matches(str(citizen.get("name",""))+" "+str(citizen.get("profession",""))+" "+str(citizen.get("job",""))): return
	var id := int(citizen.id)
	var row: HBoxContainer
	if world.has_method("ui_texture"):
		row=preload("res://scripts/creature_sheet_style.gd").row(rows,world,36)
	else: row=row_box();row.custom_minimum_size.y=36
	row.get_parent().name="Resident_%d" % id
	if world.has_method("ui_texture"):
		var row_style = row.get_parent().get_theme_stylebox("panel").duplicate()
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: row_style.set_content_margin(side,0)
		row.get_parent().add_theme_stylebox_override("panel",row_style)
	row.add_theme_constant_override("separation",8)

	var picture := Panel.new(); picture.custom_minimum_size=Vector2(32,36); row.add_child(picture)
	var picture_style := StyleBoxTexture.new(); picture_style.texture=info_frame.ui.texture("BUTTON_PICTURE_BOX")
	for side in [SIDE_LEFT,SIDE_RIGHT]: picture_style.set_texture_margin(side,8)
	for side in [SIDE_TOP,SIDE_BOTTOM]: picture_style.set_texture_margin(side,12)
	picture.add_theme_stylebox_override("panel",picture_style)
	var sprite := resident_art(picture,resident_icons.get(id),Vector2(32,32)); sprite.position=Vector2(0,2)
	resident_icon_controls[id] = sprite
	var name_text := str(citizen.get("name",""))
	var profession := str(citizen.get("profession",""))
	if not profession.is_empty() and not name_text.to_lower().ends_with(profession.to_lower()): name_text += ", " + profession
	var name_label := label(row,name_text); name_label.custom_minimum_size.x = clampf((get_viewport().get_visible_rect().size.x-256)*.255,150,242); name_label.custom_minimum_size.y = 24; name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_constant_override("line_spacing",0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; name_label.max_lines_visible = 2
	var color_id := int(citizen.get("profession_color",-1))
	if color_id>=0 and color_id<16: name_label.add_theme_color_override("font_color",preload("res://scripts/native_creature_text.gd").colors[color_id])
	var focus := resident_action(row,"STOCKS_RECENTER","Show on map",func():
		var tile: Vector3i = world.unit_tile(id)
		if tile.x>=0: focus_requested.emit(tile); close_panel())
	focus.disabled = not bool(citizen.get("can_focus",false))
	resident_action(row,"STOCKS_VIEW_ITEM","View creature",func(): selected_resident=id; inspect_requested.emit(id))
	var job := str(citizen.get("job",""))
	var idle := int(citizen.get("job_type",-2))==-1 and job in ["","No current job","No job"]
	var activity := label(row,"No job" if idle else job); activity.custom_minimum_size.x = 288
	activity.add_theme_color_override("font_color",Color.GREEN if citizen.get("social_activity",false) else Color.YELLOW if idle else Color.CYAN)
	if bool(citizen.get("has_stress",false)):
		var mood := resident_mood(int(citizen.get("stress",0)))
		resident_art(row,info_frame.ui.texture("BUTTON_STRESS_%d" % mood),Vector2(24,24))
	# These are assignment readouts, not equipment or active editing buttons.
	var assignment_clip := Control.new(); assignment_clip.custom_minimum_size=Vector2(160,36); assignment_clip.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	assignment_clip.clip_contents=true; row.add_child(assignment_clip)
	var assignments := HBoxContainer.new(); assignments.add_theme_constant_override("separation",0); assignment_clip.add_child(assignments)
	if citizen.has("only_assigned_jobs"):
		var mode_art := "WORKER_ONLY_DO_ASSIGNED_JOBS" if citizen.only_assigned_jobs else "WORKER_DO_ANY_AVAILABLE_JOB"
		var mode := resident_art(assignments,info_frame.ui.texture(mode_art),Vector2(32,36))
		mode.tooltip_text="Only assigned jobs" if citizen.only_assigned_jobs else "Any available job"
	for detail in citizen.get("assigned_details",[]):
		var icon := int(detail.get("icon",-1))
		if icon<0 or icon>=WORK_DETAIL_ART.size(): continue
		var badge := resident_art(assignments,info_frame.ui.texture("WORK_DETAIL_"+WORK_DETAIL_ART[icon]),Vector2(32,36))
		badge.tooltip_text=str(detail.get("name",""))

func update_resident_icons():
	if not world.has_method("resident_icon"): return
	var budget := 2
	var visible_rect := scroll.get_global_rect()
	for id in resident_icon_controls:
		if budget==0: break
		var art: TextureRect = resident_icon_controls[id]
		if int(resident_icon_generations.get(id,-2))==_resident_generation or not visible_rect.intersects(art.get_global_rect()): continue
		var texture: Texture2D = world.resident_icon(int(id))
		resident_icons[id]=texture; resident_icon_generations[id]=_resident_generation; art.texture=texture; budget-=1


func update_resident_widths(width: float):
	if is_equal_approx(resident_layout_width,width): return
	resident_layout_width = width
	for id in resident_icon_controls:
		var row: HBoxContainer = resident_icon_controls[id].get_parent().get_parent()
		row.get_child(1).custom_minimum_size.x = clampf((width-32)*.255,150,242)
		row.get_child(4).custom_minimum_size.x = clampf(width-row.get_child(1).custom_minimum_size.x-364,120,288)

func resident_action_texture(key: String) -> Texture2D:
	if resident_art_cache.has(key): return resident_art_cache[key]
	var source: Texture2D = info_frame.ui.texture(key)
	if source==null: return null
	# Original STOCKS action cells have transparent padding above/below the
	# 24px frame. Trim only alpha-empty margins, preserving source pixels.
	var atlas := AtlasTexture.new(); atlas.atlas=source; atlas.region=source.get_image().get_used_rect()
	resident_art_cache[key]=atlas
	return atlas

func resident_strip(key: String, count: int) -> Texture2D:
	if resident_art_cache.has(key): return resident_art_cache[key]
	if not world.has_method("ui_texture"): return null
	var first: Texture2D = world.ui_texture(key,0)
	if first==null: return null
	var cell := first.get_size()
	var image := Image.create(int(cell.x)*count,int(cell.y),false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
	for i in count:
		var part: Texture2D = world.ui_texture(key,i)
		if part!=null: image.blit_rect(part.get_image(),Rect2i(Vector2i.ZERO,Vector2i(cell)),Vector2i(int(cell.x)*i,0))
	var texture := ImageTexture.create_from_image(image); resident_art_cache[key]=texture
	return texture
