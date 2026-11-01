extends "res://scripts/farm_panel.gd"
# Staged workshop owner; the caller supplies the installed subtype icon.
var tasks=preload("res://scripts/workshop_tasks_state.gd").new()

func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()

func configure(world,service,host,help=null) -> void:
	tasks.configure(service)
	super.configure(world,service,host,help)
	panel.configure_tasks(world,tasks,"")
	tasks.applied.connect(state.refresh)
	tasks.applied.connect(contents.refresh)

func _create_view():return preload("res://scripts/workshop_sheet_view.gd").new()
func _open_state(id: int,_season: int) -> void:
	tasks.close();state.open(id)
func _contents_supported() -> bool:return true

func open_workshop(id: int,icon: String) -> void:
	if panel==null:return
	panel.building_icon=icon;open_target(id)

func _state_changed() -> void:
	super._state_changed()
	if opening:return
	if state.building_id<0 or state.snapshot.get("removing",false):tasks.close()
	elif not state.snapshot.is_empty() and tasks.building_id!=state.building_id:tasks.open(state.building_id)

func close_panel() -> void:
	tasks.close();super.close_panel()

func _exit_tree() -> void:
	tasks.dispose();super._exit_tree()
