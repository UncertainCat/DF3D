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
func _init() -> void:state.changed.connect(_sync)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/work_details_view.gd").new();layer.add_child(panel)
	panel.configure_work_details(world,state);panel.input_allowed=allowed
	panel.cancelled.connect(close_panel)
	panel.settings_requested.connect(func():settings_requested.emit())
	panel.rename_requested.connect(func():rename_requested.emit())
	host.register(self);_layout();_sync()
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;state.open();opening=false;_sync()
func close_panel() -> void:state.close()
func handle_back() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if panel!=null:panel.visible=opened
	if not opened and not opening and ui_host!=null:ui_host.release(self)
func _layout() -> void:
	if panel==null:return
	var size:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	panel.scale=scale;layout_size=size;panel.layout(size/scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose()
