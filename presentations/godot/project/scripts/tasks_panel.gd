extends Node
# Staged Tasks owner. Public launchers remain gated until input/navigation parity.
signal information_requested(caption: String)
signal focus_requested(tile: Vector3i)
signal inspect_requested(tile: Vector3i,unit_id: int)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var job_panel
var job_state=preload("res://scripts/job_settings_state.gd").new()
var state=preload("res://scripts/tasks_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
var destination: Dictionary={}
func _init() -> void:
	state.changed.connect(_sync)
	job_state.changed.connect(_sync)
	job_state.applied.connect(func():
		if state.phase==state.Phase.Ready:state.refresh())
	state.inspect_ready.connect(func(tile,id):
		if allowed() and state.phase==state.Phase.Navigating:inspect_requested.emit(tile,id))
func configure(world,service,host,help=null) -> void:
	ui_host=host;state.configure(service);job_state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/tasks_view.gd").new();layer.add_child(panel)
	panel.configure_tasks(world,state);panel.input_allowed=func():return allowed() and not job_open()
	panel.hover_help=help
	panel.cancelled.connect(close_panel);panel.navigation_requested.connect(_navigate)
	panel.information_requested.connect(func(caption):
		if allowed():information_requested.emit(caption))
	job_panel=preload("res://scripts/work_order_details_view.gd").new();job_panel.job_context=true;job_panel.tasks_context=true;layer.add_child(job_panel)
	job_panel.configure_details(world,job_state);job_panel.input_allowed=func():return allowed() and job_open()
	job_panel.cancelled.connect(job_state.close)
	host.register(self);_layout();_sync()
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;destination={};state.open();opening=false;_sync()
func close_panel() -> void:destination={};state.close()
func job_open() -> bool:return job_state.phase!=job_state.Phase.Closed
func handle_back() -> void:
	if job_open():job_panel.back()
	else:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _navigate(row: Dictionary,worker: bool,inspect: bool) -> void:
	if not allowed() or job_open() or state.phase!=state.Phase.Ready:return
	if not state.rows.any(func(current):return current.job_id==row.get("job_id") and current.revision==row.get("revision")):return
	if inspect:
		if worker:state.inspect_worker(row.job_id)
		elif row.can_view_job and row.building_id>=0:job_state.open(row.building_id,row.job_id)
		return
	# Re-read the native semantic row before moving the camera. Never use a
	# displayed creature/building position after it has become stale.
	destination={"job_id":row.job_id,"worker":worker,"id":row.worker_id if worker else row.building_id}
	state.refresh()
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if not opened and job_open():job_state.close()
	if panel!=null:panel.visible=opened and not job_open()
	if job_panel!=null:job_panel.visible=opened and job_open()
	if not opened and not opening and ui_host!=null:ui_host.release(self)
	if not destination.is_empty() and state.phase==state.Phase.Ready:
		var target:=destination;destination={}
		for row in state.rows:
			if row.job_id!=target.job_id or (row.worker_id if target.worker else row.building_id)!=target.id:continue
			var key: String="worker_position" if target.worker else "building_position"
			if allowed() and row.has(key):
				var tile: Vector3i=row[key];close_panel();focus_requested.emit(tile)
			return
	elif state.phase in [state.Phase.Closed,state.Phase.Unavailable,state.Phase.Rejected,state.Phase.Unknown]:destination={}
func _layout() -> void:
	if panel==null:return
	var extent:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(extent)
	panel.scale=scale;layout_size=extent;panel.layout(extent/scale)
	if job_panel!=null:job_panel.scale=scale;job_panel.layout(extent/scale)
func _process(_delta: float) -> void:
	if panel!=null and (panel.visible or job_open()) and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:job_state.dispose();state.dispose()
