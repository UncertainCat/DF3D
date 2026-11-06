extends "res://scripts/location_staff_candidates_frame.gd"
# Native global renderer392f00; protected global-work-orders-native capture.
# Staged until Details, hover, responsive layout and navigation pass.
signal cancelled
signal create_requested
signal conditions_requested(id: int,workshop: int)
signal details_requested(id: int)
signal information_requested(caption: String)
const InfoTabs=preload("res://scripts/work_order_info_tabs.gd")
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var editing_id: int=-1
var editing_limit:=false
var draft:=""
var blink:=false
var wide_tabs:=false
var hover_help
var pointer_known:=false
var pointer_global:=Vector2.ZERO
func list_top() -> int:return 48 if wide_tabs else 72
# Native392f79..39315f divides the available row into thirds; coordinates here
# are relative to the frame's four-column left margin.
func row_end() -> int:return int(size.x/8)-8-(2 if state!=null and state.total>page_rows else 0)
func controls_x() -> int:return (int((12+row_end()+4)/3)-4)*8
func workshop_x() -> int:return (int((6+2*(row_end()+4))/3)-4)*8
func button_positions() -> Array:
	var first:=controls_x()+48
	var second:=workshop_x()+160
	return [first,first+32,first+64,first+96,first+128,first+160,first+192,second,second+32,second+64,(row_end()-3)*8]
func configure_orders(source,model,help=null) -> void:
	hover_help=help
	super.configure(source);state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_exited.connect(leave_hover)
	visibility_changed.connect(func():
		if not is_visible_in_tree():leave_hover())
	scrollbar.row_changed.connect(func(value):finish_entry();state.seek(value,page_rows))
	scrollbar.input_allowed=func():return state.phase==state.Phase.Ready and (not input_allowed.is_valid() or input_allowed.call())
	state.changed.connect(func():
		if state.phase in [state.Phase.Closed,state.Phase.Unavailable]:hide()
		if state.phase not in [state.Phase.Ready,state.Phase.Applying]:finish_entry()
		sync_scroll();queue_redraw())
func open() -> void:
	finish_entry();state.open();show();queue_redraw()
func layout(view: Vector2) -> void:
	frame_rows=maxi(13,floori(view.y/12)-7)
	wide_tabs=floori(view.x/8)>=155
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	page_rows=maxi(0,int((size.y-list_top()-72)/36));sync_scroll();queue_redraw()
func sync_scroll() -> void:
	if scrollbar==null or state==null:return
	scrollbar.position=Vector2(size.x-72,list_top());scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	scrollbar.set_rows(state.total,state.first)
	if state.capacity!=page_rows or state.first!=scrollbar.first:state.seek(scrollbar.first,page_rows)
func finish_entry() -> void:
	editing_id=-1;draft="";queue_redraw()
func _process(_delta: float) -> void:
	update_hover()
	if editing_id<0:return
	var next:=Time.get_ticks_msec()%1000<500
	if next!=blink:blink=next;queue_redraw()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:finish_entry();cancelled.emit();get_viewport().set_input_as_handled();return
		if editing_id<0:return
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:finish_entry()
		elif not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			var before:=draft
			if event.keycode==KEY_BACKSPACE:draft=draft.left(maxi(0,draft.length()-1))
			elif draft.length()<(3 if editing_limit else 4) and ((event.unicode>=48 and event.unicode<=57) or (event.unicode>=65 and event.unicode<=90)):draft+=String.chr(event.unicode)
			if draft!=before:
				var value:=0
				for index in draft.length():
					var digit:=draft.unicode_at(index)-48
					if digit<0 or digit>9:break
					value=value*10+digit
				if editing_limit:state.set_limit(editing_id,value)
				else:state.set_quantity(editing_id,value)
				queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		finish_entry();cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer_known=true;pointer_global=get_global_transform()*event.position;update_hover()
	if input_allowed.is_valid() and not input_allowed.call():return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var caption:=InfoTabs.caption_at(event.position,wide_tabs)
		if not caption.is_empty():
			if caption!="Work orders":information_requested.emit(caption)
			accept_event();return
	if state==null or state.phase!=state.Phase.Ready or (input_allowed.is_valid() and not input_allowed.call()):return
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		finish_entry();state.seek(state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),page_rows);accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if Rect2(size.x-48,list_top(),32,36).has_point(event.position) and state.native_state.get("manager_available",false):
		finish_entry();create_requested.emit();accept_event();return
	for index in page_rows:
		var row: Dictionary=state.rows.get(state.first+index,{})
		if row.is_empty():continue
		var y:=list_top()+index*36
		var buttons:=button_positions()
		for button in buttons.size():
			var x: int=buttons[button]
			if not Rect2(x,y,32,36).has_point(event.position):continue
			if button>=7 and button<=9 and row.workshop_id!=-1:return
			finish_entry()
			match button:
				0,7:editing_id=row.id;editing_limit=button==7
				1:state.set_quantity(row.id,row.remaining+1)
				2:state.set_quantity(row.id,maxi(0,row.remaining-1))
				3:state.move_order(row.id,-1)
				4:state.move_order(row.id,1)
				5:conditions_requested.emit(row.id,row.workshop_id)
				6:
					if row.native_state.details_available:details_requested.emit(row.id)
				8:state.set_limit(row.id,mini(999,row.max_workshops+1))
				9:state.set_limit(row.id,maxi(0,row.max_workshops-1))
				10:state.remove_order(row.id)
			queue_redraw();accept_event();return
		# Native3c5af8/3c5e28 includes the status/name/quantity region to the
		# left of the validation column, not just the number-entry button.
		if Rect2(16,y,controls_x()-16,36).has_point(event.position):
			finish_entry();editing_id=row.id;editing_limit=false;queue_redraw();accept_event();return
func hover_kind(point: Vector2) -> String:
	if state==null or state.phase!=state.Phase.Ready:return ""
	if state.native_state.get("manager_available",false) and Rect2(size.x-48,list_top(),32,36).has_point(point):return "new"
	for index in page_rows:
		var row: Dictionary=state.rows.get(state.first+index,{})
		if row.is_empty():continue
		var y:=list_top()+index*36
		if row.native_state.phase in [1,2,3,4] and Rect2(16,y,32,36).has_point(point):return ["","active","waiting","checking","ready"][row.native_state.phase]
		if row.native_state.validation_required and Rect2(controls_x(),y,32,36).has_point(point):return "validated" if row.validated else "not_validated"
		var buttons:=button_positions()
		for button in buttons.size():
			if not Rect2(buttons[button],y,32,36).has_point(point):continue
			if button==3 and row.position==0:continue
			if button==4 and row.position==state.total-1:continue
			if button==6 and not row.native_state.details_available:continue
			if button>=7 and button<=9 and row.workshop_id!=-1:continue
			return ["amount","amount","amount","priority","priority","conditions","details","shop_limit","shop_limit","shop_limit","remove"][button]
	return ""
func update_hover() -> void:
	if not is_instance_valid(hover_help):return
	var kind:=""
	if pointer_known and is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call()):
		kind=hover_kind(get_global_transform().affine_inverse()*pointer_global)
	if kind.is_empty():hover_help.leave(get_instance_id())
	else:hover_help.enter_work_order(get_instance_id(),kind)
func leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
func _exit_tree() -> void:
	leave_hover()
func text(value: String,point: Vector2,color: int=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color] if colors.size()>color else Color.WHITE)
func icon(token: String,point: Vector2) -> void:
	var texture: Texture2D=art.texture(token)
	if texture!=null:draw_texture_rect(texture,Rect2(point,Vector2(32,36)),false)
func tab(value: String,point: Vector2,selected:=false) -> float:
	var width:=value.length()+4
	var texture: Texture2D=art.texture("SHORT_TAB_SELECTED" if selected else "SHORT_TAB")
	if texture!=null:
		for y in 2:
			for x in width:
				var sx:=x if x<2 else x-width+5 if x>=width-2 else 2
				draw_texture_rect_region(texture,Rect2(point+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
	text(value,point+Vector2(16,16),0 if selected else 15)
	return width*8
func _draw() -> void:
	if world==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for row in groups.size():
		var x:=8.0
		for value in groups[row]:x+=tab(value,Vector2(x,12+row*24),value=="Work orders")
	if state==null:return
	if state.native_state.get("manager_available",false):
		icon("WORK_ORDERS_CREATE_NEW",Vector2(size.x-48,list_top()))
		if state.total==0:text("There are no active work orders.",Vector2(16,list_top()+12))
	if state.native_state.has("manager_available"):
		if not state.native_state.manager_available:
			text("A manager is required to coordinate",Vector2(16,size.y-48),12)
			text("work orders.",Vector2(16,size.y-36),12)
		elif state.native_state.validation_required:
			text("All work orders must be validated",Vector2(16,size.y-48))
			text("by the manager before they become",Vector2(16,size.y-36))
			text("active.",Vector2(16,size.y-24))
	var phases: Array=["","WORK_ORDERS_ACTIVE","WORK_ORDERS_WAITING","WORK_ORDERS_CHECKING","WORK_ORDERS_READY"]
	for index in page_rows:
		var row: Dictionary=state.rows.get(state.first+index,{})
		if row.is_empty():continue
		var y:=list_top()+index*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,int(y/12)),row_end()-1,3)
		icon(phases[row.native_state.phase],Vector2(16,y))
		var name: String=row.name
		var name_columns:=int((controls_x()-64)/8)
		if name.length()>=name_columns:name=name.left(maxi(0,name_columns-4))+"..."
		text(name,Vector2(64,y+24),11)
		var quantity: String="∞/∞" if row.total==0 else str(row.remaining)+"/"+str(row.total)
		if editing_id==row.id and not editing_limit:quantity=draft+("_" if blink else "")
		text(quantity,Vector2(64,y+36),11)
		var buttons:=button_positions()
		if row.native_state.validation_required:icon("WORK_ORDERS_VALIDATED" if row.validated else "WORK_ORDERS_NOT_VALIDATED",Vector2(controls_x(),y))
		for button in 3:icon(["WORK_ORDERS_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"][button],Vector2(buttons[button],y))
		if row.position>0:icon("WORK_ORDERS_PRIORITY_UP",Vector2(buttons[3],y))
		if row.position<state.total-1:icon("WORK_ORDERS_PRIORITY_DOWN",Vector2(buttons[4],y))
		icon("WORK_ORDERS_CONDITIONS",Vector2(buttons[5],y))
		if row.native_state.details_available:icon("WORK_ORDERS_DETAILS",Vector2(buttons[6],y))
		if row.workshop_id==-1:
			# Native393e31..393fcc, literals162b5d8..162b620.
			var limit: String="Can use any shop" if row.max_workshops<=0 else str(row.max_workshops)+(" shop" if row.max_workshops==1 else " shops")+" max"
			if editing_id==row.id and editing_limit:
				limit=draft+("_" if blink else "")+" shop(s) max"
				text("0 = Can use any shop",Vector2(workshop_x(),y+36))
			text(limit,Vector2(workshop_x(),y+24))
			for button in 3:icon(["WORK_ORDERS_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"][button],Vector2(buttons[7+button],y))
		elif row.native_state.has("workshop_name"):
			var workshop: String=row.native_state.workshop_name
			text(workshop,Vector2(workshop_x(),y+24))
		icon("WORK_ORDERS_REMOVE",Vector2(buttons[10],y))
