extends Node
# The launcher owns process cleanup. Closing never invents a save or its outcome.
signal close_requested
var world
var closing := false
var latest: Dictionary = {}
var confirmation: Control
var prompt = preload("res://scripts/native_options_confirmation.gd").new()
var art_ready := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	confirmation = Control.new()
	confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(confirmation)
	confirmation.add_child(prompt)
	prompt.confirm_allowed = func(): return not save_pending()
	prompt.confirmed.connect(func(_token): confirm_close())
	prompt.cancelled.connect(confirmation.hide)
	confirmation.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_close()

func request_close() -> void:
	if closing: return
	# Assets load after this controller is created; resolve them on first use.
	if not art_ready:
		prompt.configure(world)
		art_ready = true
	confirmation.show()
	prompt.display("QUIT_WITHOUT_SAVING")
	prompt.layout_reference()
	update_session(latest)

func save_pending() -> bool:
	return latest.get("phase",4) in [6,7] or latest.get("request_status",0) == 1

func update_session(state: Dictionary) -> void:
	latest = state.duplicate(true)
	if confirmation == null: return
	prompt.queue_redraw()

func _input(event: InputEvent) -> void:
	# This modal must not send shortcuts to the underlying viewer or DF panels.
	if confirmation != null and confirmation.visible and event is InputEventKey:
		get_viewport().set_input_as_handled()

func confirm_close() -> void:
	if closing or save_pending(): return
	closing = true
	close_requested.emit()
