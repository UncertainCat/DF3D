extends Node
# RC cut: closing the presentation leaves the separately owned DF process running.
# Save-and-close is deferred until explicit native destination/confirmation flows
# are complete. Never submit an implicit save or infer its outcome on viewer exit.
signal close_requested
var world
var closing := false
func _ready() -> void:
	get_tree().auto_accept_quit = false
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not closing:
		closing = true
		close_requested.emit()
func update_session(_state: Dictionary) -> void:
	pass
