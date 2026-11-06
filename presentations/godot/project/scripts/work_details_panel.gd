extends Node
# Staged owner; settings/name editing and full native acceptance precede exposure.
signal settings_requested
signal rename_requested
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/work_details_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
var name_session
var name_generation: int=-1
var pending_name_action: Dictionary={}
var closing:=false
var pending_name_first: int=-1
func _init() -> void:state.changed.connect(_sync)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/work_details_view.gd").new();layer.add_child(panel)
	panel.configure_work_details(world,state);panel.input_allowed=allowed
	panel.cancelled.connect(close_panel)
	panel.settings_requested.connect(state.open_settings)
	panel.reset_requested.connect(state.reset_settings)
	panel.delete_requested.connect(state.delete_detail)
	panel.rename_requested.connect(_begin_name)
	panel.name_edited.connect(_name_edited)
	panel.name_finished.connect(_finish_name)
	host.register(self);_layout();_sync()
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if is_instance_valid(name_session) and not name_session.stopped:return
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;state.open();opening=false;_sync()
func close_panel() -> void:
	closing=true;pending_name_action={};pending_name_first=-1;_finish_name({});state.close()
	if panel!=null:panel.clear_name()
	closing=false
func _begin_name() -> void:
	if not state.can_edit() or is_instance_valid(name_session):return
	name_generation=state.generation;state.phase=state.Phase.Applying
	name_session=preload("res://scripts/work_detail_name_session.gd").new();state.service.add_child(name_session)
	name_session.changed.connect(_name_changed);name_session.finished.connect(_name_done);name_session.failed.connect(_name_failed)
	name_session.configure(state.service,state.selected);panel.begin_name();state.changed.emit()
func _name_edited(value: String) -> void:
	if is_instance_valid(name_session):name_session.edit(value)
func _finish_name(action: Dictionary) -> void:
	if not is_instance_valid(name_session):return
	pending_name_action=action.duplicate(true);panel.finish_name();name_session.finish()
func _name_changed(observed: Dictionary) -> void:
	if state.generation!=name_generation or closing:return
	state.selected=observed.duplicate(true);state.details[int(observed.index)]=observed.duplicate(true);panel.queue_redraw()
func _name_done() -> void:
	name_session=null
	if closing or state.generation!=name_generation:return
	pending_name_first=state.first;panel.clear_name();state._reload(int(state.selected.index))
func _name_failed(result: Dictionary) -> void:
	name_session=null;pending_name_action={}
	if closing or state.generation!=name_generation:return
	panel.clear_name();state._reject(result)
func _dispatch_name_action(action: Dictionary,generation: int) -> void:
	if state.generation==generation and state.phase==state.Phase.Ready and allowed():panel.dispatch_action(action)

func handle_back() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	if state.phase==state.Phase.Ready and pending_name_first>=0:
		var first:=pending_name_first;pending_name_first=-1;state.seek(first,state.capacity);return
	if state.phase==state.Phase.Ready and not pending_name_action.is_empty():
		var action:=pending_name_action;pending_name_action={};_dispatch_name_action.call_deferred(action,state.generation)
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if panel!=null:
		panel.visible=opened
		if not opened:panel.clear_name();pending_name_action={};pending_name_first=-1
	if not opened and not opening and ui_host!=null:ui_host.release(self)
func _layout() -> void:
	if panel==null:return
	var size:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	panel.scale=scale;layout_size=size;panel.layout(size/scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:
	closing=true
	if is_instance_valid(name_session):
		name_session.changed.disconnect(_name_changed);name_session.finished.disconnect(_name_done);name_session.failed.disconnect(_name_failed)
		name_session.finish()
	state.dispose()
