extends "res://scripts/farm_panel.gd"
# Staged Box owner shares input/navigation lifetime, never farm simulation facts.
func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()
	contents.edit_removing=true
func _create_view():return preload("res://scripts/chest_sheet_view.gd").new()
func _open_state(id: int,_season: int) -> void:state.open(id)
func _contents_supported() -> bool:return true
