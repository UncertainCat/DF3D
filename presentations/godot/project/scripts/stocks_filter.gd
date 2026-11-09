extends "res://scripts/area_owner_filter.gd"
# Native Stocks empty, unfocused filter hint (capture215344).
func _draw() -> void:
	if value.is_empty() and not has_focus() and theme!=null and theme.default_font!=null:
		theme.default_font.draw_string(get_canvas_item(),Vector2(16,24),"...",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
	else:super._draw()
