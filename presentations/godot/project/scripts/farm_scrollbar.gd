extends "res://scripts/area_location_scrollbar.gd"
# The farm sheet handles scrollbar clicks/drags but ignores scroll-key events.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event();return
	super._gui_input(event)
