extends "res://scripts/farm_panel.gd"
# Ordinary furniture uses native header and contained-item authority.
func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()
	contents.edit_removing=true
func _create_view():
	var view=preload("res://scripts/funerary_sheet_view.gd").new()
	view.building_icon="" # Native artwork is authoritative; no Box fallback for other furniture.
	return view
func _open_state(id: int,_season: int) -> void:state.open(id)
func _contents_supported() -> bool:return true

func _process(delta: float) -> void:
	super._process(delta)
	if panel!=null and panel.visible and play_enabled and contents.ticket==0:
		state.poll_refresh(delta)
		if state.phase==state.Phase.Ready and state.ticket==0 and state.name_session==null:
			contents.poll_refresh(delta)
