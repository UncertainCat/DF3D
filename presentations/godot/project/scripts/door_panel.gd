extends "res://scripts/chest_panel.gd"
# Staged owner; public routing waits for full-sheet native qualification.
var door=preload("res://scripts/door_controls_state.gd").new()

func configure(world,service,host,help=null) -> void:
	door.configure(service)
	super.configure(world,service,host,help)
	panel.configure_controls(world,door)
	door.applied.connect(contents.refresh)

func _create_view():return preload("res://scripts/door_sheet_view.gd").new()

func _state_changed() -> void:
	super._state_changed()
	if state.snapshot.is_empty() or state.snapshot.get("removing",false):
		if door.building_id>=0:door.close()
	elif door.building_id!=state.building_id:door.open(state.building_id)

func close_panel() -> void:
	door.close();super.close_panel()

func _exit_tree() -> void:
	door.dispose();super._exit_tree()
