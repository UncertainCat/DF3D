extends Control
signal choose_requested
signal conditions_requested(id: int)
signal details_requested(id: int)
# Native renderer1882fe/189a22 and protected workshop-work-orders reference.
# Row actions and details are still staged.
var art=preload("res://scripts/original_ui.gd").new()
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var editing:=false
var quantity_order: int=-1
var draft:=""
var cursor_visible:=true
var visible_rows:=0
var hover_help
var pointer_known:=false
var pointer_global:=Vector2.ZERO
func configure(source,model,help=null) -> void:
	hover_help=help
	state=model;art.configure(source);theme=art.theme;colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_exited.connect(leave_hover)
	visibility_changed.connect(func():
		if not is_visible_in_tree():leave_hover())
	state.changed.connect(func():
		if state.phase not in [state.Phase.Ready,state.Phase.Applying]:editing=false
		queue_redraw())
func finish_entry() -> void:editing=false;quantity_order=-1;queue_redraw()
func feed_key(event: InputEventKey) -> void:
	if not editing or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:finish_entry();return
	var before:=draft
	if event.keycode==KEY_BACKSPACE:draft=draft.left(maxi(0,draft.length()-1))
	elif draft.length()<(4 if quantity_order>=0 else 2) and ((event.unicode>=48 and event.unicode<=57) or (event.unicode>=65 and event.unicode<=90)):
		# Native c39700 flags4 also accepts uppercase ASCII; preserve its filter.
		draft+=String.chr(event.unicode)
	if before!=draft:
		var value:=0
		for index in draft.length():
			var digit:=draft.unicode_at(index)-48
			if digit<0 or digit>9:break
			value=value*10+digit
		if quantity_order>=0:state.set_quantity(quantity_order,value)
		else:state.set_limit(value)
	queue_redraw()
func _process(_delta: float) -> void:
	update_hover()
	if not is_visible_in_tree():editing=false;return
	var capacity:=maxi(0,int((size.y-72)/36))
	if visible_rows!=capacity:
		visible_rows=capacity;state.seek_rows(state.row_offset,capacity)
	if editing:
		var phase:=Time.get_ticks_msec()%1000<500
		if phase!=cursor_visible:cursor_visible=phase;queue_redraw()
func button_rect(index: int) -> Rect2:return Rect2(360+index*32,size.y-36,32,36)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer_known=true;pointer_global=get_global_transform()*event.position;update_hover()
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready:return
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		finish_entry();state.seek_rows(state.row_offset+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),visible_rows);accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if state.snapshot.get("manager_available",false) and Rect2(424,0,32,36).has_point(event.position):finish_entry();choose_requested.emit();accept_event();return
	for index in visible_rows:
		var row: Dictionary=state.rows.get(state.row_offset+index,{})
		if not row.is_empty() and row.get("native_state",{}).get("details_available",false) and Rect2(392,36+index*36,32,36).has_point(event.position):
			finish_entry();details_requested.emit(row.id);accept_event();return
		if not row.is_empty() and Rect2(360,36+index*36,32,36).has_point(event.position):
			finish_entry();conditions_requested.emit(row.id);accept_event();return
		if not row.is_empty() and Rect2(424,36+index*36,32,36).has_point(event.position):
			finish_entry();state.remove_order(row.id);accept_event();return
		if not row.is_empty() and Rect2(328,36+index*36,32,36).has_point(event.position):
			quantity_order=row.id;editing=true;draft="";queue_redraw();accept_event();return
	if button_rect(0).has_point(event.position):quantity_order=-1;editing=true;draft="";queue_redraw();accept_event();return
	for index in [1,2]:
		if button_rect(index).has_point(event.position):finish_entry();state.step(1 if index==1 else -1);accept_event();return
func update_hover() -> void:
	if not is_instance_valid(hover_help):return
	if pointer_known and is_visible_in_tree() and state!=null and state.phase==state.Phase.Ready and state.snapshot.get("manager_available",false) and (not input_allowed.is_valid() or input_allowed.call()) and Rect2(424,0,32,36).has_point(get_global_transform().affine_inverse()*pointer_global):
		hover_help.enter_work_order(get_instance_id(),"workshop_new")
	else:hover_help.leave(get_instance_id())
func leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
func _exit_tree() -> void:
	leave_hover()
func caption(value: String,point: Vector2,color: Color) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
func _draw() -> void:
	if state==null or state.snapshot.is_empty():return
	if not state.snapshot.manager_available:
		caption("A manager is required to add work orders to the shop.",Vector2(0,24),colors[12] if colors.size()>12 else Color.WHITE)
	else:
		caption("Work orders can be added specifically for this shop.",Vector2(0,24),Color.WHITE)
		var add: Texture2D=art.texture("WORK_ORDERS_CREATE_NEW")
		if add!=null:draw_texture_rect(add,Rect2(424,0,32,36),false)
	for index in visible_rows:
		var row: Dictionary=state.rows.get(state.row_offset+index,{})
		if row.is_empty():continue
		var native: Dictionary=row.native_state
		var y:=36+index*36
		row_background(y)
		var phases: Array=["","WORK_ORDERS_ACTIVE","WORK_ORDERS_WAITING","WORK_ORDERS_CHECKING","WORK_ORDERS_READY"]
		row_icon(phases[native.phase],Vector2(0,y))
		var name: String=row.name
		if name.length()>=29:name=name.left(25)+"..."
		var cyan: Color=colors[11] if colors.size()>11 else Color.WHITE
		caption(name,Vector2(48,y+22),cyan)
		var quantity: String="∞/∞" if row.total==0 else str(row.remaining)+"/"+str(row.total)
		if editing and quantity_order==row.id:quantity=draft+("_" if cursor_visible else "")
		caption(quantity,Vector2(48,y+34),cyan)
		if native.validation_required:row_icon("WORK_ORDERS_VALIDATED" if row.validated else "WORK_ORDERS_NOT_VALIDATED",Vector2(296,y))
		row_icon("WORK_ORDERS_ENTER_AMOUNT",Vector2(328,y))
		row_icon("WORK_ORDERS_CONDITIONS",Vector2(360,y))
		if native.details_available:row_icon("WORK_ORDERS_DETAILS",Vector2(392,y))
		row_icon("WORK_ORDERS_REMOVE",Vector2(424,y))
	caption("General work orders allowed: "+(draft+("_" if cursor_visible else "") if editing and quantity_order<0 else str(state.snapshot.general_order_limit)),Vector2(0,size.y-12),Color.WHITE)
	for index in 3:
		var texture: Texture2D=art.texture(["WORK_ORDERS_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"][index])
		if texture!=null:draw_texture_rect(texture,button_rect(index),false)

func row_icon(token: String,point: Vector2) -> void:
	var texture: Texture2D=art.texture(token)
	if texture!=null:draw_texture_rect(texture,Rect2(point,Vector2(32,36)),false)

func row_background(top: int) -> void:
	var texture: Texture2D=art.texture("BUTTON_RECTANGLE")
	if texture==null:return
	for y in 3:
		for x in 57:
			draw_texture_rect_region(texture,Rect2(x*8,top+y*12,8,12),Rect2(0 if x==0 else 16 if x==56 else 8,y*12,8,12))
