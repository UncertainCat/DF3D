extends "res://scripts/farm_panel.gd"
signal removal_handoff(id: int)
func _init() -> void:state=preload("res://scripts/pending_building_state.gd").new()
func _create_view():return preload("res://scripts/pending_building_view.gd").new()
func _open_state(id: int,_season: int) -> void:state.open(id)
func _contents_supported() -> bool:return true
func configure(world,service,host,help=null) -> void:
	super.configure(world,service,host,help)
	state.retired.connect(func(id,removing):
		close_panel()
		if removing:removal_handoff.emit(id))
