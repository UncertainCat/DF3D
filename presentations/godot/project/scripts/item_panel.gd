extends Node
# Staged farm item owner. General item types remain unfinished.
signal stockpile_requested(stockpile_id: int)
signal holder_requested(building_id: int)
signal carrier_requested(kind: int, id: int)
const Preferences=preload("res://scripts/presentation_settings.gd")
const C=preload("res://scripts/management_contract.gd")
const OPERATIONS={"forbid":C.FarmOperation.ItemForbid,"dump":C.FarmOperation.ItemDump,"melt":C.FarmOperation.ItemMelt,"hidden":C.FarmOperation.ItemHidden}
var state=preload("res://scripts/item_sheet_state.gd").new()
var ui_host
var panel
var follow
var canvas: CanvasLayer
var play_enabled:=true
var modal_input:=false
var right_down:=false
var right_travel:=0.0

func configure(world,service,host,help=null) -> void:
	ui_host=host;state.configure(service)
	canvas=CanvasLayer.new();canvas.layer=5;add_child(canvas)
	panel=preload("res://scripts/item_sheet_view.gd").new();canvas.add_child(panel);panel.configure(world,help);panel.hide()
	panel.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self)
	panel.flag_requested.connect(func(id,flag,value):
		if id==state.item_id and OPERATIONS.has(flag):state.set_flag(OPERATIONS[flag],value))
	panel.holder_requested.connect(func(id):
		if state.phase==state.Phase.Ready and state.snapshot.get("holder",{}).get("id",-1)==id:holder_requested.emit(id))
	panel.stockpile_requested.connect(func(id):
		if state.phase==state.Phase.Ready and state.snapshot.get("stockpile",{}).get("id",-1)==id:stockpile_requested.emit(id))
	panel.carrier_requested.connect(func(kind,id):
		var carrier: Dictionary=state.snapshot.get("carrier",{})
		if state.phase==state.Phase.Ready and carrier.get("kind",0)==kind and carrier.get("id",-1)==id:
			if kind==1:open_target(id)
			else:carrier_requested.emit(kind,id))
	panel.contents_view.child_requested.connect(func(kind,id):
		if kind==1 and play_enabled and ui_host.allows_panel_input(self):state.open_child(id))
	panel.contents_view.child_flag_requested.connect(func(id,operation,value):
		if play_enabled and ui_host.allows_panel_input(self) and operation>=0 and operation<4:
			state.set_flag([C.FarmOperation.ItemForbid,C.FarmOperation.ItemDump,C.FarmOperation.ItemMelt,C.FarmOperation.ItemHidden][operation],value,id))
	state.changed.connect(_state_changed)
	ui_host.register(self);_process(0)

func open_target(item: int) -> void:
	if not play_enabled or not ui_host.activate(self):return
	state.open(item)

func configure_follow(source) -> void:
	follow=source;follow.changed.connect(_follow_changed)
	panel.camera_requested.connect(func(id):
		if state.phase==state.Phase.Ready and id==state.item_id:follow.toggle(id))
	_follow_changed()

func _follow_changed() -> void:
	panel.set_following(is_instance_valid(follow) and state.item_id>=0 and follow.item_id==state.item_id)

func _state_changed() -> void:
	var value: Dictionary=state.view_snapshot()
	if value.has("holder"):
		value.holder_id=value.holder.id
		value.holder_name=("On " if value.holder.type==2 else "In ")+value.holder.name

	panel.pending=state.phase!=state.Phase.Ready
	panel.present(value)
	_follow_changed()
	if state.item_id<0 or (value.is_empty() and state.phase not in [state.Phase.Reading,state.Phase.Applying]):_release_if_closed.call_deferred()

func _release_if_closed() -> void:
	if state.item_id<0 or (state.snapshot.is_empty() and state.phase not in [state.Phase.Reading,state.Phase.Applying]):ui_host.release(self);cancel_gesture()

func close_panel() -> void:
	state.close();panel.hide();ui_host.release(self);cancel_gesture()

func handle_escape() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value and panel!=null:close_panel()
func cancel_gesture() -> void:right_down=false;right_travel=0

func _process(delta: float) -> void:
	if panel==null:return
	if play_enabled:state.poll(delta)
	var viewport:=get_viewport().get_visible_rect().size
	var factor:=Preferences.effective_scale_vector(viewport)
	canvas.scale=factor
	var view:=viewport/factor
	panel.position=Vector2((floori(view.x/8)-98)*8,48+fposmod(view.y,12)*0.5)
	panel.size=Vector2(488,floori(view.y/12)*12-84)

func _input(event: InputEvent) -> void:
	if panel==null or not ui_host.allows_panel_input(self):return
	if event is InputEventMouseMotion and right_down:right_travel+=event.relative.length()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed:right_down=true;right_travel=0
		else:
			var click:=right_down and right_travel<4;right_down=false
			if click:close_panel();get_viewport().set_input_as_handled()

func _exit_tree() -> void:state.dispose()
