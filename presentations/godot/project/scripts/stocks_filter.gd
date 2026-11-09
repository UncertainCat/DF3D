extends "res://scripts/area_owner_filter.gd"
# Native Stocks empty, unfocused filter hint (capture215344).
var focused_before_click:=false

func _input(event: InputEvent) -> void:
	# Capture before Godot's FOCUS_CLICK handling focuses the control.
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		focused_before_click=has_focus()

func _gui_input(event: InputEvent) -> void:
	if editable and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if focused_before_click:release_focus()
		else:grab_focus()
		accept_event()

func feed_key(event: InputEventKey) -> void:
	# Native012659 stores ASCII text uppercase. Keep the inherited byte-oriented
	# backspace and non-ASCII path; do not apply Unicode case expansion.
	if event.unicode>=97 and event.unicode<=122:
		var normalized: InputEventKey=event.duplicate();normalized.unicode-=32
		super.feed_key(normalized)
	else:super.feed_key(event)

func _draw() -> void:
	if value.is_empty() and not has_focus() and theme!=null and theme.default_font!=null:
		theme.default_font.draw_string(get_canvas_item(),Vector2(16,24),"...",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
	else:super._draw()
