extends "res://scripts/machinery_sheet_view.gd"
var access_controls
func configure_access(source,model) -> void:
	access_controls=preload("res://scripts/door_controls_view.gd").new()
	add_child(access_controls);access_controls.configure(source,model)
	access_controls.input_allowed=func():return contents_allowed() and not removing and state.snapshot.get("type",-1)==35
	refresh()
func refresh() -> void:
	super.refresh()
	if access_controls!=null:access_controls.visible=not removing and state.snapshot.get("type",-1)==35
