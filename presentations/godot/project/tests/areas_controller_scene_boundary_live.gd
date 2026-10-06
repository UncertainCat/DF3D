extends "res://tests/areas_controller_scene_live.gd"
# Focused boundary-cell regression, not full Areas acceptance. Uses the same
# protected fixture, viewport driver, native readbacks and cleanup as the suite.
func pointer_areas() -> void:
	await pointer_zone_boundary_cells()
	if not stopped: await native("final")
