extends Node3D
var frame_diagnostics # Optional recorder, injected only for explicit boundary probes.
# Layer-4 interaction controller. Every query/command goes through Df3dWorld.
const Selection = preload("res://scripts/interaction_state.gd")
const CutoutPicking = preload("res://scripts/cutout_picking.gd")
const DesignationOverlay = preload("res://scripts/designation_overlay.gd")
const TOOLS = ["Inspect items", "Dig", "Channel", "Stairs up", "Stairs down", "Stairs up/down", "Smooth", "Engrave", "Remove", "Ramp", "Chop trees", "Clear chop", "Gather plants", "Clear gather", "Inspect buildings", "Stairs", "Remove stairs/ramps", "Carve fortifications", "Carve track", "Convert blueprint to standard", "Convert standard to blueprint"]
var world # Injected by world_view; untyped for headless fake-world tests.
var selection_panel
var construction_active := false
var camera: Camera3D
var camera_rig: Node3D
var camera_button: Button
var camera_help: Label
var audio: Node
var state = Selection.new()
var panel: PanelContainer
var tool_picker: OptionButton
var item_picker: OptionButton
var status: Label
var feedback: Label
var priority: SpinBox
var marker_only := false
var mining_mode := 0
var show_priorities := false
var show_traffic := false
var _items: Array = []
var _preferred_unit := -1
var _preferred_item := -1
var _item_tile := Vector3i(-1, -1, -1)
var _dragging := false
var _right_armed := false
var _right_travel := 0.0
var _start := Vector3i(-1, -1, -1)
var _end := Vector3i(-1, -1, -1)
var _session := -1
var _z := -1
var _marker_timer := 0.0
var _markers: Array = []
var _lines: MeshInstance3D
var _order_sprites
var _cursor_sprites
var _preview := Rect2i()
var _preview_key: Array = []
var _track_preview: Array = []
var _preview_height := 1.0
var _buttons: Array[Button] = []
var building_picker: OptionButton
var building_row: HBoxContainer
var _buildings: Array = []
var _preferred_building := -1
var shell_enabled := false
var shell_blocked := false
var _play_enabled := true
var _tool_row: HBoxContainer
var _camera_row: HBoxContainer
var _legend: Label

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	panel = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(530, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status = Label.new()
	box.add_child(status)
	var row := HBoxContainer.new()
	_tool_row = row
	box.add_child(row)
	tool_picker = OptionButton.new()
	tool_picker.name = "ToolPicker"
	tool_picker.focus_mode = Control.FOCUS_NONE
	for tool in TOOLS:
		tool_picker.add_item(tool)
	row.add_child(tool_picker)
	tool_picker.item_selected.connect(func(_i): cancel_selection(); _clear_items())
	tool_picker.item_selected.connect(func(_i): _cue("select"); _draw_overlay())
	var label := Label.new()
	label.text = " Priority "
	row.add_child(label)
	priority = SpinBox.new()
	priority.min_value = 1
	priority.max_value = 7
	priority.value = 4
	priority.get_line_edit().focus_mode = Control.FOCUS_NONE
	priority.tooltip_text = "Dig priority: 1 highest, 7 lowest"
	row.add_child(priority)
	priority.value_changed.connect(func(_value): set_show_priorities(true))
	_add_button(row, "Pause", func(): _pause(true))
	_add_button(row, "Resume", func(): _pause(false))
	var camera_row := HBoxContainer.new()
	_camera_row = camera_row
	box.add_child(camera_row)
	camera_button = Button.new()
	camera_button.focus_mode = Control.FOCUS_NONE
	camera_button.tooltip_text = "Switch DF top-down / Free 3D camera (F4)"
	camera_button.pressed.connect(func():
		if camera_rig != null and not camera_rig.controls_blocked():
			camera_rig.toggle_mode()
			_cue("click"))
	camera_row.add_child(camera_button)
	camera_help = Label.new()
	camera_help.add_theme_font_size_override("font_size", 13)
	box.add_child(camera_help)
	if camera_rig != null: camera_rig.mode_changed.connect(_refresh_camera)
	_refresh_camera()
	var legend := Label.new()
	_legend = legend
	legend.text = "Pending in DF: amber dig · cyan smooth · violet engrave"
	legend.add_theme_font_size_override("font_size", 13)
	box.add_child(legend)
	item_picker = OptionButton.new()
	item_picker.name = "ItemPicker"
	item_picker.fit_to_longest_item = false
	item_picker.custom_minimum_size.x = 300
	item_picker.focus_mode = Control.FOCUS_NONE
	item_picker.tooltip_text = "Observed DF item state; choose a specific item in this tile"
	item_picker.visible = false
	item_picker.item_selected.connect(func(_i): _cue("select"))
	box.add_child(item_picker)
	var item_row := HBoxContainer.new()
	box.add_child(item_row)
	_add_button(item_row, "Forbid", func(): _item_flags(1, -1), true)
	_add_button(item_row, "Reclaim", func(): _item_flags(0, -1), true)
	_add_button(item_row, "Dump", func(): _item_flags(-1, 1), true)
	_add_button(item_row, "Cancel dump", func(): _item_flags(-1, 0), true)
	var melt_row := HBoxContainer.new()
	box.add_child(melt_row)
	_add_button(melt_row, "Melt", func(): _item_flags(-1, -1, 1), true)
	_add_button(melt_row, "Cancel melt", func(): _item_flags(-1, -1, 0), true)
	building_picker = OptionButton.new()
	building_picker.fit_to_longest_item = false
	building_picker.custom_minimum_size.x = 300
	building_picker.focus_mode = Control.FOCUS_NONE
	building_picker.item_selected.connect(func(_i): _refresh_building_actions(); _cue("select"))
	box.add_child(building_picker)
	building_row = HBoxContainer.new()
	box.add_child(building_row)
	_add_button(building_row, "Forbid passage", func(): _building_flags(true))
	_add_button(building_row, "Allow passage", func(): _building_flags(false))
	feedback = Label.new()
	feedback.custom_minimum_size.x = 520
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 13)
	box.add_child(feedback)
	_lines = MeshInstance3D.new()
	_lines.name = "DesignationOverlay"
	add_child(_lines)
	_order_sprites = DesignationOverlay.new()
	_order_sprites.world = world
	add_child(_order_sprites)
	_cursor_sprites = DesignationOverlay.new()
	_cursor_sprites.world = world
	_cursor_sprites.layer_priority = 20
	add_child(_cursor_sprites)
	_clear_items()

func _refresh_camera() -> void:
	if camera_rig == null: return
	camera_button.text = "Camera: %s (F4)" % {"df":"DF", "isometric":"Isometric", "free":"Free", "walk":"Walk"}[camera_rig.get_mode()]
	camera_help.text = "LMB drag rectangle · Right click / Esc back · PgUp/PgDn level · F3 diagnostics\n" + ("North-up · MMB pan · wheel zoom · WASD/arrows pan · QE level" if camera_rig.get_mode() != "free" else "RMB drag orbit · MMB pan · wheel zoom · WASD/arrows move · QE height")
	if camera_rig.get_mode() == "walk": camera_help.text = "Click map to look · WASD walk · Space jump · Walk off edges to drop · Q descend stairs · Esc release · F4/F5 return"

func _add_button(row: Control, title: String, action: Callable, item := false) -> void:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.pressed.connect(func(): _cue("click"))
	row.add_child(button)
	if item:
		_buttons.append(button)

# The fortress shell owns tool selection and panel routing.
func enable_shell() -> void:
	shell_enabled = true
	panel.get_parent().layer = 2
	panel.custom_minimum_size.x = 390
	feedback.custom_minimum_size.x = 310
	_tool_row.hide()
	_camera_row.hide()
	camera_help.hide()
	_legend.hide()
	var box = panel.get_child(0)
	for row in box.get_children():
		if not row is HBoxContainer or row in [_tool_row, _camera_row, building_row]: continue
		var grid = GridContainer.new()
		grid.columns = 2
		box.add_child(grid)
		box.move_child(grid, row.get_index())
		for child in row.get_children(): child.reparent(grid)
		row.queue_free()

func set_play_enabled(value: bool) -> void:
	if value == _play_enabled: return
	_play_enabled = value
	if not value: cancel_selection()
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED

func select_tool(index: int) -> void:
	if index < 0 or index >= TOOLS.size(): return
	if index not in [0,14] and selection_panel != null: selection_panel.close_panel()
	cancel_selection()
	_clear_items()
	tool_picker.select(index)
	_draw_overlay()
	_cue("select")

func shell_context_visible() -> bool:
	return not _items.is_empty() or not _buildings.is_empty()

func update_shell_context(view: Vector2) -> void:
	panel.position = Vector2(maxf(12, view.x - 402), 52)
	panel.size.x = 390
	status.text = "Items and buildings" if _item_tile.z >= 0 else ""

func _process(delta: float) -> void:
	var started: int = frame_diagnostics.detail_start() if frame_diagnostics != null else 0
	_process_view(delta)
	if frame_diagnostics != null: frame_diagnostics.detail_mark("ui.interaction", started)

func _process_view(delta: float) -> void:
	if world == null:
		return
	# Fake-world handler tests may omit optional session metadata.
	if world.has_method("session_generation"):
		var generation := int(world.session_generation())
		if generation != _session:
			_session = generation
			state = Selection.new()
			cancel_selection()
			_clear_items()
			_markers.clear()
			_marker_timer = 0.0
			_marker_revision = -1
			_draw_overlay()
	var top := int(world.get_top_z())
	if _order_sprites != null:
		_order_sprites.update_grid(world.map_size(), top, preload("res://scripts/presentation_settings.gd").targeting_grid and world.terrain_loaded() and camera_rig != null and camera_rig.is_df_mode() and tool_picker.selected not in [0,14] and not construction_active and not shell_blocked)
	if top != _z:
		_z = top
		if _dragging:
			_end.z = top
			_update_preview()
		else: cancel_selection()
		_clear_items()
		_marker_timer = 0.0
		_marker_revision = -1
		var preview_env := OS.get_environment("DF3D_PREVIEW_RECT")
		if not world.is_live() and preview_env != "":
			var parts := preview_env.split(",")
			if parts.size() == 4:
				tool_picker.select(1)
				_start = Vector3i(int(parts[0]), int(parts[1]), top)
				_end = _start + Vector3i(maxi(1, int(parts[2])) - 1, maxi(1, int(parts[3])) - 1, 0)
				_update_preview()
	var results: Array = world.drain_command_results()
	for outcome in state.receive(results):
		_cue("accepted" if outcome == 0 else "rejected")
	state.expire(Time.get_ticks_msec())
	if not results.is_empty() and _item_tile.z >= 0:
		var selected_id: int = _items[item_picker.selected].id if not _items.is_empty() else -1
		_refresh_items(selected_id)
	_marker_timer -= delta
	if _marker_timer <= 0 and world.terrain_loaded():
		_marker_timer = 0.35
		if _item_tile.z >= 0: _refresh_buildings()
		var revision := int(world.terrain_revision()) if world.has_method("terrain_revision") else -1
		if revision < 0 or revision != _marker_revision:
			_marker_revision = revision
			if _dragging and tool_picker.selected == 18: _update_preview()
			marker_scan_count += 1
			var markers: Array = world.designation_tiles(top)
			if markers != _markers:
				_markers = markers
				_draw_overlay()
	var source := "LIVE" if world.is_live() else ("OFFLINE · preview only" if world.is_attached() else "WAITING FOR DF")
	status.text = "Items and buildings" if shell_enabled else "%s  |  Level %d  |  %s" % [source, top, TOOLS[tool_picker.selected]]
	var lines := PackedStringArray(state.history)
	if not state.pending.is_empty():
		lines.append("%d awaiting DF result." % state.pending.size())
	feedback.text = "\n".join(lines)

# Input over UI never reaches _unhandled_input; release over it must still
# cancel an existing world drag instead of leaving a stale armed rectangle.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _right_armed:
		_right_travel += event.relative.length()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if (panel.is_visible_in_tree() and panel.get_global_rect().has_point(event.position)) or get_viewport().gui_get_hovered_control() != null:
			cancel_selection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_selection()
		_right_armed = false

func _unhandled_input(event: InputEvent) -> void:
	if not _play_enabled: return
	if camera_rig != null and camera_rig.get_mode() == "walk": return
	if construction_active or shell_blocked: return
	if selection_panel != null and selection_panel.is_open():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT: return
		if event is InputEventKey and event.keycode == KEY_ESCAPE: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_right_armed = true
			_right_travel = 0.0
		else:
			var back := _right_armed and _right_travel < 4.0
			_right_armed = false
			if back:
				if _preview.has_area(): cancel_selection()
				else: select_tool(0)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cue("cancel")
		if _preview.has_area(): cancel_selection()
		else: select_tool(0)
		_clear_items()
		get_viewport().set_input_as_handled()
		return
	if world == null or not world.terrain_loaded():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var tile := _pick(event.position)
		if event.pressed:
			if tile.z < 0:
				cancel_selection()
				return
			if tool_picker.selected == 0 or TOOLS[tool_picker.selected] == "Inspect buildings":
				_select_items(tile)
			else:
				# One press/release owns one rectangle. UI presses never reach here.
				_start = tile
				_end = tile
				_dragging = true
				_update_preview()
		elif _dragging:
			if tile.z < 0 or tile.z != world.get_top_z():
				cancel_selection()
			else:
				_end = tile
				_update_preview()
				_dragging = false
				_designate()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var tile := _pick(event.position)
		if tile.z >= 0 and tile.z == world.get_top_z():
			_end = tile
			_update_preview()

func _pick(screen: Vector2) -> Vector3i:
	_preferred_unit = -1
	_preferred_item = -1
	_preferred_building = -1
	if TOOLS[tool_picker.selected] == "Inspect buildings" and world.has_method("pick_building"):
		var hit: Dictionary = world.pick_building(camera.project_ray_origin(screen), camera.project_ray_normal(screen), world.get_top_z())
		if not hit.is_empty():
			_preferred_building = hit.id
			return hit.tile
	if tool_picker.selected == 0:
		var hit := _pick_piece(screen)
		if not hit.is_empty():
			if int(hit.get("kind",2)) == 1: _preferred_unit = hit.id
			if int(hit.get("kind",2)) == 2: _preferred_item = hit.id
			if int(hit.get("kind",2)) == 3: _preferred_building = hit.id
			return hit.tile
	# Tools target the cut surface; items target their floor slab.
	if tool_picker.selected != 0:
		return world.pick_tile(camera.project_ray_origin(screen), camera.project_ray_normal(screen), world.get_top_z())
	var height := float(Df3dWorld.floor_height())
	return Selection.project_tile(camera.project_ray_origin(screen), camera.project_ray_normal(screen), world.get_top_z(), world.map_size(), height)

func _update_preview() -> void:
	var key := [_start, _end, tool_picker.selected, world.get_top_z(), world.terrain_revision() if world.has_method("terrain_revision") else -1]
	if key == _preview_key: return
	_preview_key = key
	_preview_height = maxf(0, world.selection_height(Vector3i(_start.x, _start.y, world.get_top_z())))
	var size: Vector3 = world.map_size()
	_preview = Selection.rectangle(Vector2i(_start.x, _start.y), Vector2i(_end.x, _end.y), Vector2i(int(size.x), int(size.z)))
	_track_preview = world.preview_track(_preview, _start.z, _start.x > _end.x, _start.y > _end.y, _end.z) if tool_picker.selected == 18 and world.has_method("preview_track") else []
	_draw_overlay()

func cancel_selection() -> void:
	_dragging = false
	_right_armed = false
	_right_travel = 0.0
	_preview = Rect2i()
	_preview_key.clear()
	_track_preview.clear()
	if _lines != null:
		_draw_overlay()

func _clear_items() -> void:
	_items = []
	_item_tile = Vector3i(-1, -1, -1)
	if item_picker != null:
		item_picker.clear()
		item_picker.visible = false
	for button in _buttons:
		button.visible = false
	_buildings = []
	if building_picker != null:
		building_picker.clear()
		building_picker.visible = false
		building_row.visible = false

func _select_items(tile: Vector3i) -> void:
	if selection_panel != null and world.is_live():
		var kind := 0
		var id := -1
		if _preferred_unit >= 0: kind = 1; id = _preferred_unit
		elif _preferred_building >= 0: kind = 3; id = _preferred_building
		elif _preferred_item >= 0: kind = 2; id = _preferred_item
		selection_panel.open_target(tile,kind,id)
		return
	_cue("select")
	_clear_items()
	_item_tile = tile
	_refresh_items(_preferred_item)
	_refresh_buildings()
	if _preferred_building >= 0:
		for i in _buildings.size():
			if _buildings[i].id == _preferred_building: building_picker.select(i)
		_refresh_building_actions()
	state.note("%d item(s), %d building(s) at (%d, %d), level %d" % [_items.size(), _buildings.size(), tile.x, tile.y, tile.z])

func _refresh_items(preferred: int) -> void:
	_items = world.items_at_tile(_item_tile)
	item_picker.clear()
	for item in _items:
		item_picker.add_item("%s ×%d  (#%d)%s%s%s" % [item.name, item.stack, item.id, " · forbidden" if item.forbidden else "", " · dump" if item.dump else "", " · melt" if item.get("melt", false) else ""])
		if item.id == preferred:
			item_picker.select(item_picker.item_count - 1)
	item_picker.visible = not _items.is_empty()
	for button in _buttons:
		button.visible = not _items.is_empty()

func _pick_piece(screen: Vector2) -> Dictionary:
	var candidates := CutoutPicking.pieces(world,camera,screen,world.get_top_z())
	if world.has_method("pick_building"):
		var building: Dictionary = world.pick_building(camera.project_ray_origin(screen),camera.project_ray_normal(screen),world.get_top_z())
		if not building.is_empty():
			building["kind"] = 3
			candidates.append(building)
	return CutoutPicking.nearest(candidates)

func _can_send() -> bool:
	if not _play_enabled: return false
	if not world.is_live():
		state.note("Offline preview only — no command sent.")
		return false
	return true

func _cue(kind: String) -> void:
	if audio != null: audio.cue(kind)

func _submit(seq: int, description: String) -> void:
	if seq > 0:
		state.submitted(seq, description)
	else:
		state.note("Not sent: %s — %s" % [description, world.last_error()])

func _designate() -> void:
	if tool_picker.selected == 15 and _start.z == _end.z:
		state.note("Stairways must connect at least two elevations.")
		cancel_selection()
		return
	if not _can_send():
		return # Leave the rectangle visible for offline exploration.
	var tool: String = TOOLS[tool_picker.selected]
	var min_z := mini(_start.z, _end.z)
	var max_z := maxi(_start.z, _end.z)
	var description := "%s %d×%d at (%d,%d), z%d" % [tool, _preview.size.x, _preview.size.y, _preview.position.x, _preview.position.y, _start.z]
	if min_z != max_z: description += " to z%d" % _end.z
	match tool:
		"Chop trees", "Clear chop":
			_submit(world.designate_chop(_preview, min_z, tool == "Chop trees", int(priority.value), marker_only, max_z), description)
		"Gather plants", "Clear gather":
			_submit(world.designate_gather(_preview, min_z, tool == "Gather plants", int(priority.value), marker_only, max_z), description)
		"Ramp":
			_submit(world.designate_dig(_preview, min_z, Df3dWorld.DIG_RAMP_UP, int(priority.value), marker_only, 0, max_z), description)
		"Smooth", "Engrave":
			_submit(world.designate_smooth(_preview, min_z, Df3dWorld.SMOOTH_SMOOTH if tool == "Smooth" else Df3dWorld.SMOOTH_ENGRAVE, int(priority.value), marker_only, max_z), description)
		"Stairs":
			_submit(world.designate_stairs(_preview, min_z, max_z, int(priority.value), marker_only), description)
		"Remove stairs/ramps":
			_submit(world.designate_dig(_preview, min_z, Df3dWorld.DIG_REMOVE_STAIRS_RAMPS, int(priority.value), marker_only, 0, max_z), description)
		"Carve fortifications":
			_submit(world.designate_smooth(_preview, min_z, Df3dWorld.SMOOTH_FORTIFY, int(priority.value), marker_only, max_z), description)
		"Carve track":
			_submit(world.designate_track(_preview, _start.z, _start.x > _end.x, _start.y > _end.y, int(priority.value), marker_only, _end.z), description)
		"Convert blueprint to standard", "Convert standard to blueprint":
			_submit(world.designate_dig(_preview, min_z, Df3dWorld.DIG_ACTIVATE if tool == "Convert blueprint to standard" else Df3dWorld.DIG_MARK, int(priority.value), false, 0, max_z), description)
		"Remove":
			_submit(world.designate_dig(_preview, min_z, Df3dWorld.DIG_REMOVE, int(priority.value), false, 0, max_z), description + " dig")
			_submit(world.designate_smooth(_preview, min_z, Df3dWorld.SMOOTH_REMOVE, int(priority.value), false, max_z), description + " smooth/engrave")
		_:
			var kinds := {"Dig": Df3dWorld.DIG_DIG, "Channel": Df3dWorld.DIG_CHANNEL, "Stairs up": Df3dWorld.DIG_STAIRS_UP, "Stairs down": Df3dWorld.DIG_STAIRS_DOWN, "Stairs up/down": Df3dWorld.DIG_STAIRS_UP_DOWN}
			_submit(world.designate_dig(_preview, min_z, kinds[tool], int(priority.value), marker_only, mining_mode if tool == "Dig" else 0, max_z), description)
	cancel_selection()

func _item_flags(forbidden: int, dump: int, melt := -1) -> void:
	if _items.is_empty() or not _can_send():
		return
	var item: Dictionary = _items[item_picker.selected]
	# Re-query: an item may have moved/vanished since it was picked. Never
	# apply an action to a stale selection that is no longer on this tile.
	var present := false
	for current in world.items_at_tile(_item_tile):
		if current.id == item.id:
			present = true
	if not present:
		state.note("Item moved or disappeared; select it again.")
		_clear_items()
		return
	var action := ("Forbid" if forbidden == 1 else "Reclaim") if forbidden >= 0 else ("Dump" if dump == 1 else "Cancel dump")
	if melt >= 0: action = "Melt" if melt == 1 else "Cancel melt"
	var f := Df3dWorld.FLAG_UNCHANGED if forbidden < 0 else (Df3dWorld.FLAG_SET if forbidden == 1 else Df3dWorld.FLAG_CLEAR)
	var d := Df3dWorld.FLAG_UNCHANGED if dump < 0 else (Df3dWorld.FLAG_SET if dump == 1 else Df3dWorld.FLAG_CLEAR)
	var m := Df3dWorld.FLAG_UNCHANGED if melt < 0 else (Df3dWorld.FLAG_SET if melt == 1 else Df3dWorld.FLAG_CLEAR)
	_submit(world.set_item_flags(item.id, f, d, m), "%s item #%d" % [action, item.id])

func _refresh_buildings() -> void:
	if not world.has_method("buildings_at_tile"): return
	var old_id: int = _buildings[building_picker.selected].id if not _buildings.is_empty() and building_picker.selected >= 0 else -1
	_buildings = world.buildings_at_tile(_item_tile)
	building_picker.clear()
	for b in _buildings:
		building_picker.add_item("%s (#%d) - %s%s" % [b.name, b.id, "complete" if b.complete else "under construction", " - forbidden" if b.forbidden else ""])
		if b.id == old_id: building_picker.select(building_picker.item_count - 1)
	building_picker.visible = not _buildings.is_empty()
	_refresh_building_actions()

func _refresh_building_actions() -> void:
	building_row.visible = not _buildings.is_empty() and bool(_buildings[building_picker.selected].can_forbid)
	if building_row.visible:
		var b: Dictionary = _buildings[building_picker.selected]
		building_row.get_child(0).disabled = b.forbidden or not b.complete
		building_row.get_child(1).disabled = not b.forbidden or not b.complete

func _building_flags(forbidden: bool) -> void:
	if _buildings.is_empty() or not _can_send(): return
	var selected: Dictionary = _buildings[building_picker.selected]
	for current in world.buildings_at_tile(_item_tile):
		if current.id == selected.id and current.can_forbid and current.complete:
			_submit(world.set_building_flags(current.id, Df3dWorld.FLAG_SET if forbidden else Df3dWorld.FLAG_CLEAR), "%s %s #%d" % ["Forbid" if forbidden else "Allow", current.name, current.id])
			return
	state.note("Building changed or disappeared; select it again.")
	_refresh_buildings()

func _pause(paused: bool) -> void:
	if _can_send():
		_submit(world.send_set_pause(paused), "Pause" if paused else "Resume")

var _marker_revision := -1
var marker_scan_count := 0
var overlay_build_count := 0
func set_show_priorities(value: bool) -> void:
	if show_priorities == value: return
	show_priorities = value
	_draw_overlay()

func set_show_traffic(value: bool) -> void:
	if show_traffic == value: return
	show_traffic = value
	_draw_overlay()

func _draw_overlay() -> void:
	overlay_build_count += 1
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	if _order_sprites != null: _order_sprites.update_markers(_markers, _z, show_priorities, show_traffic, tool_picker.selected in [1,2,3,4,5,9,15,16] and not shell_blocked and not construction_active)
	if _cursor_sprites != null:
		if tool_picker.selected == 18: _cursor_sprites.update_track_cursor(_track_preview, world.get_top_z())
		else: _cursor_sprites.update_cursor(_preview, world.get_top_z())
	# ImmediateMesh requires vertices even when the overlay is empty.
	mesh.surface_set_color(Color(0, 0, 0))
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
	_lines.mesh = mesh
