extends Node
# Staged modal owner; no public route until rendered/native acceptance is complete.
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/hunter_ammunition_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
func _init() -> void:state.changed.connect(_sync)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/hunter_ammunition_view.gd").new();layer.add_child(panel)
	panel.configure_ammunition(world,state);panel.input_allowed=allowed
	host.register(self);_layout();_sync()
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;state.open();opening=false;_sync()
func close_panel() -> void:state.close()
func handle_back() -> void:state.back()
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
	panel.scale=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	layout_size=size;panel.layout(size/panel.scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose()
