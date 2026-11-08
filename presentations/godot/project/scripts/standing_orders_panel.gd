extends Node
# Staged owner, pending all categories and native interaction acceptance.
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/standing_orders_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
var ammunition_owner
var world_source
var action_service
func _init() -> void:state.changed.connect(_sync)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service)
	world_source=world;action_service=service
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/standing_orders_view.gd").new();layer.add_child(panel)
	panel.configure_standing_orders(world,state);panel.input_allowed=allowed
	panel.hunter_ammunition_requested.connect(open_ammunition)
	panel.cancelled.connect(close_panel);host.register(self);_layout();_sync()
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_ammunition() -> void:
	if not allowed() or state.phase!=state.Phase.Ready or state.category!=6:return
	if not is_instance_valid(ammunition_owner):
		ammunition_owner=preload("res://scripts/hunter_ammunition_panel.gd").new();add_child(ammunition_owner)
		ammunition_owner.configure(world_source,action_service,ui_host)
	ammunition_owner.open_panel()
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
	panel.scale=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	layout_size=size;panel.layout(size/panel.scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose()
