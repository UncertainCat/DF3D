extends "res://scripts/farm_panel.gd"
signal focus_requested(tile: Vector3i)
signal selection_retired
var goods=preload("res://scripts/depot_goods_state.gd").new()
var goods_view
var goods_mode:=false
var trade=preload("res://scripts/trade_goods_state.gd").new()
var trade_view
var trade_mode:=false
var links=preload("res://scripts/building_links_state.gd").new()
var access=preload("res://scripts/door_controls_state.gd").new()
var cage=preload("res://scripts/cage_picker_state.gd").new()
var cage_occupants=preload("res://scripts/cage_picker_state.gd").new()
var cage_view
var cage_mode:=false
# Ordinary furniture uses native header and contained-item authority.
func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()
	contents.edit_removing=true
func _create_view():
	var view=preload("res://scripts/cage_sheet_view.gd").new()
	view.building_icon="" # Native artwork is authoritative; no Box fallback for other furniture.
	return view
func _open_state(id: int,_season: int) -> void:
	_retire_cage();cage_occupants.close();_retire_goods();_retire_trade();state.open(id)
func _contents_supported() -> bool:return true
func configure(world,service,host,help=null) -> void:
	goods.configure(service)
	trade.configure(service)
	links.configure(service)
	access.configure(service)
	cage.configure(service)
	cage_occupants.configure(service,true)
	super.configure(world,service,host,help)
	panel.configure_occupants(cage_occupants)
	cage_view=preload("res://scripts/area_candidates_view.gd").new();cage_view.cage_layout=true
	canvas.add_child(cage_view);cage_view.native_help=help;cage_view.configure(world,cage)
	cage_view.add_theme_stylebox_override("panel",cage_view.panel_style());cage_view.hide()
	panel.cage_requested.connect(_open_cage)
	cage.applied.connect(contents.refresh)
	cage.applied.connect(func():
		if state.snapshot.get("type",-1)==28:cage_occupants.open(state.building_id))
	cage_occupants.applied.connect(func():
		contents.refresh()
		if cage_mode:cage.open(state.building_id))
	goods_view=preload("res://scripts/depot_goods_view.gd").new();canvas.add_child(goods_view)
	goods_view.configure_goods(world,goods);goods_view.hover_help=help;goods_view.hide()
	goods_view.input_allowed=func():return goods_mode and play_enabled and ui_host.allows_panel_input(self)
	goods_view.cancelled.connect(_back_goods)
	panel.goods_requested.connect(_open_goods)
	trade_view=preload("res://scripts/trade_view.gd").new();canvas.add_child(trade_view)
	trade_view.configure_trade(world,trade);trade_view.hide()
	trade_view.input_allowed=func():return trade_mode and play_enabled and ui_host.allows_panel_input(self)
	trade_view.cancelled.connect(close_panel)
	panel.trade_requested.connect(_open_trade)
	panel.configure_links(world,links,help)
	panel.configure_access(world,access)
	access.applied.connect(contents.refresh)
	panel.links_view.recenter_requested.connect(func(tile):
		if panel.contents_allowed() and links.phase==links.Phase.Ready:
			close_panel();focus_requested.emit(tile))
func _state_changed() -> void:
	super._state_changed()
	if state.snapshot.get("type",-1)==28 and not state.snapshot.get("removing",true):
		if cage_occupants.building_id!=state.building_id or (cage_occupants.phase==cage_occupants.Phase.Ready and cage_occupants.snapshot.get("justice_restraint")!=state.snapshot.cage.justice_restraint):cage_occupants.open(state.building_id)
	elif cage_occupants.building_id>=0:cage_occupants.close()
	if cage_mode and (state.building_id!=cage.building_id or state.snapshot.get("removing",false) or state.snapshot.get("cage",{}).get("justice_restraint",false)):_retire_cage()
	if goods_mode:
		if state.building_id!=goods.depot_id or state.building_id<0:
			_retire_goods()
		else:panel.hide()
	if trade_mode:
		if state.building_id!=trade.depot_id or state.building_id<0:
			_retire_trade()
		else:panel.hide()
	if state.snapshot.get("type",-1) in [9,19,23,33,35,36,37,38,39,40,41,42,43,44,50]:
		if links.building_id!=state.building_id:links.open(state.building_id)
	elif links.building_id>=0:links.close()
	if state.snapshot.get("type",-1)==35 and not state.snapshot.get("removing",true):
		if access.building_id!=state.building_id:access.open(state.building_id)
	elif access.building_id>=0:access.close()
func _open_goods() -> void:
	if goods_mode or trade_mode or not play_enabled or not ui_host.allows_panel_input(self) or not panel.contents_allowed():return
	if state.snapshot.get("type",-1)!=6 or not state.snapshot.get("depot",{}).get("goods_available",false):return
	goods_mode=true;panel.finish_rename();panel.hide();cancel_gesture()
	selection_retired.emit()
	goods_view._closing=false;goods_view.show();goods.open(state.building_id)
func _open_trade() -> void:
	if goods_mode or trade_mode or not play_enabled or not ui_host.allows_panel_input(self) or not panel.contents_allowed():return
	var depot: Dictionary=state.snapshot.get("depot",{})
	if state.snapshot.get("type",-1)!=6 or not depot.get("trade_available",false) or depot.get("worker_id",-1)<0:return
	trade_mode=true;panel.finish_rename();panel.hide();cancel_gesture()
	selection_retired.emit()
	trade_view.show();trade.open(state.building_id)
func _retire_trade() -> void:
	trade_mode=false
	if trade_view!=null:trade_view.hide()
	trade.close()
func _back_goods() -> void:
	if not goods_mode:return
	# Native Escape commits the picker and also clears its parent selection.
	close_panel()
func _retire_goods() -> void:
	goods_mode=false
	if goods_view!=null:goods_view._closing=false;goods_view.hide()
	goods.close()
func _open_cage() -> void:
	if cage_mode or not play_enabled or not ui_host.allows_panel_input(self) or not panel.contents_allowed() or state.snapshot.get("type",-1)!=28 or state.snapshot.get("removing",true) or state.snapshot.get("cage",{}).get("justice_restraint",true):return
	panel.finish_rename();cancel_gesture();cage_mode=true;cage_view.show();cage.open(state.building_id)
func _retire_cage() -> void:
	cage_mode=false
	if cage_view!=null:cage_view.hide()
	cage.close()
func handle_escape() -> void:
	if cage_mode:_retire_cage()
	elif goods_mode:goods_view._finish()
	else:super.handle_escape()
func _input(event: InputEvent) -> void:
	if cage_mode and play_enabled and ui_host.allows_panel_input(self):cage_view.owner_pointer(event)
	if cage_mode and play_enabled and ui_host.allows_panel_input(self) and event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:
			_retire_cage();get_viewport().set_input_as_handled();return
		if cage_view.feed_owner_key(event):get_viewport().set_input_as_handled();return
	super._input(event)
func close_panel() -> void:
	# Native Trade and chooser cancellation also clear the depot selection.
	_retire_cage();_retire_goods();_retire_trade()
	cage_occupants.close();access.close();links.close();super.close_panel()
func _exit_tree() -> void:
	_retire_cage();cage.dispose();cage_occupants.dispose();_retire_goods();_retire_trade();trade.dispose();goods.dispose();access.dispose();links.dispose();super._exit_tree()

func _process(delta: float) -> void:
	super._process(delta)
	if cage_mode:
		cage_view.visible=play_enabled and ui_host.allows_panel_input(self)
		cage.tick(delta);cage_view.layout(get_viewport().get_visible_rect().size/canvas.scale)
		# Recipes are snapshot-owned; load only the visible portraits.
		var first: int=cage_view.owner_scrollbar.first
		for index in range(first,mini(cage_view.portrait_slots.size(),first+cage_view.page_rows())):
			var slot: Dictionary=cage_view.portrait_slots[index]
			if not slot.loaded:slot.view.texture=cage_view.world.candidate_icon(slot.recipe);slot.loaded=true
	if goods_view!=null:
		goods_view.layout(get_viewport().get_visible_rect().size/canvas.scale)
		if goods_mode:panel.hide()
	if trade_view!=null:
		trade_view.layout(get_viewport().get_visible_rect().size/canvas.scale)
		if trade_mode:panel.hide()
	if panel!=null and panel.visible and play_enabled and contents.ticket==0:
		state.poll_refresh(delta)
		if state.phase==state.Phase.Ready and state.ticket==0 and state.name_session==null:
			contents.poll_refresh(delta)
			links.poll_refresh(delta)
			if not cage_mode:cage_occupants.poll_refresh(delta)
