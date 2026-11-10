extends Node
signal information_requested(caption: String)
signal work_details_requested
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
var return_category:=0
var kitchen_state=preload("res://scripts/kitchen_state.gd").new()
var kitchen_panel
var kitchen_active:=false
var stone_state=preload("res://scripts/stone_use_state.gd").new()
var stone_panel
var stone_active:=false
var labor_handoff:=false
func current_state():return stone_state if stone_active else kitchen_state if kitchen_active else chores_state if chores_active else state
func _init() -> void:
	state.changed.connect(_sync);chores_state.changed.connect(_sync);chores_state.rows_changed.connect(_rows)
	kitchen_state.changed.connect(_sync);stone_state.changed.connect(_sync)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service);chores_state.configure(service);kitchen_state.configure(service);stone_state.configure(service)
	service.session_changed.connect(_reset_labor_navigation)
	world_source=world;action_service=service
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/standing_orders_view.gd").new();layer.add_child(panel)
	panel.configure_standing_orders(world,state);panel.input_allowed=allowed
	panel.hunter_ammunition_requested.connect(open_ammunition)
	panel.chores_requested.connect(open_chores)
	panel.work_details_requested.connect(request_work_details)
	panel.kitchen_requested.connect(open_kitchen);panel.stone_use_requested.connect(open_stone_use)
	chores_panel=preload("res://scripts/chores_view.gd").new();layer.add_child(chores_panel)
	chores_panel.configure_chores(world,chores_state);chores_panel.input_allowed=allowed
	chores_panel.category_requested.connect(open_category);chores_panel.cancelled.connect(close_panel)
	chores_panel.work_details_requested.connect(request_work_details)
	chores_panel.kitchen_requested.connect(open_kitchen);chores_panel.stone_use_requested.connect(open_stone_use)
	kitchen_panel=preload("res://scripts/kitchen_view.gd").new();layer.add_child(kitchen_panel)
	kitchen_panel.configure_kitchen(world,kitchen_state);kitchen_panel.input_allowed=allowed
	kitchen_panel.work_details_requested.connect(request_work_details);kitchen_panel.standing_requested.connect(return_standing)
	kitchen_panel.cancelled.connect(close_panel);kitchen_panel.stone_use_requested.connect(open_stone_use)
	stone_panel=preload("res://scripts/stone_use_view.gd").new();layer.add_child(stone_panel)
	stone_panel.configure_stone_use(world,stone_state);stone_panel.input_allowed=allowed
	stone_panel.work_details_requested.connect(request_work_details);stone_panel.standing_requested.connect(return_standing)
	stone_panel.kitchen_requested.connect(open_kitchen);stone_panel.cancelled.connect(close_panel)
	for information_view in [panel,chores_panel,kitchen_panel,stone_panel]:
		information_view.information_requested.connect(_request_information)
	panel.cancelled.connect(close_panel);host.register(self);_layout();_sync()
func open_stone_use() -> void:
	var current=current_state()
	if not allowed() or stone_active or current.phase==current.Phase.Applying:return
	if not kitchen_active and not stone_active:return_category=5 if chores_active else state.category
	opening=true;state.close();chores_state.close();kitchen_state.close(true)
	chores_active=false;kitchen_active=false;stone_active=true;stone_state.open(true);opening=false;_sync()
func open_kitchen() -> void:
	var current=current_state()
	if not allowed() or kitchen_active or current.phase==current.Phase.Applying:return
	if not stone_active:return_category=5 if chores_active else state.category
	opening=true;state.close();chores_state.close();stone_state.close(true);stone_active=false;chores_active=false;kitchen_active=true;kitchen_state.open(true);opening=false;_sync()
func return_standing() -> void:
	var current=current_state()
	if not allowed() or not (kitchen_active or stone_active) or current.phase==current.Phase.Applying:return
	opening=true;kitchen_state.close(true);stone_state.close(true);kitchen_active=false;stone_active=false;state.open()
	if return_category==5:state.close();chores_active=true;chores_state.open()
	elif return_category!=0:state.select_category(return_category)
	opening=false;_sync()
func open_chores() -> void:
	if not allowed() or kitchen_active or stone_active or chores_active or state.phase==state.Phase.Applying:return
	opening=true;state.close();chores_active=true;chores_state.open();opening=false;_sync()
func open_category(category: int) -> void:
	if not allowed() or not chores_active or chores_state.phase==chores_state.Phase.Applying or not state.COUNTS.has(category):return
	opening=true;chores_state.close();chores_active=false;state.open()
	if category!=0:state.select_category(category)
	opening=false;_sync()
func _rows() -> void:
	if chores_panel!=null:chores_panel.display_rows(chores_state.rows.values())
func allowed() -> bool:return play_enabled and ui_host!=null and ui_host.allows_panel_input(self)
func _reset_labor_navigation() -> void:return_category=0
func _request_information(caption: String) -> void:
	var current=current_state()
	if allowed() and current.phase!=current.Phase.Applying:information_requested.emit(caption)
func request_work_details() -> void:
	var current=current_state()
	if not allowed() or current.phase==current.Phase.Applying:return
	if not kitchen_active and not stone_active:return_category=5 if chores_active else state.category
	labor_handoff=true;work_details_requested.emit();labor_handoff=false
func open_from_labor(kitchen: bool=false,stone: bool=false) -> void:
	var saved_category:=return_category
	open_panel(true)
	if not allowed():return
	if stone:open_stone_use();return_category=saved_category
	elif kitchen:open_kitchen();return_category=saved_category
	elif return_category==5:open_chores()
	elif return_category!=0:state.select_category(return_category)
func open_ammunition() -> void:
	if not allowed() or state.phase!=state.Phase.Ready or state.category!=6:return
	if not is_instance_valid(ammunition_owner):
		ammunition_owner=preload("res://scripts/hunter_ammunition_panel.gd").new();add_child(ammunition_owner)
		ammunition_owner.configure(world_source,action_service,ui_host)
	ammunition_owner.open_panel()
func open_panel(retain_kitchen_navigation: bool=false) -> void:
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;chores_state.close();kitchen_state.close(retain_kitchen_navigation);stone_state.close(retain_kitchen_navigation);stone_active=false;kitchen_active=false;chores_active=false;state.open();opening=false;_sync()
func close_panel() -> void:
	opening=true;state.close();chores_state.close();kitchen_state.close(labor_handoff);stone_state.close(labor_handoff);opening=false;_sync()
func handle_back() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	var current=current_state()
	var opened: bool=current.phase not in [current.Phase.Closed,current.Phase.Unavailable]
	if panel!=null:panel.visible=opened and not chores_active and not kitchen_active and not stone_active
	if kitchen_panel!=null:kitchen_panel.visible=opened and kitchen_active
	if stone_panel!=null:stone_panel.visible=opened and stone_active
	if chores_panel!=null:
		chores_panel.visible=opened and chores_active
		if opened and chores_active and chores_state.phase==chores_state.Phase.Ready:chores_state.seek_children(chores_state.child_first,chores_panel.capacity())
	if not opened and not opening and ui_host!=null:ui_host.release(self)
func _layout() -> void:
	if panel==null:return
	var size:=get_viewport().get_visible_rect().size
	panel.scale=preload("res://scripts/presentation_settings.gd").effective_scale_vector(size)
	layout_size=size;panel.layout(size/panel.scale)
	if kitchen_panel!=null:kitchen_panel.scale=panel.scale;kitchen_panel.layout(size/panel.scale)
	if stone_panel!=null:stone_panel.scale=panel.scale;stone_panel.layout(size/panel.scale)
	if chores_panel!=null:
		chores_panel.scale=panel.scale;chores_panel.layout(size/panel.scale)
		if chores_active and chores_state.phase==chores_state.Phase.Ready:chores_state.seek_children(chores_state.child_first,chores_panel.capacity())
func _process(_delta: float) -> void:
	if panel!=null and (panel.visible or (chores_panel!=null and chores_panel.visible) or (kitchen_panel!=null and kitchen_panel.visible) or (stone_panel!=null and stone_panel.visible)) and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:state.dispose();chores_state.dispose();kitchen_state.dispose();stone_state.dispose()
