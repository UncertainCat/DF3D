extends Control
signal choose_requested
# Native renderer1882fe/189a22 and protected workshop-work-orders reference.
# Order creation and row details are still staged.
var art=preload("res://scripts/original_ui.gd").new()
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var editing:=false
var draft:=""
var cursor_visible:=true
func configure(source,model) -> void:
	state=model;art.configure(source);theme=art.theme;colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(func():
		if state.phase not in [state.Phase.Ready,state.Phase.Applying]:editing=false
		queue_redraw())
func finish_entry() -> void:editing=false;queue_redraw()
func feed_key(event: InputEventKey) -> void:
	if not editing or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:finish_entry();return
	var before:=draft
	if event.keycode==KEY_BACKSPACE:draft=draft.left(maxi(0,draft.length()-1))
	elif draft.length()<2 and ((event.unicode>=48 and event.unicode<=57) or (event.unicode>=65 and event.unicode<=90)):
		# Native c39700 flags4 also accepts uppercase ASCII; preserve its filter.
		draft+=String.chr(event.unicode)
	if before!=draft:
		var value:=0
		for index in draft.length():
			var digit:=draft.unicode_at(index)-48
			if digit<0 or digit>9:break
			value=value*10+digit
		state.set_limit(value)
	queue_redraw()
func _process(_delta: float) -> void:
	if not is_visible_in_tree():editing=false;return
	if editing:
		var phase:=Time.get_ticks_msec()%1000<500
		if phase!=cursor_visible:cursor_visible=phase;queue_redraw()
func button_rect(index: int) -> Rect2:return Rect2(360+index*32,size.y-36,32,36)
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready:return
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	if state.snapshot.get("manager_available",false) and Rect2(424,0,32,36).has_point(event.position):finish_entry();choose_requested.emit();accept_event();return
	if button_rect(0).has_point(event.position):editing=true;draft="";queue_redraw();accept_event();return
	for index in [1,2]:
		if button_rect(index).has_point(event.position):finish_entry();state.step(1 if index==1 else -1);accept_event();return
func caption(value: String,point: Vector2,color: Color) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
func _draw() -> void:
	if state==null or state.snapshot.is_empty():return
	if not state.snapshot.manager_available:
		caption("A manager is required to add work orders to the shop.",Vector2(0,22),colors[12] if colors.size()>12 else Color.WHITE)
	else:
		caption("Work orders can be added specifically for this shop.",Vector2(0,22),Color.WHITE)
		var add: Texture2D=art.texture("WORK_ORDERS_CREATE_NEW")
		if add!=null:draw_texture_rect(add,Rect2(424,0,32,36),false)
	caption("General work orders allowed: "+(draft+("_" if cursor_visible else "") if editing else str(state.snapshot.general_order_limit)),Vector2(0,size.y-14),Color.WHITE)
	for index in 3:
		var texture: Texture2D=art.texture(["WORK_ORDERS_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"][index])
		if texture!=null:draw_texture_rect(texture,button_rect(index),false)
