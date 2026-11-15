extends "res://scripts/chest_sheet_view.gd"
var door_controls

func _init() -> void:
	building_icon="BUILDING_ICON_DOOR"

func configure_controls(source,model) -> void:
	door_controls=preload("res://scripts/door_controls_view.gd").new()
	add_child(door_controls);door_controls.configure(source,model)
	door_controls.input_allowed=func():return allowed() and state.phase==state.Phase.Ready and not removing
	refresh()

func refresh() -> void:
	super.refresh()
	if door_controls!=null:door_controls.visible=not removing and not state.snapshot.is_empty()
