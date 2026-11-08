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
var chores_state=preload("res://scripts/chores_state.gd").new()
var chores_panel
var chores_active:=false
func _init() -> void:
	state.changed.connect(_sync);chores_state.changed.connect(_sync);chores_state.rows_changed.connect(_rows)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service);chores_state.configure(service)
	world_source=world;action_service=service
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/standing_orders_view.gd").new();layer.add_child(panel)
	panel.configure_standing_orders(world,state);panel.input_allowed=allowed
	panel.hunter_ammunition_requested.connect(open_ammunition)
	panel.chores_requested.connect(open_chores)
	chores_panel=preload("res://scripts/chores_view.gd").new();layer.add_child(chores_panel)
	chores_panel.configure_chores(world,chores_state);chores_panel.input_allowed=allowed
	chores_panel.category_requested.connect(open_category);chores_panel.cancelled.connect(close_panel)
	panel.cancelled.connect(close_panel);host.register(self);_layout();_sync()
func open_chores() -> void:
	if not allowed() or chores_active or state.phase==state.Phase.Applying:return
	opening=true;state.close();chores_active=true;chores_state.open();opening=false;_sync()
func open_category(category: int) -> void:
	if not allowed() or not chores_active or chores_state.phase==chores_state.Phase.Applying or not state.COUNTS.has(category):return
	opening=true;chores_state.close();chores_active=false;state.open()
	if category!=0:state.select_category(category)
	opening=false;_sync()
func _rows() -> void:
	if chores_panel!=null:chores_panel.display_rows(chores_state.rows.values())
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func open_ammunition() -> void:
	if not allowed() or state.phase!=state.Phase.Ready or state.category!=6:return
	if not is_instance_valid(ammunition_owner):
		ammunition_owner=preload("res://scripts/hunter_ammunition_panel.gd").new();add_child(ammunition_owner)
		ammunition_owner.configure(world_source,action_service,ui_host)
	ammunition_owner.open_panel()
func open_panel() -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;chores_state.close();chores_active=false;state.open();opening=false;_sync()
func close_panel() -> void:
	opening=true;state.close();chores_state.close();opening=false;_sync()
func handle_back() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	var current=chores_state if chores_active else state
	var opened: bool=current.phase not in [current.Phase.Closed,current.Phase.Unavailable]
	if panel!=null:panel.visible=opened and not chores_active
	if chores_panel!=null:
		chores_panel.visible=opened and chores_active
		if opened and chores_active and chores_state.phase==chores_state.Phase.Ready:chores_state.seek_children(chores_state.child_first,chores_panel.capacity())
	if not opened and not opening and ui_host!=null:ui_host.release(self)
func _layout() -> void:
	if panel==null:return
	var size:=get_viewport().get_visible_rect().size
	panel.scale=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	layout_size=size;panel.layout(size/panel.scale)
	if chores_panel!=null:
		chores_panel.scale=panel.scale;chores_panel.layout(size/panel.scale)
		if chores_active and chores_state.phase==chores_state.Phase.Ready:chores_state.seek_children(chores_state.child_first,chores_panel.capacity())
func _process(_delta: float) -> void:
	if panel!=null and (panel.visible or (chores_panel!=null and chores_panel.visible)) and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose();chores_state.dispose()
