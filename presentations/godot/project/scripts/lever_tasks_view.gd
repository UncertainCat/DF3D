extends "res://scripts/workshop_tasks_view.gd"
# Native lever Tasks uses the shared queue rows without job-details buttons.
# References: protected075033 lever-pull-2 / lever-link-target-click.
signal link_requested
signal pull_requested
func shows_job_details() -> bool:return false
func lever_button(index: int) -> Rect2:
	return Rect2(264+96*index,state.jobs().size()*36+36,96,24)
func creation_click(point: Vector2) -> bool:
	for index in 2:
		if lever_button(index).has_point(point):
			if index==0:link_requested.emit()
			else:pull_requested.emit()
			return true
	return false
func draw_creation_controls() -> void:
	for index in 2:
		var rect:=lever_button(index)
		patch("HORIZONTAL_OPTION_ACTIVE",Rect2(rect.position-Vector2(0,6),rect.size+Vector2(0,12)))
		caption("Link lever" if index==0 else "Pull lever",rect.position+Vector2(8,18),10)
