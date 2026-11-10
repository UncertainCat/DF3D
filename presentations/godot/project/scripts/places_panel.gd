extends Node
# Staged owner; public Places entry stays gated while controls are incomplete.
signal focus_requested(tile: Vector3i)
signal inspect_requested(tab: int,building_id: int,tile: Vector3i)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/places_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
var destination: Dictionary={}
func _init() -> void:state.changed.connect(_sync)
func configure(world,service,host,hover=null) -> void:
	ui_host=host;state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/places_view.gd").new();layer.add_child(panel)
	panel.configure_places(world,state);panel.input_allowed=allowed;panel.hover_help=hover
	panel.cancelled.connect(close_panel);panel.navigation_requested.connect(_navigate)
	panel.siege_requested.connect(func(id,action):
		if allowed():state.apply(id,action))
	host.register(self);_layout();_sync()
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;destination={};state.open();opening=false;_sync()
func close_panel() -> void:destination={};state.close()
func handle_back() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _navigate(row: Dictionary,inspect: bool) -> void:
	if not allowed() or state.phase!=state.Phase.Ready:return
	if not state.rows.any(func(current):return current.building_id==row.get("building_id")):return
	# A fresh owned read revalidates membership and position before either
	# camera navigation or inspection. Never invoke native menu handlers.
	destination={"tab":state.tab,"id":row.building_id,"inspect":inspect};state.refresh()
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if panel!=null:panel.visible=opened
	if not opened and not opening and ui_host!=null:ui_host.release(self)
	if destination.is_empty():return
	if state.tab!=destination.tab or state.phase in [state.Phase.Closed,state.Phase.Unavailable,state.Phase.Rejected]:destination={};return
	if state.phase!=state.Phase.Ready:return
	var target:=destination;destination={}
	for row in state.rows:
		if row.building_id!=target.id:continue
		if allowed() and row.has("position"):
			var tile: Vector3i=row.position;close_panel()
			if target.inspect:inspect_requested.emit(target.tab,target.id,tile)
			else:focus_requested.emit(tile)
		return
func _layout() -> void:
	if panel==null:return
	var extent:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(extent)
	panel.scale=scale;layout_size=extent;panel.layout(extent/scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose()
