extends Node3D
const Contract = preload("res://scripts/management_contract.gd")
const Action = Contract.ManagementAction
const Status = Contract.ManagementStatus
# Semantic construction controller. Catalog and material eligibility come from DF.
var world
var camera: Camera3D
var interaction
var panel: PanelContainer
var picker: OptionButton
var materials: OptionButton
var message: Label
var dimensions: Label
var place_button: Button
var next_button: Button
var remove_button: Button
var refresh_button: Button
var catalog: Array = []
var inputs: Array = []
var origin := Vector3i(-1, -1, -1)
var request_ticket := 0
var draft_generation := 0
var previous_outcome := ""
var action_service
var ui_host
var modal_input := true
var current_z := -1
var next_cursor := 0
var inspected_id := -1
var inspected_terrain := Vector3i(-1, -1, -1)
var mode := "place"
var ready_to_place := false
var outline: MeshInstance3D
var refresh_time := 0.0
var placed_sites: Dictionary = {}
var selection_color := Color(0.8, 0.65, 0.15)
var play_enabled := true


func _ready() -> void:
	action_service.session_changed.connect(_session_changed)
	action_service.completed.connect(_service_completed)
	tree_exiting.connect(_detach_draft)
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	panel = PanelContainer.new()
	panel.position = Vector2(570, 52)
	panel.custom_minimum_size.x = 360
	panel.visible = false
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := Label.new()
	title.text = "Construction"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	button(heading, "Close", close_panel)
	picker = OptionButton.new()
	picker.fit_to_longest_item = false
	picker.custom_minimum_size.x = 320
	picker.clip_text = true
	picker.item_selected.connect(
		func(_i):
			cancel_site()
			mode = "place"
			update_definition()
	)
	box.add_child(picker)
	dimensions = Label.new()
	box.add_child(dimensions)
	var row := HBoxContainer.new()
	box.add_child(row)
	button(
		row,
		"Choose site",
		func():
			mode = "place"
			cancel_site()
			message.text = "Click a floor tile to check placement"
	)
	button(
		row,
		"Inspect building",
		func():
			mode = "inspect"
			cancel_site()
			message.text = "Click a building to inspect construction"
	)
	materials = OptionButton.new()
	materials.fit_to_longest_item = false
	materials.custom_minimum_size.x = 320
	materials.clip_text = true
	materials.item_selected.connect(func(i): materials.tooltip_text = materials.get_item_text(i))
	box.add_child(materials)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	place_button = button(actions, "Place", place)
	next_button = button(actions, "More materials", func(): preview(next_cursor))
	var inspection := HBoxContainer.new()
	box.add_child(inspection)
	refresh_button = button(inspection, "Refresh", refresh)
	remove_button = button(inspection, "Remove building", remove_building)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 320
	box.add_child(message)
	var tip := Label.new()
	tip.custom_minimum_size.x = 320
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.text = "Native jobs require normal hauling and labor. Esc cancels.\nFixed dimensions; special placement types are listed unavailable."
	tip.add_theme_font_size_override("font_size", 12)
	box.add_child(tip)
	outline = MeshInstance3D.new()
	add_child(outline)
	var original := preload("res://scripts/original_ui.gd").new()
	original.configure(world)
	original.apply(self)
	cancel_site()


func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func open_panel() -> void:
	if not play_enabled or not ui_host.activate(self): return
	panel.show()
	_refresh_previous_outcome()
	current_z = int(world.get_top_z())
	cancel_site()
	send({"action": Action.Catalog})


func set_play_enabled(value: bool) -> void:
	play_enabled = value
	if not value:
		close_panel()


func close_panel() -> void:
	panel.hide()
	cancel_site()
	ui_host.release(self)


func cancel_site() -> void:
	_detach_draft()
	origin = Vector3i(-1, -1, -1)
	inspected_id = -1
	inspected_terrain = Vector3i(-1, -1, -1)
	ready_to_place = false
	inputs.clear()
	materials.clear()
	next_cursor = 0
	if outline != null:
		draw_outline(selection_color)
	update_buttons()


func update_definition() -> void:
	if picker.selected < 0 or picker.selected >= catalog.size():
		return
	var d: Dictionary = catalog[picker.selected]
	dimensions.text = "%d × %d · fixed orientation" % [d.width, d.height]
	message.text = "Click a floor tile to preview" if d.supported else d.reason


func send(request: Dictionary) -> void:
	if not play_enabled or not panel.visible or request_ticket != 0: return
	var generation := draft_generation
	request_ticket = action_service.submit("construction", request,
		func(ticket, result, sent):
			if generation == draft_generation and ticket == request_ticket and panel.visible:
				request_ticket = 0
				_receive_result(result, sent))
	message.text = "Waiting for Dwarf Fortress"
	update_buttons()


func preview(cursor := 0) -> void:
	if origin.z < 0 or picker.selected < 0:
		return
	var d: Dictionary = catalog[picker.selected]
	ready_to_place = false
	send(
		{
			"action": Action.Preview,
			"definition": d.key,
			"origin": origin,
			"width": d.width,
			"height": d.height,
			"cursor": cursor
		}
	)
	draw_outline(Color(0.8, 0.65, 0.15))


func place() -> void:
	if not ready_to_place or materials.selected < 0 or origin.z < 0:
		return
	var d: Dictionary = catalog[picker.selected]
	send(
		{
			"action": Action.Place,
			"definition": d.key,
			"origin": origin,
			"width": d.width,
			"height": d.height,
			"items": [inputs[materials.selected].id]
		}
	)
	ready_to_place = false


func refresh() -> void:
	if inspected_id >= 0:
		send({"action": Action.Inspect, "building_id": inspected_id})
	elif origin.z >= 0:
		preview()
	else:
		send({"action": Action.Catalog})


func remove_building() -> void:
	if inspected_id >= 0:
		send({"action": Action.Remove, "building_id": inspected_id})
	elif inspected_terrain.z >= 0:
		send({"action": Action.RemoveConstruction, "origin": inspected_terrain})


func update_buttons() -> void:
	_show_previous_outcome()
	if place_button == null:
		return
	place_button.disabled = request_ticket != 0 or not ready_to_place or materials.item_count == 0
	next_button.disabled = request_ticket != 0 or next_cursor == 0 or origin.z < 0
	remove_button.disabled = request_ticket != 0 or (inspected_id < 0 and inspected_terrain.z < 0)
	refresh_button.disabled = request_ticket != 0
	picker.disabled = request_ticket != 0


func _process(delta: float) -> void:
	if not play_enabled or not panel.visible: return
	_show_previous_outcome()
	panel.position = Vector2(maxf(12, get_viewport().get_visible_rect().size.x - panel.size.x - 12), 52)
	var z := int(world.get_top_z())
	if current_z != z:
		current_z = z
		cancel_site()
	refresh_time -= delta
	if inspected_id >= 0 and request_ticket == 0 and refresh_time <= 0:
		refresh_time = 1.0
		send({"action": Action.Inspect, "building_id": inspected_id})

func _receive_result(s: Dictionary, request: Dictionary) -> void:
	message.text = str(s.get("message", "Construction unavailable"))
	if int(s.get("status", Status.Rejected)) == Status.Ok:
		match int(s.get("action", Action.Catalog)):
			Action.Catalog:
				catalog = s.get("catalog", [])
				picker.clear()
				for d in catalog:
					picker.add_item(d.name if d.supported else d.name + " (unavailable)")
				for i in catalog.size():
					if catalog[i].supported:
						picker.select(i)
						break
				update_definition()
			Action.Preview:
				if origin != request.get("origin", Vector3i(-1, -1, -1)):
					update_buttons()
					return
				inputs = s.get("inputs", [])
				materials.clear()
				for i in inputs:
					materials.add_item("%s · #%d · qty %d" % [i.description, i.id, i.quantity])
				materials.tooltip_text = (
					materials.get_item_text(0) if materials.item_count else ""
				)
				next_cursor = int(s.get("next_cursor", 0))
				ready_to_place = bool(s.get("placement_valid", false))
				draw_outline(Color(0.25, 0.9, 0.35))
				if inputs.is_empty():
					message.text = "No eligible ground materials found. Refresh after supplies arrive."
			Action.Place, Action.Inspect, Action.InspectAtTile:
				inspected_id = int(s.get("building_id", -1))
				inspected_terrain = (
					request.get("origin", Vector3i(-1, -1, -1))
					if s.get("terrain_construction", false)
					else Vector3i(-1, -1, -1)
				)
				if int(s.action) == Action.Place:
					placed_sites[inspected_id] = {
						"origin": request.origin,
						"width": request.width,
						"height": request.height
					}
					draw_outline(Color(0.25, 0.9, 0.35))
				message.text += (
					"\nStage %d / %d · %d jobs%s"
					% [
						s.get("build_stage", -1),
						s.get("max_stage", -1),
						s.get("jobs", 0),
						" · removing" if s.get("removing", false) else ""
					]
				)
			Action.Remove, Action.RemoveConstruction:
				placed_sites.erase(inspected_id)
				inspected_id = -1
				origin = Vector3i(-1, -1, -1)
				draw_outline(selection_color)
				inspected_terrain = Vector3i(-1, -1, -1)
	else:
		ready_to_place = false
		draw_outline(Color(1, 0.2, 0.2))
	update_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if not ui_host.allows_panel_input(self): return
	if not panel.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_site()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and request_ticket == 0
	):
		var ray := camera.project_ray_origin(event.position)
		var direction := camera.project_ray_normal(event.position)
		if mode == "inspect":
			var hit: Dictionary = world.pick_building(ray, direction, world.get_top_z())
			var tile: Vector3i = (
				hit.tile
				if not hit.is_empty()
				else world.pick_tile(ray, direction, world.get_top_z())
			)
			if tile.z >= 0:
				send({"action": Action.InspectAtTile, "origin": tile})
		else:
			origin = world.pick_tile(ray, direction, world.get_top_z())
			inspected_id = -1
			if origin.z >= 0:
				preview()
		get_viewport().set_input_as_handled()


func draw_outline(color: Color) -> void:
	selection_color = color
	var mesh := ImmediateMesh.new()
	var sites: Array = []
	for site in placed_sites.values():
		if int(site.origin.z) == int(world.get_top_z()):
			sites.append(site)
	if origin.z == world.get_top_z() and picker.selected >= 0 and picker.selected < catalog.size():
		var definition: Dictionary = catalog[picker.selected]
		sites.append({"origin": origin, "width": definition.width, "height": definition.height})
	if sites.is_empty():
		outline.mesh = null
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for d in sites:
		var p: Vector3i = d.origin
		if p.z != world.get_top_z():
			continue
		var y := float(p.z) + float(world.floor_height()) + 0.02
		var corners: Array[Vector3] = [
			Vector3(p.x, y, p.y),
			Vector3(p.x + d.width, y, p.y),
			Vector3(p.x + d.width, y, p.y + d.height),
			Vector3(p.x, y, p.y + d.height)
		]
		for i in 4:
			mesh.surface_add_vertex(corners[i])
			mesh.surface_add_vertex(corners[(i + 1) % 4])
	mesh.surface_end()
	outline.mesh = mesh


func _detach_draft() -> void:
	draft_generation += 1
	if action_service != null: action_service.detach(request_ticket)
	request_ticket = 0

func _session_changed() -> void:
	catalog.clear()
	picker.clear()
	placed_sites.clear()
	cancel_site()
	message.text = "World changed; reopen to refresh"

func _service_completed(_ticket: int, _result: Dictionary) -> void:
	if panel.visible: _refresh_previous_outcome()

func _refresh_previous_outcome() -> void:
	if not previous_outcome.is_empty() and message.text.ends_with(previous_outcome):
		message.text = message.text.trim_suffix("\n" + previous_outcome)
	var outcome: Dictionary = action_service.last_detached_mutation("construction")
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
	pass # Construction uses click placement; no in-flight drag gesture.
