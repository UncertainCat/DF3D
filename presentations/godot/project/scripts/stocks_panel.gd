extends Node
# Public Stocks owner. Native View/Recenter leave Stocks without a return route.
signal focus_requested(tile: Vector3i)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var item_owner
var state=preload("res://scripts/stocks_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
func _init() -> void:
	state.changed.connect(_sync)
	state.destination_ready.connect(_destination)
func configure(world,service,host,help=null) -> void:
	ui_host=host;state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/stocks_view.gd").new();layer.add_child(panel)
	panel.configure_stocks(world,state,help);panel.input_allowed=allowed
	panel.cancelled.connect(close_panel)
	panel.recenter_requested.connect(func(id):if allowed():state.navigate(id,false))
	panel.item_requested.connect(func(id):if allowed():state.navigate(id,true))
	item_owner=preload("res://scripts/item_panel.gd").new();add_child(item_owner)
	item_owner.configure(world,service,host,help)
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
func _destination(tile: Vector3i,id: int,inspect: bool) -> void:
	if not allowed() or state.phase!=state.Phase.Navigating:return
	close_panel();focus_requested.emit(tile)
	if inspect and is_instance_valid(item_owner):item_owner.open_target(id)
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if panel!=null:panel.visible=opened
	if not opened and not opening and ui_host!=null:ui_host.release(self)
func _layout() -> void:
	if panel==null:return
	var extent:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(extent)
	panel.scale=scale;layout_size=extent;panel.layout(extent/scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose()
