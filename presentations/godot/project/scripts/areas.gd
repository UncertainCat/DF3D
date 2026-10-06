extends Node3D
signal focus_requested(tile: Vector3i)
const Contract = preload("res://scripts/management_contract.gd")
const Action = Contract.ManagementAction
const Status = Contract.ManagementStatus
# Area semantics come from the versioned management contract.
const Selection = preload("res://scripts/interaction_state.gd")
const MenuData = preload("res://scripts/area_menu_data.gd")
var menu_data: Dictionary = MenuData.read()
var category_labels: Array[String] = MenuData.category_labels_by_bit(menu_data)
var world
var hud
var launcher_destination := "Stockpiles"
var camera: Camera3D
var interaction
var panel: PanelContainer
var content: VBoxContainer
var stockpile_view: Control
var candidates_state = preload("res://scripts/area_candidates_state.gd").new()
var candidates_view: PanelContainer
var portraits = preload("res://scripts/area_portraits.gd").new()
var portrait_timer := 0.0
var details_state = preload("res://scripts/location_details_state.gd").new()
var details_view: Control
var details_layer: Control
var details_parent_shield: Control
var details_origin := ""
var details_parent_ticket := 0
var details_parent_refresh_again := false
var locations_state = preload("res://scripts/area_locations_state.gd").new()
var locations_view: PanelContainer
var zone_menu: Control
var zone_draft: Dictionary = {}
var paint_view: Control
var paint_state = preload("res://scripts/area_paint_state.gd").new()
var zone_paint: Node
var paint_counts = preload("res://scripts/area_paint_counts.gd").new()
var paint_hover := Vector3i(-1,-1,-1)
var multi_state = preload("res://scripts/area_multi_state.gd").new()
var multi_second_corner := false
var paint_tool := "rectangle"
var paint_erasing := false
var paint_second_corner := false
var paint_saved_corner := Vector3i(-1,-1,-1)
var paint_last := Vector3i(-1,-1,-1)
var paint_preview: MeshInstance3D
var paint_lookup := false
var paint_lookup_tile := Vector3i(-1,-1,-1)
var storage_view: PanelContainer
var links_view: PanelContainer
var observed_links: Array = []
var links_pending: Dictionary = {}
var links_delay := -1.0
var links_cursor := 0
var links_revision := 0
var links_picking := false
var links_give := true
var settings_state = preload("res://scripts/area_settings_state.gd").new()
var settings_view: Control
var stockpile_page := "types"
var rename_field: LineEdit
var kind_picker: OptionButton
var zone_picker: OptionButton
var area_picker: OptionButton
var candidate_picker: OptionButton
var search: LineEdit
var message: Label
var detail: Label
var categories: Array[CheckBox] = []
var category_grid: GridContainer
var storage: Dictionary = {}
var storage_box: VBoxContainer
var zone_box: VBoxContainer
var links_only: CheckBox
var active: CheckBox
var link_row: VBoxContainer
var owner_row: HBoxContainer
var create_button: Button
var apply_button: Button
var remove_button: Button
var more_button: Button
var overlap_button: Button
var areas: Array = []
var choices: Array = []
var zone_types: Array = []
var selected: Dictionary = {}
var request_ticket := 0
var _request_action := -1
var _candidate_poll_request: Dictionary = {}
var _candidate_poll_remaining := 0.0
var draft_generation := 0
var request_problem := false
var action_service
var ui_host
var modal_input := true
var available := false
var mode := "inspect"
var play_enabled := true
var origin := Vector3i(-1, -1, -1)
var rectangle := Rect2i()
var drag_start := Vector3i(-1, -1, -1)
var dragging := false
var current_z := -1
var _layout_view := Vector2(-1, -1)
var next_cursor := 0
var overlap_cursor := 0
var overlap_tile := Vector3i()
var zone_overlaps: Array = []
var zone_lookup_rows: Array = []
var outline: MeshInstance3D


func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func option(parent: Node) -> OptionButton:
	var p := OptionButton.new()
	p.fit_to_longest_item = false
	p.clip_text = true
	p.custom_minimum_size.x = 310
	p.item_selected.connect(func(i): p.tooltip_text = p.get_item_text(i))
	parent.add_child(p)
	return p


func _ready() -> void:
	details_state.configure(action_service)
	paint_counts.service = action_service
	paint_counts.changed.connect(_show_paint_counts)
	action_service.session_changed.connect(_session_changed)
	tree_exiting.connect(_detach_draft)
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	panel = PanelContainer.new()
	# Deferred font/container sizing can retire a temporary scrollbar after
	# the first layout. Reapply native bounds when that minimum changes.
	panel.minimum_size_changed.connect(func(): _layout_view = Vector2(-1,-1))
	panel.custom_minimum_size.x = 390
	panel.hide()
	canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	content = box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	stockpile_view = preload("res://scripts/area_stockpile_view.gd").new()
	box.add_child(stockpile_view)
	stockpile_view.configure(world)
	stockpile_view.preset_selected.connect(choose_preset)
	stockpile_view.control_selected.connect(stockpile_control)
	storage_view = preload("res://scripts/area_storage_view.gd").new()
	canvas.add_child(storage_view); storage_view.configure(world); storage_view.hide()
	storage_view.value_requested.connect(set_storage_value)
	storage_view.done.connect(func(): storage_view.cancel_edit(); handle_back())
	links_view = preload("res://scripts/area_links_view.gd").new()
	canvas.add_child(links_view); links_view.configure(world); links_view.hide()
	links_view.pick_requested.connect(begin_link_pick)
	links_view.unlink_requested.connect(func(row): change_link(int(row.id),int(row.kind),int(row.direction) == 1,true))
	links_view.more_requested.connect(func(): if links_cursor != 0 and links_pending.is_empty() and request_ticket == 0: read_links(links_cursor))
	links_view.done.connect(handle_back)
	paint_view = preload("res://scripts/area_paint_view.gd").new()
	box.add_child(paint_view); paint_view.configure(world,menu_data.paint_tools,canvas)
	paint_view.accept_requested.connect(accept_paint)
	paint_view.multi_requested.connect(begin_multi)
	paint_view.undo_requested.connect(undo_multi)
	paint_view.paint_requested.connect(leave_multi_for_paint)
	paint_view.cancel_requested.connect(cancel_zone_paint)
	zone_menu = preload("res://scripts/area_zone_menu_view.gd").new()
	box.add_child(zone_menu); zone_menu.configure(world)
	zone_menu.type_selected.connect(choose_zone_type)
	zone_menu.control_selected.connect(zone_control)
	zone_menu.rename_requested.connect(rename_area)
	zone_menu.setting_requested.connect(set_zone_setting)
	candidates_view = preload("res://scripts/area_candidates_view.gd").new()
	canvas.add_child(candidates_view); candidates_view.configure(world,candidates_state); candidates_view.hide()
	candidates_view.focus_requested.connect(func(tile): focus_requested.emit(tile))
	locations_view = preload("res://scripts/area_locations_view.gd").new()
	canvas.add_child(locations_view); locations_view.configure(world,locations_state); locations_view.hide()
	locations_state.request_ready.connect(send)
	locations_state.failed_page.connect(func(reason): request_problem = true; message.text = reason; update_controls())
	locations_view.done.connect(handle_back)
	locations_view.details_requested.connect(open_location_details)
	details_layer=Control.new();canvas.add_child(details_layer);details_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# Native Details keeps the zone panel visible but ignores its pointer input.
	details_parent_shield=Control.new();details_layer.add_child(details_parent_shield)
	details_parent_shield.mouse_filter=Control.MOUSE_FILTER_STOP
	details_layer.hide()
	candidates_state.request_ready.connect(send)
	candidates_state.failed_page.connect(func(reason): request_problem = true; message.text = reason; update_controls())
	paint_view.tool_selected.connect(select_paint_tool)
	settings_view = preload("res://scripts/area_settings_view.gd").new()
	box.add_child(settings_view); settings_view.configure(world,settings_state)
	settings_state.request_ready.connect(send)
	settings_state.failed_page.connect(func(reason):
		request_problem = true; message.text = reason; update_controls())
	rename_field = LineEdit.new()
	rename_field.max_length = 128
	rename_field.text_submitted.connect(rename_area)
	box.add_child(rename_field)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Stockpiles / zones"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	button(header, "Close", close_panel)
	var nav := HBoxContainer.new()
	box.add_child(nav)
	button(nav, "New", new_area).tooltip_text = "Start a new rectangular stockpile or zone"
	var inspect_button := button(
		nav,
		"Inspect",
		func():
			mode = "inspect"
			cancel_drag()
			message.text = "Click a tile to inspect every overlapping area"
	)
	inspect_button.tooltip_text = "Click a tile to choose existing stockpiles and overlapping zones"
	button(nav, "Refresh", refresh)
	kind_picker = option(box)
	kind_picker.add_item("Stockpile", 0)
	kind_picker.add_item("Zone", 1)
	kind_picker.item_selected.connect(func(_i): new_area())
	zone_picker = option(box)
	area_picker = option(box)
	area_picker.item_selected.connect(func(i): use_area(areas[i]))
	overlap_button = button(
		box, "More overlapping areas", func(): inspect_tile(overlap_tile, overlap_cursor)
	)
	detail = Label.new()
	detail.custom_minimum_size.x = 310
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	category_grid = GridContainer.new()
	category_grid.columns = 2
	box.add_child(category_grid)
	for text in category_labels:
		var c := CheckBox.new()
		c.text = text
		c.clip_text = true
		c.tooltip_text = text
		c.add_theme_font_size_override("font_size", 12)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.x = 145
		category_grid.add_child(c)
		categories.append(c)
	storage_box = VBoxContainer.new()
	box.add_child(storage_box)
	for key in ["barrels", "bins", "wheelbarrows"]:
		var row := HBoxContainer.new()
		storage_box.add_child(row)
		var label := Label.new()
		label.text = key.capitalize()
		label.custom_minimum_size.x = 145
		row.add_child(label)
		var amount := SpinBox.new()
		amount.min_value = 0
		amount.max_value = 961
		amount.step = 1
		row.add_child(amount)
		storage[key] = amount
	links_only = CheckBox.new()
	links_only.text = "Take only from links"
	storage_box.add_child(links_only)
	zone_box = VBoxContainer.new()
	box.add_child(zone_box)
	active = CheckBox.new()
	active.text = "Zone active"
	zone_box.add_child(active)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	create_button = button(actions, "Create area", create_area)
	apply_button = button(actions, "Apply edits", apply_edits)
	remove_button = button(actions, "Remove area", remove_area)
	var target_label := Label.new()
	target_label.text = "Link / owner search"
	box.add_child(target_label)
	search = LineEdit.new()
	search.placeholder_text = "Name or numeric ID"
	search.max_length = 128
	box.add_child(search)
	search.text_submitted.connect(func(_text): search_candidates())
	search.text_changed.connect(func(_text): _cancel_candidate_poll())
	var search_row := HBoxContainer.new()
	box.add_child(search_row)
	button(search_row, "Search", search_candidates)
	more_button = button(search_row, "More", func(): search_candidates(next_cursor))
	candidate_picker = option(box)
	link_row = VBoxContainer.new()
	box.add_child(link_row)
	var give_row := HBoxContainer.new()
	link_row.add_child(give_row)
	button(give_row, "Give to", func(): link(true, false))
	button(give_row, "Stop giving", func(): link(true, true))
	var take_row := HBoxContainer.new()
	link_row.add_child(take_row)
	button(take_row, "Take from", func(): link(false, false))
	button(take_row, "Stop taking", func(): link(false, true))
	owner_row = HBoxContainer.new()
	box.add_child(owner_row)
	button(owner_row, "Assign owner", assign_owner)
	button(owner_row, "Clear owner", func(): assign_owner(true))
	message = Label.new()
	message.custom_minimum_size.x = 310
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	var limits := Label.new()
	limits.custom_minimum_size.x = 310
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limits.text = "Turning a category on or off keeps any custom filters you set in Dwarf Fortress. Material and quality filters, resizing, and animal, squad or location assignments are managed in Dwarf Fortress."
	limits.add_theme_font_size_override("font_size", 12)
	box.add_child(limits)
	outline = MeshInstance3D.new()
	add_child(outline)
	paint_preview = MeshInstance3D.new(); add_child(paint_preview)
	var ui := preload("res://scripts/original_ui.gd").new()
	ui.configure(world)
	ui.apply(self)
	new_area()


func open_panel() -> void:
	if play_enabled and panel.visible: close_panel(); return
	if not play_enabled or not ui_host.activate(self): return
	panel.show()
	current_z = int(world.get_top_z())
	new_area()
	available = false
	if world.is_live():
		send({"action": Action.Catalog})
	else:
		message.text = "Offline preview only; native area creation and settings unavailable"
	update_controls()


func set_area_kind(value: int) -> void:
	if value not in [0,1]: return
	if kind_picker.selected != value and panel.visible: close_panel()
	kind_picker.select(value)
	launcher_destination = "Stockpiles" if value == 0 else "Zones"

func close_panel() -> void:
	_release_zone_paint("exit")
	_finish_multi()
	portraits.clear(world)
	zone_overlaps.clear(); zone_lookup_rows.clear()
	locations_state.clear(); locations_view.hide()
	candidates_state.clear(); candidates_view.hide()
	paint_state.clear(); paint_view.tools.hide()
	clear_links(); links_view.hide()
	storage_view.cancel_edit(); storage_view.hide()
	settings_state.clear()
	panel.hide()
	world.set_zone_overlays_visible(false)
	cancel_drag()
	ui_host.release(self)


func set_play_enabled(value: bool) -> void:
	play_enabled = value
	if not value:
		world.set_zone_overlays_visible(false)
		if panel.visible: close_panel()


func cancel_drag() -> void:
	if paint_preview != null: paint_preview.mesh = null
	_detach_draft()
	dragging = false
	rectangle = Rect2i()
	origin = Vector3i(-1, -1, -1)
	draw_outline()


func new_area() -> void:
	paint_saved_corner = Vector3i(-1,-1,-1)
	_release_zone_paint("exit")
	_finish_multi()
	zone_overlaps.clear(); zone_lookup_rows.clear()
	locations_state.clear()
	candidates_state.clear()
	zone_menu.cancel_edit()
	zone_draft.clear()
	launcher_destination = "Stockpiles" if kind_picker.selected == 0 else "Zones"
	paint_state.clear()
	clear_links()
	storage_view.cancel_edit()
	settings_state.clear()
	stockpile_page = "types"
	selected = {}
	areas = []
	area_picker.clear()
	mode = "create"
	cancel_drag()
	for i in categories.size():
		categories[i].set_pressed_no_signal(i == 13)
	for key in storage:
		storage[key].max_value = 961
		storage[key].value = 0
	active.set_pressed_no_signal(true)
	links_only.set_pressed_no_signal(false)
	message.text = "Drag a rectangle on the map, then Create area" if message != null else ""
	if kind_picker.selected == 0:
		var bounds: Vector3 = world.map_size()
		paint_state.open({},Vector2i(int(bounds.x),int(bounds.z)),int(world.get_top_z()))
		paint_tool = "rectangle"; paint_erasing = false; paint_second_corner = false; mode = "paint"; stockpile_page = "repaint"
	else:
		mode = "zone_select"
	update_controls()


func zone_control(key: String) -> void:
	if key in ["previous","next"]:
		if request_ticket != 0 or zone_overlaps.size() < 2: return
		for index in zone_overlaps.size():
			if int(zone_overlaps[index].id) == int(selected.get("id",-1)):
				var target: Dictionary = zone_overlaps[posmod(index+(-1 if key == "previous" else 1),zone_overlaps.size())].duplicate(true)
				target.revision = 0
				use_area(target)
				return
		return
	if selected.is_empty() or int(selected.kind) != 1 or not available or request_ticket != 0: return
	if key=="location_details":
		open_location_details({"site_id":selected.get("location_site_id",-1),"id":selected.get("location_id",-1)},true)
		return
	if key != "location": locations_state.clear()
	if key not in ["owner","animals","squads"]: candidates_state.clear(); stockpile_page = "types"
	match key:
		"owner":
			if not bool(selected.get("owner_allowed",false)): return
			stockpile_page = "owner"; update_controls(); candidates_state.open(selected)
		"animals":
			stockpile_page = "animals"; update_controls(); candidates_state.open(selected,2)
		"squads":
			var mask := 15
			for row in zone_types:
				if int(row.id) == int(selected.zone_type) and row.name == "ArcheryRange": mask = 2
			stockpile_page = "squads"; update_controls(); candidates_state.open(selected,3,{"squad_mask":mask})
		"location":
			stockpile_page = "location"; update_controls(); locations_state.open(selected)
		"rename": zone_menu.begin_rename()
		"repaint": begin_paint()
		"remove": remove_area()
		"suspend":
			var request := selected_request(Action.AreaUpdate)
			request.active = 0 if bool(selected.active) else 1
			send(request)
	update_controls()

func set_zone_setting(key: String, value: int) -> void:
	if selected.is_empty() or int(selected.kind) != 1 or request_ticket != 0 or not available: return
	var settings: Dictionary = selected.get("zone_settings",{})
	if not settings.has(key) or int(settings[key]) < 0 or int(settings[key]) == value: return
	var allowed := {"pond_mode":[1,2],"facing":[1,2,3,4],"tomb_citizens":[0,1],"tomb_pets":[0,1],"gather_trees":[0,1],"gather_shrubs":[0,1]}
	if not allowed.has(key) or value not in allowed[key]: return
	var request := selected_request(Action.AreaUpdate)
	request.operation = Contract.AreaOperation.ZoneSettings
	request.zone_settings = {key:value}
	send(request)

func native_zone_panel() -> bool:
	if selected.is_empty(): return false
	# Only observed catalog entries can select a native zone panel.
	for row in zone_types:
		if int(row.id) == int(selected.get("zone_type",-1)):
			return str(row.name) in ["Bedroom","DiningHall","WaterSource","Dungeon","FishingArea","SandCollection","Dormitory","Dump","AnimalTraining","ClayCollection","Pen","Pond","Barracks","ArcheryRange","Tomb","PlantGathering","MeetingHall","Office"]
	return false

func open_location_details(target: Dictionary, assigned := false) -> void:
	if not panel.visible or not ui_host.allows_panel_input(self) or not available or request_ticket!=0 or not details_origin.is_empty():return
	if selected.is_empty() or int(selected.get("kind",-1))!=1:return
	if assigned:
		if target.get("site_id")!=selected.get("location_site_id") or target.get("id")!=selected.get("location_id"):return
	else:
		if stockpile_page!="location" or locations_state.busy():return
		var observed:=false
		for row in locations_state.rows:
			if row.get("site_id")==target.get("site_id") and row.get("id")==target.get("id"):observed=true;break
		if not observed:return
	if int(target.get("site_id",-1))<0 or int(target.get("id",-1))<0:return
	if details_view==null:
		details_view=preload("res://scripts/location_details_view.gd").new();details_layer.add_child(details_view)
		details_view.configure(world,details_state,hud.native_help if hud!=null else null)
		details_view.staff_candidates_view.input_allowed=func():return ui_host.allows_panel_input(self)
		details_view.staff_workflow.applied.connect(_refresh_details_parent)
		details_view.layout(get_viewport().get_visible_rect().size)
	details_origin="zone" if assigned else "chooser"
	details_parent_shield.position=panel.position;details_parent_shield.size=panel.size
	details_state.open(target)
	update_controls()

func close_location_details() -> void:
	details_origin=""
	details_state.close()
	if details_layer!=null:details_layer.hide()

func _refresh_details_parent() -> void:
	# A staff edit can change the zone owner's profession. Reobserve the parent
	# without reopening Details or disturbing its chooser/selector ownership.
	if not panel.visible or selected.is_empty() or int(selected.get("kind",-1))!=1:return
	if details_parent_ticket!=0:details_parent_refresh_again=true;return
	var owner:=draft_generation
	var id:=int(selected.id)
	details_parent_refresh_again=false
	details_parent_ticket=action_service.submit("areas",{"action":Action.AreaInspect,"kind":1,"id":id},func(ticket,result,_sent):
		if ticket!=details_parent_ticket or owner!=draft_generation:return
		details_parent_ticket=0
		if not panel.visible or int(selected.get("id",-1))!=id or int(selected.get("kind",-1))!=1:return
		if int(result.get("status",Status.Rejected))==Status.Ok:
			for observed in result.get("area",{}).get("areas",[]):
				if int(observed.get("id",-1))!=id or int(observed.get("kind",-1))!=1:continue
				selected=observed.duplicate(true)
				for i in areas.size():
					if int(areas[i].get("id",-1))==id and int(areas[i].get("kind",-1))==1:areas[i]=selected.duplicate(true)
				if not locations_state.area.is_empty():locations_state.area=selected.duplicate(true)
				update_controls()
				break
		if details_parent_refresh_again:_refresh_details_parent())

func choose_zone_type(id: int) -> void:
	if not available or request_ticket != 0 or kind_picker.selected != 1: return
	_finish_multi()
	for row in zone_types:
		if int(row.id) != id: continue
		_release_zone_paint("exit")
		locations_state.clear(); candidates_state.clear(); stockpile_page = "types"
		zone_overlaps.clear(); zone_lookup_rows.clear()
		selected = {}; zone_menu.cancel_edit(); cancel_drag()
		zone_draft = row.duplicate(true)
		var bounds: Vector3 = world.map_size()
		paint_state.open({},Vector2i(int(bounds.x),int(bounds.z)),int(world.get_top_z()))
		paint_tool = "rectangle"; paint_erasing = false; paint_second_corner = false; mode = "paint"
		_start_zone_paint({})
		dragging = false; update_controls(); draw_outline()
		return


func send(request: Dictionary) -> void:
	if not play_enabled or not panel.visible or request_ticket != 0: return
	paint_counts.clear()
	var multi := int(request.get("operation",0)) in [Contract.AreaOperation.MultiCreate,Contract.AreaOperation.MultiUndo,Contract.AreaOperation.MultiFinish]
	if not multi and int(request.action) in [Action.AreaUpdate, Action.AreaDelete, Action.AreaLink] and int(request.get("expected_revision", 0)) <= 0:
		message.text = "Inspect this area before changing it"
		return
	_cancel_candidate_poll()
	request_problem = false
	_request_action = int(request.action)
	var generation := draft_generation
	request_ticket = action_service.submit(Contract.domain_of(int(request.action)), request,
		func(ticket, result, sent):
			if generation == draft_generation and ticket == request_ticket and panel.visible:
				request_ticket = 0
				_request_action = -1
				_receive_result(result, sent))
	message.text = "" if multi else "Waiting for Dwarf Fortress"
	update_controls()


func selected_request(action: int) -> Dictionary:
	var data := {"action": action, "id": selected.id, "kind": selected.kind}
	if action in [Action.AreaUpdate, Action.AreaDelete, Action.AreaLink]:
		data.expected_revision = int(selected.get("revision", 0))
	return data


func choose_preset(preset: int) -> void:
	if selected.is_empty() or int(selected.kind) != 0 or not available or request_ticket != 0: return
	if preset == 0:
		stockpile_page = "settings"
		settings_state.open(selected)
		update_controls()
		return
	var known := false
	for row in menu_data.presets:
		if int(row.preset) == preset: known = true
	if not known: return
	var request := selected_request(Action.AreaUpdate)
	request.operation = Contract.AreaOperation.Preset
	request.preset = preset
	send(request)


func stockpile_control(key: String) -> void:
	if selected.is_empty() or int(selected.kind) != 0 or not available or request_ticket != 0: return
	match key:
		"remove": remove_area()
		"links_only":
			var request := selected_request(Action.AreaUpdate)
			request.links_only = int(not bool(selected.links_only))
			send(request)
		"rename":
			stockpile_page = "rename"
			rename_field.text = str(selected.name)
			update_controls()
			rename_field.grab_focus()
			rename_field.select_all()
		"repaint": begin_paint()
		"containers", "links":
			storage_view.cancel_edit()
			stockpile_page = key
			if key == "links": clear_links(); read_links()
			update_controls()


func begin_paint() -> void:
	_finish_multi()
	if selected.is_empty() or request_ticket != 0 or not available: return
	_release_zone_paint("exit")
	_detach_draft(); clear_links(); settings_state.clear(); storage_view.cancel_edit()
	if int(selected.kind) == 1:
		for row in zone_types:
			if int(row.id) == int(selected.zone_type): zone_draft = row.duplicate(true)
	var bounds: Vector3 = world.map_size()
	paint_state.open(selected,Vector2i(int(bounds.x),int(bounds.z)),int(selected.origin.z))
	origin = selected.origin; rectangle = Rect2i(origin.x,origin.y,int(selected.width),int(selected.height))
	paint_tool = "rectangle"; paint_erasing = false; paint_second_corner = false; mode = "paint"; stockpile_page = "repaint"
	if int(selected.kind) == 1: _start_zone_paint(selected)
	dragging = false; update_controls(); draw_outline()

func begin_multi() -> void:
	if not available or request_ticket != 0 or not selected.is_empty() or kind_picker.selected != 1: return
	var furniture := int({"Bedroom":1,"Office":2,"DiningHall":3,"Tomb":4}.get(str(zone_draft.get("name","")),0))
	var bounds: Vector3 = world.map_size()
	if furniture == 0: return
	if zone_paint != null:
		# Native080650 discards ordinary Paint on this switch. Wait for the
		# deletion receipt before Multi can submit a room selection.
		zone_paint.finish("multi"); update_controls(); return
	# Native083030 carries Rectangle's saved corner while Brush is selected.
	# A held Brush pointer is not a pending rectangle.
	if paint_tool == "brush":
		dragging = paint_saved_corner.z >= 0
		if dragging: drag_start = paint_saved_corner
		paint_saved_corner = Vector3i(-1,-1,-1)
	_finish_multi(); _detach_draft()
	if not multi_state.open(furniture,Vector2i(int(bounds.x),int(bounds.z))): return
	# Native080928 shares the pending rectangle corner across Paint/Multi.
	paint_state.clear(); multi_second_corner = false; paint_preview.mesh = null
	mode = "multi"; message.text = ""; request_problem = false
	if dragging: draw_paint_preview(drag_start)
	update_controls(); draw_outline()

func _finish_multi() -> void:
	if multi_state.interaction_id <= 0: return
	var request: Dictionary = multi_state.finish()
	_detach_draft()
	# The service keeps a sent request until terminal, then dispatches Finish.
	# A queued unsent selection is cancelled by detach instead.
	if action_service != null: action_service.submit("areas",request,Callable())

func leave_multi_for_paint() -> void:
	if mode != "multi" or request_ticket != 0: return
	var shared_corner := drag_start if dragging else Vector3i(-1,-1,-1)
	_finish_multi()
	var bounds: Vector3 = world.map_size()
	paint_state.open({},Vector2i(int(bounds.x),int(bounds.z)),int(world.get_top_z()))
	# Preserve the shared first corner and Paint erase state across this switch.
	paint_second_corner = false; mode = "paint"
	_start_zone_paint({})
	if paint_tool == "brush":
		paint_saved_corner = shared_corner
		dragging = false
	paint_preview.mesh = null
	if dragging: draw_paint_preview(drag_start)
	update_controls(); draw_outline()

func undo_multi() -> void:
	if mode != "multi" or not available or request_ticket != 0: return
	var request: Dictionary = multi_state.undo()
	if not request.is_empty(): send(request)
	update_controls()

func multi_pointer(tile: Vector3i, pressed: bool) -> void:
	if mode != "multi" or not multi_state.ready() or request_ticket != 0: return
	if pressed:
		if tile.z < 0: return
		multi_second_corner = dragging
		if not dragging: drag_start = tile; dragging = true
		draw_paint_preview(tile)
	elif dragging:
		if not multi_second_corner and tile == drag_start: return
		dragging = false; paint_preview.mesh = null
		var request: Dictionary = multi_state.selection(drag_start,tile)
		if not request.is_empty(): send(request)
		update_controls()

func _start_zone_paint(observed: Dictionary) -> void:
	paint_saved_corner = Vector3i(-1,-1,-1)
	_release_zone_paint("exit")
	var owner = preload("res://scripts/area_zone_paint_session.gd").new()
	action_service.add_child(owner)
	var bounds: Vector3 = world.map_size()
	owner.configure(action_service,observed,int(zone_draft.get("id",-1)),Vector2i(int(bounds.x),int(bounds.z)),int(world.get_top_z()))
	zone_paint = owner; paint_state = owner.geometry
	owner.changed.connect(_zone_paint_changed.bind(owner))
	owner.finished.connect(_zone_paint_finished.bind(owner))
	owner.failed.connect(_zone_paint_failed.bind(owner))

func _release_zone_paint(destination: String) -> void:
	if zone_paint == null: return
	var owner := zone_paint
	zone_paint = null
	paint_state = preload("res://scripts/area_paint_state.gd").new()
	if is_instance_valid(owner) and not owner.stopped: owner.finish(destination)

func _zone_paint_changed(owner: Node) -> void:
	if zone_paint != owner or not panel.visible: return
	draw_outline(); update_controls()

func _zone_paint_finished(destination: String, observed: Dictionary, owner: Node) -> void:
	if zone_paint != owner: return
	zone_paint = null
	paint_state = preload("res://scripts/area_paint_state.gd").new()
	if destination == "multi": begin_multi()
	elif destination == "accept" and not observed.is_empty(): use_area(observed,false)
	elif destination in ["cancel","remove"]: new_area()
	else: close_panel()

func _zone_paint_failed(result: Dictionary, owner: Node) -> void:
	if zone_paint != owner: return
	zone_paint = null
	request_problem = true
	message.text = str(result.get("message",""))
	update_controls()

func cancel_zone_paint() -> void:
	if kind_picker.selected != 1: return
	if zone_paint != null:
		_release_zone_paint("cancel")
	new_area()

func _paint_stroke(first: Vector3i, last: Vector3i) -> bool:
	if zone_paint != null: return zone_paint.stroke(first,last,paint_erasing)
	return paint_state.stroke(first,last,paint_erasing)

func accept_paint() -> void:
	if mode == "paint" and zone_paint != null:
		if not available: return
		if zone_paint.finish("accept"):
			dragging = false; paint_preview.mesh = null; update_controls()
		return
	if mode != "paint" or dragging or not available or request_ticket != 0: return
	if not paint_state.prepare():
		message.text = paint_state.problem; request_problem = not paint_state.problem.is_empty(); update_controls(); return
	send(paint_state.next_request(kind_picker.selected,int(zone_draft.get("id",-1))))

func select_paint_tool(key: String) -> void:
	if mode != "paint" or not available or request_ticket != 0: return
	if key == "remove":
		if zone_paint != null: zone_paint.finish("remove")
		else: remove_area()
		return
	if key == "erase":
		# Native072013 retains the mode and pending first corner on this toggle.
		paint_erasing = not paint_erasing
	elif key in ["rectangle","brush"] and key != paint_tool:
		if zone_paint != null:
			if paint_tool == "rectangle":
				paint_saved_corner = drag_start if dragging else Vector3i(-1,-1,-1)
				dragging = false
			else:
				dragging = paint_saved_corner.z >= 0
				if dragging: drag_start = paint_saved_corner
				paint_saved_corner = Vector3i(-1,-1,-1)
		else: dragging = false
		paint_tool = key; paint_second_corner = false
		paint_preview.mesh = null
	update_controls()

func paint_pointer(tile: Vector3i, pressed: bool) -> void:
	if zone_paint != null and (zone_paint.stopped or not zone_paint.ending.is_empty()): return
	paint_hover = tile
	if tile.z != paint_state.z:
		# Native084658 ignores other-plane clicks without losing Rectangle's corner.
		if zone_paint == null or paint_tool != "rectangle": dragging = false
		paint_preview.mesh = null; update_controls(); return
	if zone_paint != null and paint_tool == "rectangle":
		if pressed:
			if dragging:
				zone_paint.rectangle(drag_start,tile,paint_erasing)
				dragging = false; paint_preview.mesh = null
			else:
				drag_start = tile; dragging = true; draw_paint_preview(tile)
		# Native release only releases the mouse; the first corner survives.
		draw_outline(); update_controls(); return
	if pressed:
		paint_second_corner = dragging and paint_tool == "rectangle"
		if not paint_second_corner: drag_start = tile
		paint_last = tile; dragging = true
		if paint_tool != "rectangle": _paint_stroke(tile,tile)
		else: draw_paint_preview(tile)
	elif dragging:
		if paint_tool == "rectangle":
			if not paint_second_corner and tile == drag_start:
				update_controls(); return
			if zone_paint != null: zone_paint.rectangle(drag_start,tile,paint_erasing)
			else: paint_state.rectangle(drag_start,tile,paint_erasing)
		else:
			if paint_last.z != tile.z: paint_last = tile
			if zone_paint == null: _paint_stroke(paint_last,tile)
		dragging = false
		paint_preview.mesh = null
	draw_outline(); update_controls()

func map_paint_pointer(tile: Vector3i, pressed: bool) -> void:
	var lookup: bool = kind_picker.selected == 0 and pressed and not paint_lookup and selected.is_empty() and paint_state.cells.is_empty() and tile.z == paint_state.z
	paint_pointer(tile,pressed)
	if lookup:
		# Preserve the local gesture while resolving the initial map hit. The
		# read can finish after release; Accept stays unavailable until then.
		paint_lookup = true; paint_lookup_tile = tile
		send({"action":Action.AreaInspectAtTile,"origin":tile,"cursor":0})

func paint_motion(tile: Vector3i) -> void:
	paint_hover = tile
	if not dragging:
		_sync_paint_counts(); return
	if tile.z != paint_state.z:
		# Resume with a new segment after returning from an invalid map pick.
		paint_last = Vector3i(-1,-1,-1); paint_preview.mesh = null; _sync_paint_counts(); return
	if paint_tool == "rectangle": draw_paint_preview(tile); _sync_paint_counts(); return
	if paint_last.z != tile.z: paint_last = tile
	if _paint_stroke(paint_last,tile):
		draw_outline(); update_controls()
	paint_last = tile
	_sync_paint_counts()

func _show_paint_counts() -> void:
	if paint_view != null and mode == "paint" and kind_picker.selected == 1:
		paint_view.set_counts(str(zone_draft.get("label","")),paint_counts.values)

func _sync_paint_counts() -> void:
	if not play_enabled or not panel.visible or not ui_host.allows_panel_input(self) or mode != "paint" or kind_picker.selected != 1 or not available or request_ticket != 0 or paint_state.stopped or not paint_state.pending.is_empty():
		paint_counts.clear(); return
	var preview: Dictionary = {}
	var hover := paint_hover
	if hover.z == paint_state.z and hover.x >= 0 and hover.y >= 0 and hover.x < paint_state.map_size.x and hover.y < paint_state.map_size.y:
		var first: Vector3i = drag_start if dragging and paint_tool == "rectangle" else hover
		var low := Vector2i(mini(first.x,hover.x),mini(first.y,hover.y))
		var size := Vector2i(absi(first.x-hover.x)+1,absi(first.y-hover.y)+1)
		if first.z == hover.z and low.x >= 0 and low.y >= 0 and size.x <= 256 and size.y <= 256 and size.x*size.y <= 32768:
			preview = {"x":low.x,"y":low.y,"width":size.x,"height":size.y}
	var key := [draft_generation,paint_state.geometry_generation,paint_state.z,int(world.get_top_z()),int(zone_draft.get("id",-1)),paint_tool,paint_erasing,preview]
	if key != paint_counts.identity:
		var request := {"action":Action.AreaInspect,"operation":Contract.AreaOperation.PaintCounts,"kind":1,
			"zone_type":int(zone_draft.get("id",-1)),"paint_z":paint_state.z,"spans":paint_state.spans_for(paint_state.cells)}
		if not preview.is_empty(): request.paint_preview = preview
		paint_counts.demand(key,request)
	_show_paint_counts()

func draw_paint_preview(tile: Vector3i) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true; material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	mesh.surface_set_color(Color(0.95,0.75,0.15))
	var left := mini(drag_start.x,tile.x); var right := maxi(drag_start.x,tile.x)+1
	var top := mini(drag_start.y,tile.y); var bottom := maxi(drag_start.y,tile.y)+1
	var y := tile.z+float(Df3dWorld.floor_height())+0.025
	var a := Vector3(left,y,top); var b := Vector3(right,y,top)
	var c := Vector3(right,y,bottom); var d := Vector3(left,y,bottom)
	for point in [a,b,b,c,c,d,d,a]: mesh.surface_add_vertex(point)
	mesh.surface_end(); paint_preview.mesh = mesh

func clear_links() -> void:
	observed_links = []; links_pending = {}; links_delay = -1
	links_cursor = 0; links_revision = 0; links_picking = false

func read_links(cursor := 0) -> void:
	if selected.is_empty() or request_ticket != 0: return
	var request := selected_request(Action.AreaInspect)
	request.operation = Contract.AreaOperation.Links
	request.expected_revision = int(selected.revision)
	request.cursor = cursor
	if cursor != 0: request.expected_list_revision = links_revision
	links_pending = request.duplicate(true); links_delay = -1
	send(request)

func begin_link_pick(give: bool) -> void:
	if selected.is_empty() or not available or request_ticket != 0 or not links_pending.is_empty(): return
	links_picking = true; links_give = give; mode = "link_pick"
	update_controls()

func link_target_tile(tile: Vector3i, cursor := 0) -> void:
	if not links_picking or selected.is_empty(): return
	overlap_tile = tile
	send({"action":Action.AreaInspectAtTile,"origin":tile,"cursor":cursor})

func change_link(id: int, kind: int, give: bool, unlink: bool) -> void:
	if selected.is_empty() or int(selected.kind) != 0 or not available or request_ticket != 0 or kind not in [0,2] or id < 0: return
	if id == int(selected.id):
		message.text = "Links require two different stockpiles"; request_problem = true; update_controls(); return
	var request := selected_request(Action.AreaLink)
	request.link_id = id; request.give = give; request.unlink = unlink
	if kind == 2:
		# WorkshopLink's first endpoint is the workshop, so its direction is
		# opposite the direction displayed from this stockpile's perspective.
		request.operation = Contract.AreaOperation.WorkshopLink
		request.kind = 2; request.id = id; request.link_id = int(selected.id); request.give = not give
	send(request)


func rename_area(value: String) -> void:
	if selected.is_empty(): return
	var request := selected_request(Action.AreaUpdate)
	request.operation = Contract.AreaOperation.Rename
	request.name = value
	send(request)


func set_storage_value(key: String, value: int) -> void:
	if selected.is_empty() or int(selected.kind) != 0 or key not in ["barrels","bins","wheelbarrows"] or request_ticket != 0 or not available: return
	if not selected.has("tile_count"): return
	var cap := mini(32767,maxi(0,int(selected.tile_count) - (1 if key == "wheelbarrows" else 0)))
	if value < 0 or value > cap or value == int(selected[key]): return
	var request := selected_request(Action.AreaUpdate)
	request[key] = value
	send(request)


func category_mask() -> int:
	var mask := 0
	for i in categories.size():
		if categories[i].button_pressed:
			mask |= 1 << i
	return mask


func create_area() -> void:
	if mode == "paint":
		accept_paint(); return
	if not available or not rectangle.has_area():
		return
	var data: Dictionary = {
		"action": Action.AreaCreate,
		"kind": kind_picker.selected,
		"origin": origin,
		"width": rectangle.size.x,
		"height": rectangle.size.y
	}
	if kind_picker.selected == 0:
		data.categories = category_mask()
		for key in storage:
			data[key] = int(storage[key].value)
		data.links_only = int(links_only.button_pressed)
	else:
		if zone_picker.selected < 0:
			return
		data.zone_type = zone_picker.get_selected_id()
		data.active = int(active.button_pressed)
	send(data)


func edit_request() -> Dictionary:
	if selected.is_empty():
		return {}
	var data := selected_request(Action.AreaUpdate)
	if selected.kind == 0:
		var mask := category_mask()
		data.categories = mask
		data.changed_categories = mask ^ int(selected.categories)
		for key in storage:
			if int(storage[key].value) != int(selected[key]):
				data[key] = int(storage[key].value)
		if links_only.button_pressed != bool(selected.links_only):
			data.links_only = int(links_only.button_pressed)
	elif active.button_pressed != bool(selected.active):
		data.active = int(active.button_pressed)
	return data


func apply_edits() -> void:
	var data := edit_request()
	if not data.is_empty():
		send(data)


func refresh() -> void:
	if not selected.is_empty():
		send(selected_request(Action.AreaInspect))


func remove_area() -> void:
	if not selected.is_empty():
		send(selected_request(Action.AreaDelete))


func inspect_tile(tile: Vector3i, cursor := 0) -> void:
	if request_ticket != 0: return
	if cursor == 0: zone_lookup_rows.clear(); zone_overlaps.clear()
	# Keep the native empty zone chooser visible while its read is pending.
	mode = "zone_select" if selected.is_empty() and kind_picker.selected == 1 else "inspect"
	overlap_tile = tile
	send({"action": Action.AreaInspectAtTile, "origin": tile, "cursor": cursor})


func search_candidates(cursor := 0) -> void:
	if selected.is_empty():
		return
	if request_ticket != 0 and _request_action == Action.AreaCandidates:
		_detach_draft()
	_cancel_candidate_poll()
	send({"action": Action.AreaCandidates, "kind": selected.kind, "query": search.text, "cursor": cursor})


func link(give: bool, unlink: bool) -> void:
	if selected.is_empty() or selected.kind != 0 or candidate_picker.selected < 0:
		return
	var data := selected_request(Action.AreaLink)
	data.link_id = choices[candidate_picker.selected].id
	data.give = give
	data.unlink = unlink
	send(data)


func assign_owner(clear := false) -> void:
	if selected.is_empty() or not selected.owner_allowed:
		return
	if not clear and candidate_picker.selected < 0:
		return
	var data := selected_request(Action.AreaUpdate)
	data.owner_id = -1 if clear else choices[candidate_picker.selected].id
	send(data)


func identity_label(label: String, id: int) -> String:
	var suffix := " #%d" % id
	if label.ends_with(suffix + suffix):
		return label.trim_suffix(suffix)
	return label if label.ends_with(suffix) else "%s (#%d)" % [label, id]


func use_area(a: Dictionary, inspect_revision := true) -> void:
	_release_zone_paint("exit")
	_finish_multi()
	var member := false
	for row in zone_overlaps:
		if int(a.kind) == 1 and int(row.id) == int(a.id): member = true; break
	if not member: zone_overlaps.clear()
	locations_state.clear()
	candidates_state.clear()
	zone_menu.cancel_edit()
	paint_state.clear()
	paint_preview.mesh = null
	_detach_draft()
	selected = a.duplicate(true)
	stockpile_page = "types"
	kind_picker.select(int(a.kind))
	launcher_destination = "Stockpiles" if int(a.kind) == 0 else "Zones"
	mode = "inspect"
	origin = a.origin
	rectangle = Rect2i(origin.x, origin.y, a.width, a.height)
	for i in categories.size():
		categories[i].set_pressed_no_signal((int(a.categories) & (1 << i)) != 0)
	for key in storage:
		storage[key].max_value = maxi(
			961, maxi(int(a[key]), mini(32767, int(a.width) * int(a.height)))
		)
		storage[key].value = int(a[key])
	links_only.set_pressed_no_signal(a.links_only)
	active.set_pressed_no_signal(a.active)
	detail.text = (
		"%s, %dx%d at z%d\n%s"
		% [
			identity_label(a.name, a.id),
			a.width,
			a.height,
			a.origin.z,
			(
				("Gives: %s\nTakes: %s" % [str(a.gives), str(a.takes)])
				if a.kind == 0
				else ("Owner: %s (#%d)" % [a.owner_name, a.owner_id])
			)
		]
	)
	choices = []
	candidate_picker.clear()
	next_cursor = 0
	update_controls()
	draw_outline()
	if inspect_revision and int(a.get("revision", 0)) == 0 and available:
		refresh()


func update_controls() -> void:
	if create_button == null:
		return
	for child in content.get_children(): child.show()
	var pile := kind_picker.selected == 0
	world.set_zone_overlays_visible(play_enabled and panel.visible and not pile)
	category_grid.visible = pile
	storage_box.visible = pile
	zone_box.visible = not pile
	zone_picker.visible = not pile and selected.is_empty()
	area_picker.visible = not areas.is_empty()
	link_row.visible = pile and not selected.is_empty()
	owner_row.visible = not selected.is_empty() and bool(selected.get("owner_allowed", false))
	create_button.disabled = (
		not available or request_ticket != 0 or not selected.is_empty() or not rectangle.has_area()
	)
	create_button.visible = selected.is_empty()
	apply_button.visible = not selected.is_empty()
	remove_button.visible = not selected.is_empty()
	apply_button.disabled = not available or request_ticket != 0 or selected.is_empty() or int(selected.get("revision", 0)) <= 0
	remove_button.disabled = apply_button.disabled
	more_button.disabled = request_ticket != 0 or next_cursor == 0
	overlap_button.disabled = request_ticket != 0 or overlap_cursor == 0
	overlap_button.visible = overlap_cursor != 0
	kind_picker.disabled = request_ticket != 0
	zone_picker.disabled = request_ticket != 0
	area_picker.disabled = request_ticket != 0
	for category in categories:
		category.disabled = request_ticket != 0
	links_only.disabled = request_ticket != 0
	active.disabled = request_ticket != 0
	for key in storage:
		storage[key].editable = request_ticket == 0
	var native_types := pile and not selected.is_empty() and stockpile_page in ["types", "rename", "containers", "links"]
	var native_settings := pile and not selected.is_empty() and stockpile_page == "settings"
	var native_paint := mode in ["paint","multi"]
	var native_zones := not pile and (mode == "zone_select" or (mode == "inspect" and native_zone_panel()))
	for child in content.get_children():
		# Transitional secondary pages are replaced independently; the type panel
		# already uses its native hierarchy and actual preset semantics.
		if child not in [stockpile_view, rename_field, message] and native_types: child.hide()
		if child not in [settings_view,message] and native_settings: child.hide()
		if child not in [paint_view,message] and native_paint: child.hide()
		if child not in [zone_menu,message] and native_zones: child.hide()
	zone_menu.visible = native_zones
	if native_zones: zone_menu.display(zone_types,available and request_ticket == 0 and (selected.is_empty() or int(selected.get("revision",0)) > 0),selected)
	zone_menu.set_overlap_navigation(zone_overlaps.size() > 1,available and request_ticket == 0)
	paint_view.set_zone(zone_draft if not pile else {})
	paint_view.visible = native_paint
	paint_view.tools.visible = panel.visible and native_paint
	if mode == "multi": paint_view.display_multi(multi_state,available and request_ticket == 0)
	elif native_paint:
		var ready: bool = not paint_state.cells.is_empty() and (zone_paint != null or (not dragging and paint_state.cells != paint_state.original))
		var editable: bool = available and request_ticket == 0 and not paint_state.stopped and (zone_paint == null or zone_paint.ending.is_empty())
		paint_view.display(paint_tool,ready,editable,not selected.is_empty(),paint_erasing,zone_paint != null and not zone_paint.area.is_empty())
	_sync_paint_counts()
	locations_view.visible = panel.visible and not pile and not selected.is_empty() and stockpile_page == "location"
	if details_layer!=null:
		details_layer.visible=panel.visible and not details_origin.is_empty()
		if details_layer.visible:locations_view.hide()
	# This installed frame is stable; avoid invalidating child layout every tick.
	if locations_view.visible and not locations_view.has_theme_stylebox_override("panel"):
		locations_view.add_theme_stylebox_override("panel",locations_view.panel_style())
	candidates_view.visible = panel.visible and not pile and not selected.is_empty() and stockpile_page in ["owner","animals","squads"]
	if candidates_view.visible: candidates_view.add_theme_stylebox_override("panel",stockpile_view.panel_style())
	stockpile_view.visible = native_types
	settings_view.visible = native_settings
	storage_view.visible = panel.visible and native_types and stockpile_page == "containers"
	links_view.visible = panel.visible and native_types and stockpile_page == "links"
	if links_view.visible:
		links_view.add_theme_stylebox_override("panel",stockpile_view.panel_style())
		links_view.display(observed_links,links_picking,links_give,available and request_ticket == 0 and links_pending.is_empty())
		links_view.size = Vector2.ZERO
	if storage_view.visible:
		storage_view.add_theme_stylebox_override("panel",stockpile_view.panel_style())
		storage_view.size = Vector2.ZERO
		storage_view.display(selected,available and request_ticket == 0 and int(selected.get("revision",0)) > 0)
	rename_field.visible = native_types and stockpile_page == "rename"
	rename_field.editable = request_ticket == 0
	if native_types: stockpile_view.display(selected, available and request_ticket == 0 and int(selected.get("revision",0)) > 0)
	if native_zones:
		panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
		message.visible = request_ticket != 0 or request_problem
	elif native_types or native_settings or native_paint:
		panel.add_theme_stylebox_override("panel",stockpile_view.panel_style())
		message.visible = request_ticket != 0 or request_problem
	else:
		panel.remove_theme_stylebox_override("panel")
	if mode == "multi": message.hide()
	_layout_view = Vector2(-1,-1)


func _cancel_candidate_poll() -> void:
	_candidate_poll_request.clear()
	_candidate_poll_remaining = 0.0


func _poll_candidates(delta: float) -> void:
	if _candidate_poll_request.is_empty(): return
	if not available or selected.is_empty() or not world.is_live() or str(_candidate_poll_request.get("query", "")) != search.text:
		_cancel_candidate_poll()
		return
	if request_ticket != 0: return
	_candidate_poll_remaining -= maxf(0.0, delta)
	if _candidate_poll_remaining > 0.000001: return
	var request := _candidate_poll_request.duplicate(true)
	_cancel_candidate_poll()
	send(request)


func _poll_portraits(delta: float) -> void:
	portrait_timer -= maxf(0,delta)
	if portrait_timer > 0: return
	portrait_timer = 0.1
	var slots: Array = []
	if candidates_view.visible:
		var clip: Rect2 = candidates_view.scroll.get_global_rect()
		for slot in candidates_view.portrait_slots:
			if clip.intersects(slot.view.get_global_rect()): slots.append(slot)
	elif zone_menu.visible and not selected.is_empty() and int(selected.get("owner_id",-1)) >= 0:
		slots.append({"id":int(selected.owner_id),"view":zone_menu.owner_portrait})
	portraits.poll(world,slots)

func _exit_tree() -> void:
	_release_zone_paint("exit")
	portraits.clear(world)

func _process(delta: float) -> void:
	if not play_enabled or not panel.visible: return
	_poll_portraits(delta)
	var view := get_viewport().get_visible_rect().size
	if view != _layout_view:
		_layout_view = view
		panel.custom_minimum_size.x = 940 if settings_view.visible else (324 if stockpile_view.visible else 390)
		var panel_height := 452.0
		if rename_field.visible: panel_height += 40
		if message.visible: panel_height += maxf(36, message.get_combined_minimum_size().y)
		panel.size = Vector2(panel.custom_minimum_size.x, minf(panel_height, view.y - 64) if stockpile_view.visible else maxf(220, view.y - 64))
		if settings_view.visible: panel.size.y = minf(704,view.y - 64)
		if paint_view.visible:
			panel.custom_minimum_size.x = 324
			panel.size = Vector2(324,(68 if kind_picker.selected == 0 else 188) + (36 if message.visible else 0))
		if zone_menu.visible:
			panel.custom_minimum_size.x = 324
			panel.size = Vector2(324,minf(584+(36 if message.visible else 0),view.y-64))
		if kind_picker.selected == 0: paint_view.tools.position = Vector2(minf(view.x/2,view.x-136),view.y-76)
		panel.position = Vector2(34, 54)
		storage_view.position = Vector2(panel.position.x + panel.size.x + 8,panel.position.y)
		links_view.position = storage_view.position
		locations_view.position = Vector2(368,52); locations_view.size = Vector2(328,420)
		if details_view!=null:details_view.layout(view)
		details_parent_shield.position=panel.position;details_parent_shield.size=panel.size
		candidates_view.position = Vector2(370,54)
		candidates_view.size = Vector2(576,420) if stockpile_page == "squads" else Vector2(388 if stockpile_page == "animals" else 588,704)
	if paint_view.tools.visible and kind_picker.selected == 0 and hud != null:
		var anchor: Rect2 = hud.launcher_rect(launcher_destination)
		if anchor.has_area():
			var factor := anchor.size.y / 36.0
			paint_view.tools.scale = Vector2.ONE * factor
			paint_view.tools.position = Vector2(clampf(anchor.position.x,0,maxf(0,view.x-paint_view.tools.size.x*factor)),anchor.position.y-38*factor)
	var z := int(world.get_top_z())
	if z != current_z:
		current_z = z
		if mode == "paint":
			# Native keeps the footprint and repaint identity when changing levels.
			# An empty new painter follows the view; existing geometry stays on its
			# own plane. Do not detach a pending read or mutation on camera movement.
			paint_preview.mesh = null
			paint_last = Vector3i(-1,-1,-1)
			paint_hover = Vector3i(-1,-1,-1)
			if paint_state.area.is_empty() and paint_state.cells.is_empty() and paint_state.pending.is_empty() and request_ticket == 0 and (zone_paint == null or zone_paint.can_follow_elevation()):
				paint_state.z = z
				# Native084202 preserves the corner while Brush hides Rectangle.
				if paint_saved_corner.z >= 0: paint_saved_corner.z = z
				if dragging and paint_tool == "rectangle": drag_start.z = z
				else: dragging = false
			elif zone_paint == null or paint_tool != "rectangle": dragging = false
			draw_outline(); update_controls()
		elif mode == "multi":
			# Native keeps the first corner and completes on the ending elevation.
			if dragging: drag_start.z = z
			paint_preview.mesh = null
			draw_outline(); update_controls()
		else:
			zone_overlaps.clear(); zone_lookup_rows.clear()
			cancel_drag(); update_controls()
	if stockpile_page in ["owner","animals","squads"] and request_ticket == 0: candidates_state.poll(delta)
	_sync_paint_counts()
	paint_counts.poll(delta)
	if stockpile_page == "location" and request_ticket == 0: locations_state.poll(delta)
	_poll_candidates(delta)
	if stockpile_page == "settings" and request_ticket == 0: settings_state.poll(delta)
	if stockpile_page == "links" and request_ticket == 0 and links_delay >= 0:
		links_delay -= maxf(0,delta)
		if links_delay <= 0.000001:
			links_delay = -1
			if not links_pending.is_empty(): send(links_pending.duplicate(true))

func _receive_result(s: Dictionary, _request: Dictionary) -> void:
	if int(_request.get("operation",0)) in [Contract.AreaOperation.MultiCreate,Contract.AreaOperation.MultiUndo]:
		if mode != "multi": return
		multi_state.accept(s,_request)
		message.text = ""; request_problem = false
		update_controls(); draw_outline(); return
	message.text = str(s.get("message", "Request ended"))
	request_problem = int(s.get("status", Status.Rejected)) != Status.Ok
	if int(s.get("status", Status.Rejected)) != Status.Ok:
		if int(s.get("status", Status.Rejected)) == Status.Rejected and stockpile_page == "settings" and int(_request.get("action",-1)) == Action.AreaInspect and message.text in ["Area changed; inspect again","List changed; refresh"] and settings_state.recover_read(_request):
			request_problem = false
			update_controls()
			return
		if interaction.audio != null:
			interaction.audio.cue("rejected")
		if int(s.get("status", Status.Rejected)) == Status.Rejected and message.text in ["Area no longer exists","Area is not visible","Area kind changed; inspect again"]:
			var reason := message.text
			available = false
			new_area()
			paint_state.stop(reason)
			message.text = reason; request_problem = true
			update_controls()
			return
		zone_lookup_rows.clear()
		paint_lookup = false
		if mode == "paint": paint_state.stop(message.text)
		links_pending = {}; links_delay = -1
		if stockpile_page == "settings": settings_state.reject()
		if stockpile_page == "location": locations_state.reject(message.text)
		if stockpile_page in ["owner","animals","squads"]: candidates_state.reject(message.text)
		_cancel_candidate_poll()
		update_controls()
		return
	var action := int(s.get("action", Action.Catalog))
	if action == Action.AreaInspect and stockpile_page == "settings" and int(_request.get("operation",-1)) == 0 and _request == settings_state.pending:
		var observed: Array = s.get("areas",[])
		if observed.is_empty():
			settings_state.reject()
		else:
			selected = observed[0].duplicate(true)
			settings_state.accept_inspection(selected,_request)
		update_controls()
		return
	if paint_lookup and action == Action.AreaInspectAtTile:
		for target in s.get("areas",[]):
			if int(target.kind) == 0:
				paint_lookup = false; dragging = false; use_area(target); return
		if int(s.get("area_next_cursor",0)) != 0:
			send({"action":Action.AreaInspectAtTile,"origin":paint_lookup_tile,"cursor":int(s.area_next_cursor)})
		else:
			paint_lookup = false; update_controls()
		return
	if action == Action.AreaInspect and int(_request.get("operation",0)) == Contract.AreaOperation.Links:
		if stockpile_page != "links" or _request != links_pending: return
		var page: Dictionary = s.get("area",{})
		if int(page.get("list_revision",0)) == 0 or int(page.get("build_done",0)) < int(page.get("build_total",0)):
			links_delay = 0.25
		else:
			if int(_request.get("cursor",0)) == 0: observed_links = []
			elif int(page.list_revision) != links_revision:
				links_pending = {}; message.text = "List changed; refresh"; request_problem = true; update_controls(); return
			observed_links.append_array(page.get("links",[]))
			links_revision = int(page.list_revision); links_cursor = int(page.get("next_cursor",0))
			links_pending = {}; links_delay = -1
		update_controls(); return
	if links_picking and action == Action.AreaInspectAtTile:
		for target in s.get("areas",[]):
			if int(target.kind) == 0:
				change_link(int(target.id),0,links_give,false); return
		if int(s.get("area_next_cursor",0)) != 0: link_target_tile(overlap_tile,int(s.area_next_cursor))
		else: send({"action":Action.InspectAtTile,"origin":overlap_tile})
		return
	if links_picking and action == Action.InspectAtTile:
		change_link(int(s.get("building_id",-1)),2,links_give,false)
		return
	if action == Action.AreaInspect and int(_request.get("operation",0)) == Contract.AreaOperation.SettingsPage:
		if stockpile_page == "settings": settings_state.accept(s.get("area",{}),_request)
		update_controls()
		return
	if action == Action.AreaInspectAtTile and kind_picker.selected == 1:
		for target in s.get("areas",[]):
			if int(target.kind) == 1:
				var duplicate := false
				for existing in zone_lookup_rows:
					if int(existing.id) == int(target.id): duplicate = true; break
				if not duplicate: zone_lookup_rows.append(target)
		var cursor := int(s.get("area_next_cursor",0))
		if cursor != 0:
			if cursor <= int(_request.get("cursor",0)):
				zone_lookup_rows.clear(); message.text = "Area list changed; select the tile again"
				update_controls()
			else: inspect_tile(overlap_tile,cursor)
			return
		zone_overlaps = zone_lookup_rows.duplicate(true); zone_lookup_rows.clear()
		if zone_overlaps.is_empty(): new_area(); return
		# Native initially selects the last zone; repeated map clicks keep selection.
		var target: Dictionary = zone_overlaps[-1]
		for row in zone_overlaps:
			if int(row.id) == int(selected.get("id",-1)): target = row; break
		areas = zone_overlaps.duplicate(true)
		use_area(target)
		return
	if action == Action.AreaCandidates and int(_request.get("operation",0)) == Contract.AreaOperation.CandidateList:
		if stockpile_page in ["owner","animals","squads"]: candidates_state.accept(s.get("area",{}),_request)
		update_controls(); return
	if action == Action.AreaInspect and int(_request.get("operation",0)) in [Contract.AreaOperation.LocationList,Contract.AreaOperation.LocationChoices]:
		if stockpile_page == "location": locations_state.accept(s.get("area",{}),_request)
		update_controls(); return
	if action == Action.Catalog:
		send({"action": Action.AreaCatalog})
		return
	if action == Action.AreaCatalog:
		zone_types = MenuData.observed_zones(menu_data, s.get("area_choices", []))
		zone_picker.clear()
		for c in zone_types:
			zone_picker.add_item(c.label, c.id)
		available = true
	elif action == Action.AreaCandidates:
		_cancel_candidate_poll()
		if str(_request.get("query", "")) != search.text or selected.is_empty():
			update_controls()
			return
		var page: Dictionary = s.get("area", {})
		# Native completion retains phase 3; the list receipt marks readiness.
		if int(page.get("build_phase", 0)) != 0 and (int(page.get("list_revision", 0)) == 0 or
			int(page.get("build_done", 0)) < int(page.get("build_total", 0))):
			choices = []
			candidate_picker.clear()
			next_cursor = 0
			_candidate_poll_request = _request.duplicate(true)
			_candidate_poll_remaining = 0.25
			update_controls()
			return
		choices = page.get("choices", s.get("area_choices", []))
		candidate_picker.clear()
		for c in choices:
			candidate_picker.add_item(identity_label(c.name, c.id))
		if not choices.is_empty():
			candidate_picker.tooltip_text = choices[0].name
		next_cursor = int(page.get("next_cursor", s.get("area_next_cursor", 0)))
	elif action == Action.AreaDelete:
		new_area()
		selected = {}
		areas = []
		area_picker.clear()
		cancel_drag()
	elif action in [Action.AreaInspectAtTile, Action.AreaInspect, Action.AreaCreate, Action.AreaUpdate, Action.AreaLink]:
		areas = s.get("areas", [])
		area_picker.clear()
		for a in areas:
			area_picker.add_item(identity_label(a.name, a.id))
		if not areas.is_empty():
			area_picker.tooltip_text = area_picker.get_item_text(0)
		overlap_cursor = int(s.get("area_next_cursor", 0))
		if not areas.is_empty():
			var keep_settings := stockpile_page == "settings" and action == Action.AreaUpdate
			var keep_storage := stockpile_page == "containers" and action == Action.AreaUpdate
			var keep_links := stockpile_page == "links" and action in [Action.AreaUpdate,Action.AreaLink]
			var keep_assignments := stockpile_page in ["animals","squads"] and action == Action.AreaUpdate and int(_request.get("operation",0)) in [Contract.AreaOperation.AssignUnits,Contract.AreaOperation.SquadUse]
			var selector_page := stockpile_page
			var selector_kind: int = candidates_state.kind
			var selector_navigation := {"query":candidates_state.query,"sort":candidates_state.sort,"descending":candidates_state.descending,"squad_mask":candidates_state.squad_mask}
			use_area(areas[0], action != Action.AreaInspect)
			if keep_assignments:
				stockpile_page = selector_page; candidates_state.open(selected,selector_kind,selector_navigation)
			if keep_storage: stockpile_page = "containers"
			if keep_links:
				stockpile_page = "links"; clear_links(); read_links()
			if keep_settings:
				stockpile_page = "settings"
				if int(_request.get("operation",0)) == Contract.AreaOperation.SettingsSet and int(_request.get("scope",0)) == 4:
					settings_state.reset_sublist()
				settings_state.open(selected,true)
		else:
			selected = {}
			cancel_drag()
			detail.text = "No areas on this tile"
	if Contract.is_mutation(action) and interaction.audio != null:
		interaction.audio.cue("accepted")
	update_controls()


func _input(event: InputEvent) -> void:
	# A consumed UI motion never reaches the map handler. Clear its implicit
	# hover here; an unhandled map motion restores it before the next poll.
	if event is InputEventMouseMotion: paint_hover = Vector3i(-1,-1,-1)
	if not ui_host.allows_panel_input(self): return
	if panel.visible and ((event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)):
		handle_back()
		get_viewport().set_input_as_handled()
		return
	if (
		panel.visible
		and dragging
		and event is InputEventMouseButton
		and not event.pressed
		and panel.get_global_rect().has_point(event.position)
	):
		if mode == "paint" and paint_tool == "rectangle":
			# Native permits clicking Erase between the two map corners.
			return
		elif mode in ["paint","multi"]:
			dragging = false; paint_preview.mesh = null; update_controls()
		else: cancel_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not ui_host.allows_panel_input(self): return
	# Native065309: map clicks cannot replace the selected zone beneath Details.
	if not details_origin.is_empty():return
	if not panel.visible:
		return
	if not available or (request_ticket != 0 and not paint_lookup): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if mode == "multi" and (event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)):
		var tile: Vector3i = world.pick_tile(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position),world.get_top_z())
		if event is InputEventMouseButton: multi_pointer(tile,event.pressed)
		elif dragging:
			if tile.z == drag_start.z: draw_paint_preview(tile)
			else: dragging = false; paint_preview.mesh = null
		get_viewport().set_input_as_handled(); return
	if mode == "paint" and (event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)):
		var tile: Vector3i = world.pick_tile(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position),world.get_top_z())
		if event is InputEventMouseButton: map_paint_pointer(tile,event.pressed)
		else: paint_motion(tile)
		get_viewport().set_input_as_handled(); return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var tile: Vector3i = world.pick_tile(
			camera.project_ray_origin(event.position),
			camera.project_ray_normal(event.position),
			world.get_top_z()
		)
		if tile.z < 0:
			cancel_drag()
			return
		if mode == "link_pick" and event.pressed:
			link_target_tile(tile)
		elif mode in ["inspect","zone_select"] and event.pressed:
			inspect_tile(tile)
		elif mode == "create":
			if event.pressed:
				drag_start = tile
				dragging = true
			elif dragging:
				dragging = false
				if tile.z != drag_start.z:
					cancel_drag()
					return
				var size: Vector3 = world.map_size()
				rectangle = Selection.rectangle(
					Vector2i(drag_start.x, drag_start.y),
					Vector2i(tile.x, tile.y),
					Vector2i(size.x, size.z)
				)
				origin = Vector3i(rectangle.position.x, rectangle.position.y, tile.z)
				message.text = (
					"%dx%d selected; Create area asks DF to validate every tile"
					% [rectangle.size.x, rectangle.size.y]
				)
				draw_outline()
				update_controls()
		get_viewport().set_input_as_handled()


func handle_back() -> void:
	if not details_origin.is_empty():
		if details_view.staff_workflow.mode==details_view.staff_workflow.Mode.Choosing:
			details_view.staff_workflow.close()
		else:close_location_details();update_controls()
		return
	if mode == "multi":
		# Native Escape/right-click cancel only a partial rectangle. With no
		# partial gesture they exit the tool; on-screen Done/Cancel are separate.
		if dragging:
			dragging = false; multi_second_corner = false; paint_preview.mesh = null
			update_controls()
		else: close_panel()
		return
	if stockpile_page == "location":
		if locations_state.catalog_kind != 0:
			_detach_draft(); locations_state.back_catalog(); update_controls(); return
		_detach_draft(); locations_state.clear(); stockpile_page = "types"; update_controls(); return
	if stockpile_page in ["owner","animals","squads"]:
		_detach_draft(); candidates_state.clear(); stockpile_page = "types"; update_controls(); return
	if zone_menu.cancel_edit(): return
	if mode == "paint":
		if zone_paint != null:
			close_panel(); return
		if selected.is_empty():
			if kind_picker.selected == 1 or not paint_state.cells.is_empty() or dragging: new_area()
			else: close_panel()
			return
		var observed := selected.duplicate(true)
		_detach_draft(); paint_state.clear(); dragging = false
		use_area(observed,false); return
	if links_view.visible and links_picking:
		_detach_draft(); links_picking = false; mode = "inspect"; update_controls(); return
	if storage_view.visible and storage_view.cancel_edit(): return
	if not selected.is_empty() and stockpile_page != "types":
		if stockpile_page == "links":
			_detach_draft()
			clear_links()
		settings_state.clear()
		cancel_drag()
		stockpile_page = "types"
		rename_field.release_focus()
		update_controls()
	elif dragging or (selected.is_empty() and rectangle.has_area()):
		cancel_drag()
		update_controls()
	else:
		close_panel()


func footprint_edges(a: Dictionary) -> Array:
	var edges: Array = []
	var w: int = a.width
	var h: int = a.height
	var cells: PackedByteArray = a.extents
	if cells.size() != w * h:
		return edges
	for y in h:
		for x in w:
			if cells[y * w + x] == 0:
				continue
			if y == 0 or cells[(y - 1) * w + x] == 0:
				edges.append([Vector2i(x, y), Vector2i(x + 1, y)])
			if y == h - 1 or cells[(y + 1) * w + x] == 0:
				edges.append([Vector2i(x, y + 1), Vector2i(x + 1, y + 1)])
			if x == 0 or cells[y * w + x - 1] == 0:
				edges.append([Vector2i(x, y), Vector2i(x, y + 1)])
			if x == w - 1 or cells[y * w + x + 1] == 0:
				edges.append([Vector2i(x + 1, y), Vector2i(x + 1, y + 1)])
	return edges


func draw_outline() -> void:
	if outline == null:
		return
	outline.visible = mode != "paint" or paint_state.z == int(world.get_top_z())
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_set_color(Color(0.95, 0.75, 0.15))
	if mode == "paint" and paint_state.z >= 0:
		var y: float = paint_state.z + float(Df3dWorld.floor_height()) + 0.015
		for point: Vector2i in paint_state.cells:
			for edge in [[Vector2i(0,0),Vector2i(1,0),Vector2i(0,-1)],[Vector2i(0,1),Vector2i(1,1),Vector2i(0,1)],[Vector2i(0,0),Vector2i(0,1),Vector2i(-1,0)],[Vector2i(1,0),Vector2i(1,1),Vector2i(1,0)]]:
				if not paint_state.cells.has(point+edge[2]):
					for offset in [edge[0],edge[1]]: mesh.surface_add_vertex(Vector3(point.x+offset.x,y,point.y+offset.y))
	elif rectangle.has_area() and origin.z >= 0:
		var y := origin.z + float(Df3dWorld.floor_height()) + 0.015
		if not selected.is_empty():
			for edge in footprint_edges(selected):
				for point in edge:
					mesh.surface_add_vertex(Vector3(origin.x + point.x, y, origin.y + point.y))
		else:
			var a := Vector3(rectangle.position.x, y, rectangle.position.y)
			var b := Vector3(rectangle.end.x, y, rectangle.position.y)
			var c := Vector3(rectangle.end.x, y, rectangle.end.y)
			var d := Vector3(rectangle.position.x, y, rectangle.end.y)
			for point in [a, b, b, c, c, d, d, a]:
				mesh.surface_add_vertex(point)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
	outline.mesh = mesh


func _detach_draft() -> void:
	if details_parent_ticket!=0 and action_service!=null:action_service.detach(details_parent_ticket)
	details_parent_ticket=0;details_parent_refresh_again=false
	close_location_details()
	paint_hover = Vector3i(-1,-1,-1)
	paint_counts.clear()
	paint_lookup = false
	links_pending = {}; links_delay = -1
	_cancel_candidate_poll()
	_request_action = -1
	draft_generation += 1
	if action_service != null: action_service.detach(request_ticket)
	request_ticket = 0

func _session_changed() -> void:
	paint_saved_corner = Vector3i(-1,-1,-1)
	# The service notifies the interaction owner separately; never drain an old
	# interaction while replacing the panel's epoch-bound state.
	zone_paint = null
	paint_state = preload("res://scripts/area_paint_state.gd").new()
	paint_counts.clear(); paint_hover = Vector3i(-1,-1,-1)
	multi_state.clear()
	if mode == "multi": mode = "inspect"
	portraits.clear(world)
	# Catalog identities and picker contents belong to the old world as well.
	zone_types.clear(); zone_draft.clear()
	zone_picker.clear(); area_picker.clear(); candidate_picker.clear()
	zone_menu.cancel_edit(); zone_menu.display([],false)
	zone_overlaps.clear(); zone_lookup_rows.clear()
	locations_state.clear(); locations_view.hide()
	candidates_state.clear(); candidates_view.hide()
	paint_state.clear(); paint_view.tools.hide()
	if mode == "paint": mode = "inspect"
	clear_links()
	storage_view.cancel_edit()
	settings_state.clear()
	available = false
	selected = {}
	areas = []
	choices = []
	cancel_drag()
	update_controls()
	message.text = "World changed; reopen to refresh"

func cancel_gesture() -> void:
	paint_hover = Vector3i(-1,-1,-1)
	paint_counts.clear()
	dragging = false
	drag_start = Vector3i(-1,-1,-1)
