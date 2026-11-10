extends Node
# Staged composition: public Residents remains on its existing route until complete.
signal information_requested(caption: String)
signal focus_requested(tile: Vector3i)
signal inspect_requested(tile: Vector3i,unit_id: int)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/residents_state.gd").new()
var job_state=preload("res://scripts/job_settings_state.gd").new()
var job_panel
var layout_size:=Vector2.ZERO
var opening:=false

func _init() -> void:
	state.changed.connect(_sync)
	job_state.changed.connect(_sync)
	job_state.applied.connect(func():
		if state.phase==state.Phase.Ready:state.refresh())
	state.inspect_ready.connect(func(tile,id):
		if allowed():inspect_requested.emit(tile,id))
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service);job_state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/residents_view.gd").new();layer.add_child(panel)
	panel.configure_residents(world,state);panel.input_allowed=func():return allowed() and not job_open()
	panel.cancelled.connect(close_panel)
	panel.information_requested.connect(func(caption):
		if allowed():information_requested.emit(caption))
	panel.focus_requested.connect(_focus)
	panel.inspect_requested.connect(state.inspect)
	panel.job_requested.connect(_job)
	job_panel=preload("res://scripts/work_order_details_view.gd").new();job_panel.job_context=true;layer.add_child(job_panel)
	job_panel.configure_details(world,job_state);job_panel.input_allowed=func():return allowed() and job_open()
	job_panel.cancelled.connect(job_state.close)
	host.register(self);_layout();_sync()
func allowed() -> bool:
	return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;state.open();opening=false;_sync()
func close_panel() -> void:state.close()
func job_open() -> bool:return job_state.phase!=job_state.Phase.Closed
func _job(id: int) -> void:
	if not allowed() or job_open() or state.phase!=state.Phase.Ready or state.ticket!=0:return
	var target: Dictionary=state.rows.get(id,{}).get("job_target",{})
	if target.is_empty():return
	job_state.open(int(target.building_id),int(target.job_id),id);_sync()
func handle_back() -> void:
	if job_open():job_panel.back()
	else:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if not opened and job_open():job_state.close()
	if panel!=null:panel.visible=opened and not job_open()
	if job_panel!=null:job_panel.visible=opened and job_open()
	if not opened and not opening and ui_host!=null:ui_host.release(self)
func _focus(tile: Vector3i) -> void:
	if not allowed() or state.phase!=state.Phase.Ready:return
	close_panel();focus_requested.emit(tile)
func _layout() -> void:
	if panel==null:return
	var size:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	panel.scale=scale;layout_size=size;panel.layout(size/scale)
	if job_panel!=null:job_panel.scale=scale;job_panel.layout(size/scale)
func _process(_delta: float) -> void:
	if panel!=null and (panel.visible or job_open()) and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:
	job_state.dispose();state.dispose()
