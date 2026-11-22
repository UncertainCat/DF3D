extends Node
# Public Residents owner; job Details shares the native-backed editor.
signal information_requested(caption: String)
signal focus_requested(tile: Vector3i)
signal inspect_requested(tile: Vector3i,unit_id: int)
signal item_inspect_requested(item_id: int)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/residents_state.gd").new()
var job_state=preload("res://scripts/job_settings_state.gd").new()
var job_panel
var pet_state=preload("res://scripts/pet_management_state.gd").new()
var pet_panel
var layout_size:=Vector2.ZERO
var opening:=false

func _init() -> void:
	state.changed.connect(_sync)
	job_state.changed.connect(_sync)
	pet_state.changed.connect(_sync)
	pet_state.applied.connect(func():
		if state.phase==state.Phase.Ready:state.refresh())
	pet_state.dismissed.connect(func():
		if state.phase==state.Phase.Ready:state.refresh())
	job_state.applied.connect(func():
		if state.phase==state.Phase.Ready:state.refresh())
	state.inspect_ready.connect(func(tile,id):
		if allowed():inspect_requested.emit(tile,id))
	state.item_inspect_ready.connect(func(id):
		if allowed():
			close_panel();item_inspect_requested.emit(id))
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service);job_state.configure(service);pet_state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/residents_view.gd").new();layer.add_child(panel)
	panel.configure_residents(world,state);panel.input_allowed=func():return allowed() and not job_open() and not pet_open()
	panel.cancelled.connect(close_panel)
	panel.information_requested.connect(func(caption):
		if allowed():information_requested.emit(caption))
	panel.focus_requested.connect(_focus)
	panel.inspect_requested.connect(state.inspect)
	panel.job_requested.connect(_job)
	panel.trainer_requested.connect(_trainer)
	panel.knowledge_requested.connect(func():
		if allowed() and not job_open() and not pet_open() and state.phase==state.Phase.Ready and state.tab==1:pet_state.open_knowledge())
	job_panel=preload("res://scripts/work_order_details_view.gd").new();job_panel.job_context=true;layer.add_child(job_panel)
	job_panel.configure_details(world,job_state);job_panel.input_allowed=func():return allowed() and job_open()
	job_panel.cancelled.connect(job_state.close)
	pet_panel=preload("res://scripts/pet_management_view.gd").new();layer.add_child(pet_panel)
	pet_panel.configure_pets(world,pet_state);pet_panel.input_allowed=func():return allowed() and pet_open()
	pet_panel.cancelled.connect(_close_pet)
	pet_panel.tab_requested.connect(func(index):
		if allowed() and pet_state.phase!=pet_state.Phase.Applying:
			_close_pet();state.select_tab(index))
	pet_panel.information_requested.connect(func(caption):
		if allowed() and pet_state.phase!=pet_state.Phase.Applying:information_requested.emit(caption))
	host.register(self);_layout();_sync()
func allowed() -> bool:
	return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;state.open();opening=false;_sync()
func close_panel() -> void:state.close()
func job_open() -> bool:return job_state.phase!=job_state.Phase.Closed
func pet_open() -> bool:return pet_state.phase not in [pet_state.Phase.Closed,pet_state.Phase.Unavailable]
func _trainer(key: int) -> void:
	if not allowed() or job_open() or pet_open() or state.phase!=state.Phase.Ready or state.ticket!=0 or state.tab!=1:return
	pet_state.open_trainers(state.rows.get(key,{}))
func _close_pet() -> void:
	pet_state.close()
	if state.phase==state.Phase.Ready:state.refresh()
func _job(id: int) -> void:
	if not allowed() or job_open() or pet_open() or state.phase!=state.Phase.Ready or state.ticket!=0:return
	var target: Dictionary=state.rows.get(id,{}).get("job_target",{})
	if target.is_empty():return
	job_state.open(int(target.building_id),int(target.job_id),id);_sync()
func handle_back() -> void:
	if pet_open():_close_pet()
	elif job_open():job_panel.back()
	else:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if not opened and job_open():job_state.close()
	if not opened and pet_open():pet_state.close()
	if panel!=null:panel.visible=opened and not job_open() and not pet_open()
	if job_panel!=null:job_panel.visible=opened and job_open()
	if pet_panel!=null:
		var was_visible: bool=pet_panel.visible
		pet_panel.visible=opened and pet_open()
		if pet_panel.visible and not was_visible and layout_size.x>0:pet_panel.layout(layout_size/pet_panel.scale)
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
	if pet_panel!=null:pet_panel.scale=scale;pet_panel.layout(size/scale)
func _process(_delta: float) -> void:
	if panel!=null and (panel.visible or job_open() or pet_open()) and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:
	pet_state.dispose();job_state.dispose();state.dispose()
