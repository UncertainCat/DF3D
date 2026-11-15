extends "res://scripts/farm_panel.gd"
signal focus_requested(tile: Vector3i)
var goods=preload("res://scripts/depot_goods_state.gd").new()
var goods_view
var goods_mode:=false
var links=preload("res://scripts/building_links_state.gd").new()
var access=preload("res://scripts/door_controls_state.gd").new()
# Ordinary furniture uses native header and contained-item authority.
func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()
	contents.edit_removing=true
func _create_view():
	var view=preload("res://scripts/depot_sheet_view.gd").new()
	view.building_icon="" # Native artwork is authoritative; no Box fallback for other furniture.
	return view
func _open_state(id: int,_season: int) -> void:
	_retire_goods();state.open(id)
func _contents_supported() -> bool:return true
func configure(world,service,host,help=null) -> void:
	goods.configure(service)
	links.configure(service)
	access.configure(service)
	super.configure(world,service,host,help)
	goods_view=preload("res://scripts/depot_goods_view.gd").new();canvas.add_child(goods_view)
	goods_view.configure_goods(world,goods);goods_view.hover_help=help;goods_view.hide()
	goods_view.input_allowed=func():return goods_mode and play_enabled and ui_host.allows_panel_input(self)
	goods_view.cancelled.connect(_back_goods)
	panel.goods_requested.connect(_open_goods)
	panel.configure_links(world,links,help)
	panel.configure_access(world,access)
	access.applied.connect(contents.refresh)
	panel.links_view.recenter_requested.connect(func(tile):
		if panel.contents_allowed() and links.phase==links.Phase.Ready:
			close_panel();focus_requested.emit(tile))
func _state_changed() -> void:
	super._state_changed()
	if goods_mode:
		if state.building_id!=goods.depot_id or state.building_id<0:
			_retire_goods()
		else:panel.hide()
	if state.snapshot.get("type",-1) in [9,19,23,33,35,36,37,38,39,40,41,42,43,44,50]:
		if links.building_id!=state.building_id:links.open(state.building_id)
	elif links.building_id>=0:links.close()
	if state.snapshot.get("type",-1)==35 and not state.snapshot.get("removing",true):
		if access.building_id!=state.building_id:access.open(state.building_id)
	elif access.building_id>=0:access.close()
func _open_goods() -> void:
	if goods_mode or not play_enabled or not ui_host.allows_panel_input(self) or not panel.contents_allowed():return
	if state.snapshot.get("type",-1)!=6 or not state.snapshot.get("depot",{}).get("goods_available",false):return
	goods_mode=true;panel.finish_rename();panel.hide();cancel_gesture()
	goods_view._closing=false;goods_view.show();goods.open(state.building_id)
func _back_goods() -> void:
	if not goods_mode:return
	goods_mode=false;goods_view.hide()
	# A confirmed close refreshes awaiting counts from DF, never local guesses.
	if state.building_id>=0:state.refresh();contents.refresh();panel.show()
func _retire_goods() -> void:
	goods_mode=false
	if goods_view!=null:goods_view._closing=false;goods_view.hide()
	goods.close()
func handle_escape() -> void:
	if goods_mode:goods_view._finish()
	else:super.handle_escape()
func close_panel() -> void:
	_retire_goods()
	access.close();links.close();super.close_panel()
func _exit_tree() -> void:
	_retire_goods();goods.dispose();access.dispose();links.dispose();super._exit_tree()

func _process(delta: float) -> void:
	super._process(delta)
	if goods_view!=null:
		goods_view.layout(get_viewport().get_visible_rect().size/canvas.scale)
		if goods_mode:panel.hide()
	if panel!=null and panel.visible and play_enabled and contents.ticket==0:
		state.poll_refresh(delta)
		if state.phase==state.Phase.Ready and state.ticket==0 and state.name_session==null:
			contents.poll_refresh(delta)
			links.poll_refresh(delta)
