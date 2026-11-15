extends "res://scripts/workshop_panel.gd"
# Staged complete lever owner. Public selection remains gated until composed
# workflows are qualified; all map intent belongs to this panel, not native UI.
signal focus_requested(tile: Vector3i)
var links=preload("res://scripts/building_links_state.gd").new()
var lever
func _create_view():return preload("res://scripts/lever_sheet_view.gd").new()
func configure(world,service,host,help=null) -> void:
	links.configure(service)
	super.configure(world,service,host,help)
	panel.configure_links(world,links,help)
	panel.links_view.recenter_requested.connect(func(tile):
		if panel.contents_allowed() and links.phase==links.Phase.Ready:
			close_panel();focus_requested.emit(tile))
	lever=preload("res://scripts/lever_link_owner.gd").new();add_child(lever)
	lever.configure(world,service,canvas)
	lever.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self)
	lever.changed.connect(_lever_changed)
	lever.applied.connect(func(_operation,_job_id):tasks.refresh();contents.refresh();state.refresh();links.poll_refresh(0.5))
	panel.tasks.link_requested.connect(lever.begin_link)
	panel.tasks.pull_requested.connect(lever.pull)
	var ordinary_input: Callable=panel.input_allowed
	panel.input_allowed=func():return ordinary_input.call() and (state.snapshot.get("removing",false) or lever.state.phase==lever.state.Phase.Ready) and not lever.targeting
func _open_state(id: int,season: int) -> void:
	if lever!=null:lever.close()
	links.close();super._open_state(id,season)
func _state_changed() -> void:
	super._state_changed()
	if lever==null:return
	if state.building_id<0 or state.snapshot.get("removing",false):
		lever.close();links.close();return
	if state.phase!=state.Phase.Ready or state.snapshot.get("type",-1)!=23:return
	if links.building_id!=state.building_id:links.open(state.building_id)
	# A confirmed task/header edit changes the source authority. Refresh only
	# an idle successful observation; never clear an unknown mutation outcome.
	if lever.state.building_id!=state.building_id or (lever.state.phase==lever.state.Phase.Ready and lever.state.snapshot.get("revision",0)!=state.snapshot.revision):
		lever.open(state.building_id,state.snapshot.native_name)
	_lever_changed()
func _lever_changed() -> void:
	if lever==null or panel==null:return
	modal_input=lever.targeting or _connections_open()
	ui_host._sync_input()
	if lever.targeting:panel.hide()
	elif state.building_id>=0 and not _job_details_open() and not connections.picking:panel.show()
func close_panel() -> void:
	if lever!=null:lever.close()
	links.close();super.close_panel()
func _exit_tree() -> void:
	links.dispose();super._exit_tree()
func _process(delta: float) -> void:
	super._process(delta)
	if lever==null:return
	var viewport:=get_viewport().get_visible_rect().size
	var view:=viewport/Preferences.effective_scale_vector(viewport)
	lever.layout(Vector2(32,48+fposmod(view.y,12)*0.5))
	if panel.visible and play_enabled and contents.ticket==0 and lever.state.phase==lever.state.Phase.Ready:
		state.poll_refresh(delta)
		if state.phase==state.Phase.Ready and state.ticket==0 and state.name_session==null:
			contents.poll_refresh(delta);links.poll_refresh(delta)
func _input(event: InputEvent) -> void:
	if lever!=null and lever.targeting:
		if play_enabled and ui_host.allows_panel_input(self) and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			lever.cancel();get_viewport().set_input_as_handled()
		return
	super._input(event)
func handle_escape() -> void:
	if lever!=null and lever.targeting:lever.cancel()
	else:super.handle_escape()
func _unhandled_input(event: InputEvent) -> void:
	if lever==null or not lever.targeting:super._unhandled_input(event);return
	if not play_enabled or not ui_host.allows_panel_input(self):return
	if camera!=null and event is InputEventMouseMotion:
		lever.hover_tile(connection_world.pick_tile(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position),connection_world.get_top_z()))
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and camera!=null:
			lever.click_tile(connection_world.pick_tile(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position),connection_world.get_top_z()))
		get_viewport().set_input_as_handled()
