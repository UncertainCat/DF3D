extends "res://scripts/farm_panel.gd"
signal focus_requested(tile: Vector3i)
var links=preload("res://scripts/building_links_state.gd").new()
var access=preload("res://scripts/door_controls_state.gd").new()
# Ordinary furniture uses native header and contained-item authority.
func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()
	contents.edit_removing=true
func _create_view():
	var view=preload("res://scripts/barrier_sheet_view.gd").new()
	view.building_icon="" # Native artwork is authoritative; no Box fallback for other furniture.
	return view
func _open_state(id: int,_season: int) -> void:state.open(id)
func _contents_supported() -> bool:return true
func configure(world,service,host,help=null) -> void:
	links.configure(service)
	access.configure(service)
	super.configure(world,service,host,help)
	panel.configure_links(world,links,help)
	panel.configure_access(world,access)
	access.applied.connect(contents.refresh)
	panel.links_view.recenter_requested.connect(func(tile):
		if panel.contents_allowed() and links.phase==links.Phase.Ready:
			close_panel();focus_requested.emit(tile))
func _state_changed() -> void:
	super._state_changed()
	if state.snapshot.get("type",-1) in [9,23,33,35,36,37,38,39,40,41,42,43,44,50]:
		if links.building_id!=state.building_id:links.open(state.building_id)
	elif links.building_id>=0:links.close()
	if state.snapshot.get("type",-1)==35 and not state.snapshot.get("removing",true):
		if access.building_id!=state.building_id:access.open(state.building_id)
	elif access.building_id>=0:access.close()
func close_panel() -> void:
	access.close();links.close();super.close_panel()
func _exit_tree() -> void:
	access.dispose();links.dispose();super._exit_tree()

func _process(delta: float) -> void:
	super._process(delta)
	if panel!=null and panel.visible and play_enabled and contents.ticket==0:
		state.poll_refresh(delta)
		if state.phase==state.Phase.Ready and state.ticket==0 and state.name_session==null:
			contents.poll_refresh(delta)
			links.poll_refresh(delta)
