extends Node
signal input_gate_changed
signal views_reset
# Sole owner of local panel and world-input transitions. Requests live elsewhere.
var interaction
var active: Node
var play_enabled := true
var overlay_blocked := false
var controllers: Array[WeakRef] = []
var overlay_shield: Control

func _ready() -> void:
	# Native panel layers are below this; HUD overlays are on layer 20.
	# Block GUI dispatch too, not just world-event handlers behind the overlay.
	var layer := CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	overlay_shield = Control.new()
	overlay_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay_shield)
	overlay_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_shield.visible = overlay_blocked

func _set_panel_focus(enabled: bool) -> void:
	if is_instance_valid(active) and "panel" in active and active.panel is Control:
		active.panel.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if enabled else Control.FOCUS_BEHAVIOR_DISABLED

func register(controller: Node) -> void:
	controller.ui_host = self
	controllers.append(weakref(controller))
	controller.tree_exiting.connect(func(): release(controller))
	controller.set_play_enabled(play_enabled)

func activate(controller: Node) -> bool:
	if not play_enabled or overlay_blocked or not is_instance_valid(controller): return false
	if is_instance_valid(active) and active != controller: active.close_panel()
	active = controller
	interaction.cancel_selection()
	_sync_input()
	return true

func release(controller: Node) -> void:
	if active != controller: return
	_set_panel_focus(true)
	active = null
	_sync_input()

func close_active() -> void:
	_set_panel_focus(true)
	if is_instance_valid(active): active.close_panel()
	active = null
	_sync_input()

func set_play_enabled(value: bool) -> void:
	if value == play_enabled: return
	play_enabled = value
	if not value: close_active()
	interaction.set_play_enabled(value)
	for reference in controllers:
		var controller = reference.get_ref()
		if is_instance_valid(controller): controller.set_play_enabled(value)
	_sync_input()

func set_overlay_blocked(value: bool) -> void:
	if value == overlay_blocked: return
	overlay_blocked = value
	if overlay_shield != null: overlay_shield.visible = value
	_set_panel_focus(not value)
	if value:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null: focused.release_focus()
		interaction.cancel_selection()
		if is_instance_valid(active) and active.has_method("cancel_gesture"):
			active.cancel_gesture()
	_sync_input()

func allows_panel_input(controller: Node) -> bool:
	return play_enabled and not overlay_blocked and active == controller

func allows_minimap_input() -> bool:
	if not play_enabled or overlay_blocked:return false
	if not is_instance_valid(active) or not active.modal_input:return true
	return active.has_method("allows_minimap_input") and active.allows_minimap_input()

func allows_elevation_input() -> bool:
	if not play_enabled or overlay_blocked: return false
	if not is_instance_valid(active) or not active.modal_input: return true
	return active.has_method("allows_elevation_input") and active.allows_elevation_input()

func _sync_input() -> void:
	interaction.construction_active = is_instance_valid(active) and bool(active.modal_input)
	interaction.shell_blocked = overlay_blocked
	interaction.panel.visible = play_enabled and not interaction.construction_active and not overlay_blocked and not interaction.shell_enabled
	input_gate_changed.emit()

func reset_local_views() -> void:
	close_active()
	views_reset.emit()
	interaction.cancel_selection()
	# Submitted operations remain owned by the action service; never replay them.

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			reset_local_views()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_instance_valid(active) and not overlay_blocked:
			if active.has_method("handle_back"): active.handle_back()
			else: close_active()
			get_viewport().set_input_as_handled()
