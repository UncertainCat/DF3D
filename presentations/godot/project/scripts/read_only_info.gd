extends Node
# Referenced views consume resident semantic publications; no transport ownership.
const Frame = preload("res://scripts/native_info_frame.gd")
const PAGES = ["Work Details"]
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
var page := "Work Details"
var people: Array = []
var details: Array = []
var detail_list_revision: int = 0
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
var _layout_key: Array = []
var footer: HBoxContainer
var footer_note: Label
var back_button: Button
var footer_inset: Control
var palette_loaded := false

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
	configure_work_details()
	if world.has_method("ui_texture"): preload("res://scripts/creature_sheet_style.gd").scrollbar(scroll,world)
	panel.hide()

func set_info_page(value: String):
	if value not in PAGES: return
	var changed := page != value
	page = value
	info_frame.select(page)
	configure_work_details()
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
	world.demand_resident_info(2)
	read_resident_state()

func refresh():
	world.refresh_resident_info()
	read_resident_state()

func read_resident_state():
	if not panel.visible: return
	var state: Dictionary = world.resident_info_state()
	if int(state.get("demand",0)) != 2: return
	loading = bool(state.get("loading",false))
	complete = bool(state.get("complete",false))
	var observed := int(state.get("world_epoch",0))
	var generation := int(state.get("generation",0))
	if generation != _resident_generation or observed != epoch:
		_resident_generation = generation
		epoch = observed
		var records: Dictionary = state.get("rows",{})
		var old_revision := -1
		for detail in details:
			if int(detail.index) == selected_detail: old_revision = int(detail.get("revision",-1))
		people = records.get("citizens",[])
		if complete and not palette_loaded and world.has_method("assets_root"):
			preload("res://scripts/native_creature_text.gd").load_text(world); palette_loaded = true
		details = records.get("details",[])
		detail_list_revision = int(state.get("detail_list_revision",0)) if complete else 0
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
	label(row,"Assigned" if assigned else "",true)
	var focus := button(row,"Show",func():
		var tile: Vector3i = world.unit_tile(int(citizen.id))
		if tile.x < 0: message.text = "This resident is no longer visible on the map."; return
		focus_requested.emit(tile); close_panel())
	focus.disabled = not bool(citizen.get("can_focus",false))
	focus.tooltip_text = "Show on map" if not focus.disabled else str(citizen.get("reason","Not on map"))

func render_rows():
	if rows == null: return
	clear_children(rows); clear_children(detail_list)
	split.get_node("Details").visible = page == "Work Details"
	mode_label.visible = page == "Work Details"
	if page == "Work Details":
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
	if rows.get_child_count() == 0: label(rows,"No matching entries" if complete else "Not loaded")

func _process(delta: float):
	if panel == null or not panel.visible: return
	var view: Vector2 = get_viewport().get_visible_rect().size
	# Layout only reruns when its inputs change; icon loading stays incremental.
	var key := [view, preload("res://scripts/presentation_settings.gd").effective_scale_vector(view), page]
	if key != _layout_key:
		_layout_key = key
		info_frame.layout(view)
	_poll_time += delta
	if _poll_time < .1: return
	_poll_time = 0
	read_resident_state()

func _unhandled_input(event):
	if ui_host != null and not ui_host.allows_panel_input(self): return
	if panel != null and panel.visible and (event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed)):
		close_panel(); get_viewport().set_input_as_handled()

func configure_work_details():
	search.custom_minimum_size = Vector2(260,32)
	panel.add_theme_font_size_override("font_size",16)
	panel.theme = info_frame.ui.theme.duplicate()
	panel.theme.default_font_size = 16
