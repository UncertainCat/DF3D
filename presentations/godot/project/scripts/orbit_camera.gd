# Layer-4 camera modes: DF is north-up orthographic; Free retains orbit/fly.
extends Node3D
signal mode_changed

@export var move_speed := 20.0
@export var orbit_sensitivity := 0.006
@export var pan_sensitivity := 0.05
@export var zoom_factor := 1.12
@export var min_distance := 3.0
@export var max_distance := 400.0
var _distance := 60.0
var _yaw := 0.0
var _pitch := -0.9
var _df_mode := false
var _mode := "free"
var walk_world
var _ground = preload("res://scripts/walk_controller.gd").new()
var _walk_return: Dictionary = {}
var _walk_panel: PanelContainer
var _walk_pointer_key: Label
var _walk_pointer_action: Label
const WALK_EYE := 0.54

func is_walk_mode() -> bool:
	return _mode == "walk"

func exit_walk() -> void:
	if is_walk_mode(): set_mode("free")

func _input(event: InputEvent) -> void:
	if not is_walk_mode(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_F4, KEY_F5]:
			exit_walk()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
	if controls_blocked():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and get_viewport().gui_get_hovered_control() == null:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch-event.relative.y*0.003, -1.45, 1.45)
		_update_transform()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_ground.jump()
	# Mouse actions cannot designate or select through the visitor camera.
	if event is InputEventMouse or event is InputEventKey:
		get_viewport().set_input_as_handled()

func _walk_window(force := false) -> void:
	var level := floori(position.y)
	# Hysteresis keeps the visible ceiling stable during small jumps.
	var current: int = walk_world.get_top_z()
	if not force and current>=mini(level+2,walk_world.map_size().y-1) and current<=level+6: return
	var ceiling := clampi(level + 4, 0, walk_world.map_size().y - 1)
	if walk_world.get_top_z() != ceiling: walk_world.set_top_z(ceiling)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		if is_walk_mode(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
const ISO_YAW := PI / 4.0
const ISO_PITCH := -0.6154797087 # Equal foreshortening of all three axes.
var _df_size := 0.0
# DF framing is independent of the free camera's whole-map auto-fit distance.
# Store pixel scale so resizing reveals more tiles rather than shrinking them.
const DEFAULT_DF_TILE_PIXELS := 32.0
var _df_pixels_per_tile := DEFAULT_DF_TILE_PIXELS
var _top_z := -1
# Capture rigs can aim below the visible ceiling without changing the cutaway.
var level_focus_offset := 0.0
@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 5
	add_child(overlay)
	_walk_panel = PanelContainer.new()
	_walk_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walk_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	overlay.add_child(_walk_panel)
	var groups := HBoxContainer.new()
	groups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groups.add_theme_constant_override("separation", 24)
	_walk_panel.add_child(groups)
	# Group movement, vertical traversal and mouse/mode ownership separately.
	_add_walk_bindings(groups, [["WASD", "Move"], ["Shift", "Faster"]])
	_add_walk_bindings(groups, [["Space", "Jump"], ["Hold Space", "Stairs up"], ["Hold Q", "Stairs down"]])
	var session := _add_walk_bindings(groups, [["Click", "Look around"], ["F5", "Exit walk"]])
	_walk_pointer_key = session.get_child(0)
	_walk_pointer_action = session.get_child(1)
	_walk_panel.hide()
	get_viewport().size_changed.connect(_viewport_resized)
	_update_transform()

func _viewport_resized() -> void:
	if _df_mode: _update_transform()
	_layout_walk_help()

func configure_walk_help(ui, frame: StyleBox) -> void:
	ui.apply(_walk_panel)
	ui.install_hud_filter(_walk_panel)
	_walk_panel.add_theme_stylebox_override("panel", frame.duplicate())
	_layout_walk_help()

func _add_walk_bindings(parent: Control, bindings: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for binding in bindings:
		for index in 2:
			var label := Label.new()
			label.text = binding[index]
			label.add_theme_font_size_override("font_size", 12)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if index == 0: label.add_theme_color_override("font_color", Color.YELLOW)
			grid.add_child(label)
	return grid

func _layout_walk_help() -> void:
	var view := get_viewport().get_visible_rect().size
	_walk_panel.scale = preload("res://scripts/presentation_settings.gd").effective_scale_vector(view)
	_walk_panel.size = _walk_panel.get_combined_minimum_size()
	var extent := _walk_panel.size * _walk_panel.scale
	_walk_panel.position = Vector2((view.x - extent.x) / 2.0, view.y - extent.y - 18)

func is_df_mode() -> bool:
	return _df_mode

func get_mode() -> String:
	return _mode

func set_mode(value: String) -> void:
	if value not in ["df", "isometric", "free", "walk"] or value == _mode: return
	if value == "walk":
		if walk_world == null or not walk_world.terrain_loaded(): return
		_ground.world = walk_world
		# The orbit node is a focus point; transfer the actual camera pose.
		var eye := _camera.global_position
		var angles := _camera.global_basis.get_euler()
		_walk_return = {"near":_camera.near}
		_ground.reset(eye - Vector3.UP * WALK_EYE, false)
		global_position = _ground.feet
		_pitch = angles.x
		_yaw = angles.y
		_camera.near = 0.025
		_walk_window(true)
	elif is_walk_mode():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var eye := _camera.global_position
		# Free orbit reconstructs its focus from the current eye and direction.
		global_position = eye - _offset()
		_camera.near = _walk_return.near
	_mode = value
	_walk_panel.visible = is_walk_mode()
	if is_walk_mode(): _refresh_walk_help()
	_df_mode = value == "df"
	if value in ["df", "isometric"] and _top_z >= 0: position.y = float(_top_z) + 1.0 + level_focus_offset
	_update_transform()
	mode_changed.emit()

func set_df_mode(enabled: bool) -> void:
	set_mode("df" if enabled else "free")

func toggle_mode() -> void:
	if is_walk_mode():
		exit_walk()
		return
	var modes := ["df", "isometric", "free"]
	set_mode(modes[(modes.find(_mode) + 1) % modes.size()])

func follow_level(top_z: int) -> void:
	_top_z = top_z
	if _mode in ["df", "isometric"]:
		position.y = float(top_z) + 1.0 + level_focus_offset
		_update_transform()

func controls_blocked() -> bool:
	if not can_process(): return true
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return true
	for panel in get_tree().get_nodes_in_group("audio_panel"):
		if panel.blocks_camera(): return true
	for hud in get_tree().get_nodes_in_group("fortress_hud"):
		if hud.blocks_camera(): return true
	return false

func _horizontal_forward() -> Vector3:
	# Use yaw rather than projecting the view vector: the pole has no horizontal view vector.
	var yaw := ISO_YAW if _mode == "isometric" else _yaw
	return Vector3.FORWARD if _df_mode else Vector3(-sin(yaw), 0.0, -cos(yaw))

func _unhandled_input(event: InputEvent) -> void:
	if controls_blocked(): return
	if is_walk_mode():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT and _mode == "free":
			_yaw -= motion.relative.x * orbit_sensitivity
			_pitch = clampf(_pitch - motion.relative.y * orbit_sensitivity, -PI / 2.0, PI / 2.0)
			_update_transform()
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right := _camera.global_transform.basis.x
			var forward := _horizontal_forward()
			var scale := _df_size / maxf(1.0, get_viewport().get_visible_rect().size.y) if _df_mode else pan_sensitivity * (_distance / 60.0)
			position += (-right * motion.relative.x + forward * motion.relative.y) * scale
			_update_transform()
	elif event is InputEventMouseButton and event.pressed:
		var btn := event as InputEventMouseButton
		if btn.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.0 / zoom_factor if btn.button_index == MOUSE_BUTTON_WHEEL_UP else zoom_factor
			if _df_mode:
				_df_size = clampf(_df_size * factor, min_distance, max_distance)
				_df_pixels_per_tile = maxf(1.0, get_viewport().get_visible_rect().size.y) / _df_size
			else: _distance = clampf(_distance * factor, min_distance, max_distance)
			_update_transform()

func _refresh_walk_help() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_walk_pointer_key.text = "Esc" if captured else "Click"
	_walk_pointer_action.text = "Release mouse" if captured else "Look around"
	_layout_walk_help()

func _process(delta: float) -> void:
	var blocked := controls_blocked()
	_walk_panel.visible = is_walk_mode() and not blocked
	if _walk_panel.visible: _refresh_walk_help()
	if blocked:
		if is_walk_mode(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if is_walk_mode() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		global_position = _ground.advance(delta, Vector3.ZERO)
		_walk_window()
		_update_transform()
		return
	var dir := Vector3.ZERO
	var forward := _horizontal_forward()
	var right := forward.cross(Vector3.UP)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir += forward
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir -= forward
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir -= right
	if _mode == "free":
		if Input.is_key_pressed(KEY_E): dir += Vector3.UP
		if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	if is_walk_mode():
		global_position = _ground.advance(delta,dir,Input.is_key_pressed(KEY_SHIFT),Input.is_key_pressed(KEY_SPACE),Input.is_key_pressed(KEY_Q))
		_walk_window()
		_update_transform()
		return
	if dir != Vector3.ZERO:
		var speed := move_speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		position += dir.normalized() * speed * delta
		_update_transform()

func current_distance() -> float:
	return _distance

func focus_on(point: Vector3, distance: float) -> void:
	# Explicit map/entity navigation returns to the normal viewing camera.
	exit_walk()
	position = point
	_distance = clampf(distance, min_distance, max_distance)
	if _df_mode and _top_z >= 0: position.y = float(_top_z) + 1.0 + level_focus_offset
	_update_transform()

# Deterministic presentation-only path used by repeatable encounter captures.
func set_orbit_pose(yaw: float, pitch: float, distance: float = -1.0) -> void:
	_yaw = yaw
	if distance > 0: _distance = clampf(distance, min_distance, max_distance)
	_pitch = clampf(pitch, -1.55, -0.05)
	_update_transform()

func place_eye(eye: Vector3, distance: float) -> void:
	_distance = clampf(distance, min_distance, max_distance)
	position = eye - _offset()
	_update_transform()

func _offset() -> Vector3:
	var pitch := ISO_PITCH if _mode == "isometric" else _pitch
	var yaw := ISO_YAW if _mode == "isometric" else _yaw
	return Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * _distance

func _update_transform() -> void:
	if is_walk_mode():
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.position = Vector3.UP * WALK_EYE
		_camera.rotation = Vector3(_pitch, _yaw, 0)
	elif _df_mode:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_df_size = clampf(maxf(1.0, get_viewport().get_visible_rect().size.y) / _df_pixels_per_tile, min_distance, max_distance)
		_camera.size = _df_size
		_camera.position = Vector3.UP * _distance
		_camera.look_at(global_position, Vector3.FORWARD)
	else:
		# Independent offline art-comparison hook, including exact pole orientation.
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if _mode == "isometric" or OS.get_environment("DF3D_CAM_ORTHO") == "1" else Camera3D.PROJECTION_PERSPECTIVE
		_camera.size = _distance
		_camera.position = _offset()
		_camera.look_at(global_position, Vector3.FORWARD if absf(cos(_pitch)) < 0.00001 else Vector3.UP)
