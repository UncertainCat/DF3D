extends Node3D
const Contract = preload("res://scripts/management_contract.gd")
const Action = Contract.ManagementAction
const Status = Contract.ManagementStatus
# Area semantics come from Management v2; no native memory or scripts here.
const Selection = preload("res://scripts/interaction_state.gd")
const CATEGORIES = [
	"Animals",
	"Food",
	"Furniture",
	"Corpses",
	"Refuse",
	"Stone",
	"Ammo",
	"Coins",
	"Bars / blocks",
	"Gems",
	"Finished goods",
	"Leather",
	"Cloth",
	"Wood",
	"Weapons",
	"Armor",
	"Sheets"
]
var world
var camera: Camera3D
var interaction
var panel: PanelContainer
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
var draft_generation := 0
var previous_outcome := ""
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
	action_service.session_changed.connect(_session_changed)
	action_service.completed.connect(_service_completed)
	tree_exiting.connect(_detach_draft)
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 390
	panel.hide()
	canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
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
	for text in CATEGORIES:
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
	var ui := preload("res://scripts/original_ui.gd").new()
	ui.configure(world)
	ui.apply(self)
	new_area()


func open_panel() -> void:
	if not play_enabled or not ui_host.activate(self): return
	panel.show()
	_refresh_previous_outcome()
	current_z = int(world.get_top_z())
	new_area()
	available = false
	if world.is_live():
		send({"action": Action.Catalog})
	else:
		message.text = "Offline preview only; native area creation and settings unavailable"
	update_controls()


func close_panel() -> void:
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
	_detach_draft()
	dragging = false
	rectangle = Rect2i()
	origin = Vector3i(-1, -1, -1)
	draw_outline()


func new_area() -> void:
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
	update_controls()


func send(request: Dictionary) -> void:
	if not play_enabled or not panel.visible or request_ticket != 0: return
	var generation := draft_generation
	request_ticket = action_service.submit("construction" if int(request.action) == Action.Catalog else "areas", request,
		func(ticket, result, sent):
			if generation == draft_generation and ticket == request_ticket and panel.visible:
				request_ticket = 0
				_receive_result(result, sent))
	message.text = "Waiting for Dwarf Fortress"
	update_controls()


func selected_request(action: int) -> Dictionary:
	return {"action": action, "id": selected.id, "kind": selected.kind}


func category_mask() -> int:
	var mask := 0
	for i in categories.size():
		if categories[i].button_pressed:
			mask |= 1 << i
	return mask


func create_area() -> void:
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
	mode = "inspect"
	overlap_tile = tile
	send({"action": Action.AreaInspectAtTile, "origin": tile, "cursor": cursor})


func search_candidates(cursor := 0) -> void:
	if selected.is_empty():
		return
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


func use_area(a: Dictionary) -> void:
	_detach_draft()
	selected = a.duplicate(true)
	kind_picker.select(int(a.kind))
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


func update_controls() -> void:
	_show_previous_outcome()
	if create_button == null:
		return
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
	apply_button.disabled = not available or request_ticket != 0 or selected.is_empty()
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


func _process(_delta: float) -> void:
	if not play_enabled or not panel.visible: return
	_show_previous_outcome()
	var view := get_viewport().get_visible_rect().size
	if view != _layout_view:
		_layout_view = view
		panel.size = Vector2(390, maxf(220, view.y - 64))
		panel.position = Vector2(maxf(12, view.x - panel.size.x - 12), 52)
	var z := int(world.get_top_z())
	if z != current_z:
		current_z = z
		cancel_drag()

func _receive_result(s: Dictionary, _request: Dictionary) -> void:
	message.text = str(s.get("message", "Request ended"))
	if int(s.get("status", Status.Rejected)) != Status.Ok:
		if interaction.audio != null:
			interaction.audio.cue("rejected")
		update_controls()
		return
	var action := int(s.get("action", Action.Catalog))
	if action == Action.Catalog:
		send({"action": Action.AreaCatalog})
		return
	if action == Action.AreaCatalog:
		zone_types = s.get("area_choices", [])
		zone_picker.clear()
		for c in zone_types:
			zone_picker.add_item(c.name, c.id)
		available = true
	elif action == Action.AreaCandidates:
		choices = s.get("area_choices", [])
		candidate_picker.clear()
		for c in choices:
			candidate_picker.add_item(identity_label(c.name, c.id))
		if not choices.is_empty():
			candidate_picker.tooltip_text = choices[0].name
		next_cursor = int(s.get("area_next_cursor", 0))
	elif action == Action.AreaDelete:
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
			use_area(areas[0])
		else:
			selected = {}
			cancel_drag()
			detail.text = "No areas on this tile"
	if Contract.is_mutation(action) and interaction.audio != null:
		interaction.audio.cue("accepted")
	update_controls()


func _input(event: InputEvent) -> void:
	if not ui_host.allows_panel_input(self): return
	if (
		panel.visible
		and dragging
		and event is InputEventMouseButton
		and not event.pressed
		and panel.get_global_rect().has_point(event.position)
	):
		cancel_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not ui_host.allows_panel_input(self): return
	if not panel.visible or not available or request_ticket != 0:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var tile: Vector3i = world.pick_tile(
			camera.project_ray_origin(event.position),
			camera.project_ray_normal(event.position),
			world.get_top_z()
		)
		if tile.z < 0:
			cancel_drag()
			return
		if mode == "inspect" and event.pressed:
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
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_set_color(Color(0.95, 0.75, 0.15))
	if rectangle.has_area() and origin.z >= 0:
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
	draft_generation += 1
	if action_service != null: action_service.detach(request_ticket)
	request_ticket = 0

func _session_changed() -> void:
	available = false
	selected = {}
	areas = []
	choices = []
	cancel_drag()
	update_controls()
	message.text = "World changed; reopen to refresh"

func _service_completed(_ticket: int, _result: Dictionary) -> void:
	if panel.visible: _refresh_previous_outcome()

func _refresh_previous_outcome() -> void:
	if not previous_outcome.is_empty() and message.text.ends_with(previous_outcome):
		message.text = message.text.trim_suffix("\n" + previous_outcome)
	var outcome: Dictionary = action_service.last_detached_mutation("areas")
	previous_outcome = ""
	if not outcome.is_empty():
		var result: Dictionary = outcome.result
		var fallback := "Accepted" if int(result.get("status",Status.Rejected)) == Status.Ok else "Outcome unavailable"
		previous_outcome = "Previous request #%d: %s" % [outcome.ticket, result.get("message",fallback)]
	_show_previous_outcome()

func _show_previous_outcome() -> void:
	if message != null and not previous_outcome.is_empty() and not message.text.ends_with(previous_outcome):
		message.text += "\n" + previous_outcome

func cancel_gesture() -> void:
	dragging = false
	drag_start = Vector3i(-1,-1,-1)
