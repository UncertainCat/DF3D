extends "res://scripts/lever_tasks_view.gd"
# Native completed plates share the queue but offer only Link plate.
# Missing mechanisms leave this control unchanged (native1ad7f3..1ad801).
func creation_click(point: Vector2) -> bool:
	if not lever_button(0).has_point(point):return false
	link_requested.emit();return true
func draw_creation_controls() -> void:
	var rect:=lever_button(0)
	patch("HORIZONTAL_OPTION_ACTIVE",Rect2(rect.position-Vector2(0,6),rect.size+Vector2(0,12)))
	caption("Link plate",rect.position+Vector2(8,18),10)
