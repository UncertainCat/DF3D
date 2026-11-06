extends "res://scripts/location_staff_candidates_frame.gd"
# Native Conditions reference: protected200556; comparison strings392edc.
# Staged: tab navigation and integrated resize/hover acceptance remain unfinished.
signal cancelled
signal information_requested(caption: String)
const InfoTabs=preload("res://scripts/work_order_info_tabs.gd")
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var editing_index: int=-1
var number_draft:=""
var blink:=false
var condition_scroll
var suggestion_scroll
var condition_first:=0
var suggestion_first:=0
var wide_tabs:=false
var hover_help
var pointer_known:=false
var pointer_global:=Vector2.ZERO
# Native38da4c..38db58: right-anchored controls and a two-cell header shift
# when the shared information tabs fit on one row.
func header_top() -> int:return 48 if wide_tabs else 72
func condition_top() -> int:return header_top()+36
func filter_top() -> int:return header_top()+72
func right_x(default_x: int) -> int:return int(size.x)-944+default_x
func condition_capacity() -> int:return maxi(0,int((size.y-204-condition_top())/36))
func row_shift(suggested: bool) -> int:return 16 if (suggestion_scroll.visible if suggested else condition_scroll.visible) else 0
const COMPARISONS=["at least","at most","greater than","less than","exactly","not"]
const FREQUENCIES=["One-time order","Restarts if completed, checked daily","Restarts if completed, checked monthly","Restarts if completed, checked seasonally","Restarts if completed, checked yearly"]
func configure_conditions(source,model,help=null) -> void:
	hover_help=help
	super.configure(source);scrollbar.hide();state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_exited.connect(leave_hover)
	visibility_changed.connect(func():
		if not is_visible_in_tree():leave_hover())
	scrollbar.row_changed.connect(func(value):state.seek_filter(value))
	scrollbar.input_allowed=func():return state.phase==state.Phase.Ready and (not input_allowed.is_valid() or input_allowed.call())
	condition_scroll=preload("res://scripts/area_location_scrollbar.gd").new()
	suggestion_scroll=preload("res://scripts/area_location_scrollbar.gd").new()
	for bar in [condition_scroll,suggestion_scroll]:
		add_child(bar);bar.configure(source);bar.hide();bar.input_allowed=scrollbar.input_allowed
	condition_scroll.row_changed.connect(func(value):finish_entry();condition_first=value;queue_redraw())
	suggestion_scroll.row_changed.connect(func(value):finish_entry();suggestion_first=value;queue_redraw())
	state.changed.connect(func():
		if state.phase in [state.Phase.Closed,state.Phase.Unavailable]:condition_first=0;suggestion_first=0;hide()
		if state.phase not in [state.Phase.Ready,state.Phase.Reading,state.Phase.Applying]:finish_entry()
		sync_filter_scroll();queue_redraw())
func sync_filter_scroll() -> void:
	if scrollbar==null or state==null:return
	page_rows=maxi(1,int((size.y-filter_top()-24)/36))
	state.set_filter_capacity(page_rows)
	scrollbar.position=Vector2(right_x(912),filter_top());scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	if state.filter_kind>=0:
		scrollbar.set_rows(state.filter_total,state.filter_first)
		if scrollbar.first!=state.filter_first:state.seek_filter(scrollbar.first)
	else:scrollbar.hide()
	if condition_scroll==null:return
	condition_scroll.position=Vector2(right_x(872),condition_top());condition_scroll.size=Vector2(16,condition_capacity()*36);condition_scroll.page=condition_capacity()
	suggestion_scroll.position=Vector2(right_x(872),size.y-192);suggestion_scroll.size=Vector2(16,144);suggestion_scroll.page=4
	if state.filter_kind<0 and not state.snapshot.is_empty():
		condition_scroll.set_rows(state.snapshot.get("conditions",[]).size(),condition_first);condition_first=condition_scroll.first
		suggestion_scroll.set_rows(state.snapshot.get("suggested_conditions",[]).size(),suggestion_first);suggestion_first=suggestion_scroll.first
	else:condition_scroll.hide();suggestion_scroll.hide()
func _process(_delta: float) -> void:
	update_hover()
	var next:=Time.get_ticks_msec()%1000<500
	if state!=null and state.filter_kind>=0 and blink!=next:blink=next;queue_redraw()
func feed_filter(event: InputEventKey) -> void:
	if not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed or state.phase not in [state.Phase.Ready,state.Phase.Reading]:return
	var value: String=state.filter_query
	if event.keycode==KEY_BACKSPACE:value=value.left(maxi(0,value.length()-1))
	else:
		# Native8baba4: capacity40, flags0xb; letters and spaces, ASCII folded.
		var code:=event.unicode
		if code>=97 and code<=122:code-=32
		if value.length()<40 and (code==32 or (code>=65 and code<=90)):value+=String.chr(code)
	state.set_filter_query(value)
func open(building: int,order: int) -> void:
	condition_first=0;suggestion_first=0;finish_entry();state.open(building,order);show();queue_redraw()
func finish_entry() -> void:editing_index=-1;number_draft="";queue_redraw()
func feed_number(event: InputEventKey) -> void:
	if not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:finish_entry();return
	var before:=number_draft
	if event.keycode==KEY_BACKSPACE:number_draft=number_draft.left(maxi(0,number_draft.length()-1))
	elif number_draft.length()<6 and ((event.unicode>=48 and event.unicode<=57) or (event.unicode>=65 and event.unicode<=90)):
		# Native8baf38 uses capacity6, flags4; parse its numeric prefix.
		number_draft+=String.chr(event.unicode)
	if number_draft!=before:
		var value:=0
		for index in number_draft.length():
			var digit:=number_draft.unicode_at(index)-48
			if digit<0 or digit>9:break
			value=value*10+digit
		state.set_threshold(editing_index,value);queue_redraw()
func layout(view: Vector2) -> void:
	var rows:=maxi(13,floori(view.y/12)-7)
	var origin:=Vector2(32,48+fposmod(view.y,12)*0.5)
	var width: int=(floori(view.x/8)-32)*8
	if frame_rows==rows and position==origin and size==Vector2(width,rows*12):return
	wide_tabs=floori(view.x/8)>=155
	frame_rows=rows
	position=origin;size=Vector2(width,frame_rows*12);sync_filter_scroll();queue_redraw()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if state.filter_kind>=0 and state.filter_kind<3 and event is InputEventKey and event.keycode!=KEY_ESCAPE:
		feed_filter(event);get_viewport().set_input_as_handled();return
	if editing_index>=0 and event is InputEventKey and event.keycode!=KEY_ESCAPE:
		feed_number(event);get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		cancelled.emit();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer_known=true;pointer_global=get_global_transform()*event.position;update_hover()
	if input_allowed.is_valid() and not input_allowed.call():return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var caption:=InfoTabs.caption_at(event.position,wide_tabs)
		if not caption.is_empty():
			if caption!="Work orders":information_requested.emit(caption)
			accept_event();return
	if state.filter_kind>=0:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and state.phase==state.Phase.Ready:
				scrollbar.move_to(state.filter_first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
			elif event.button_index==MOUSE_BUTTON_LEFT and Rect2(16,filter_top(),right_x(896),page_rows*36).has_point(event.position):
				var index:=int((event.position.y-filter_top())/36)
				if index<state.filter_rows.size():state.choose_filter(state.filter_rows[index].id)
			accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if state.phase==state.Phase.Ready:
			var bar=condition_scroll if event.position.y<size.y-192 else suggestion_scroll
			if Rect2(16,condition_top(),right_x(872),size.y-condition_top()-48).has_point(event.position):bar.move_to(bar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(bar.page if event.shift_pressed else 1))
		accept_event();return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if Rect2(right_x(832),header_top(),32,36).has_point(event.position):state.cycle_frequency()
		if Rect2(right_x(864),header_top(),32,36).has_point(event.position):finish_entry();state.add_item_condition()
		if Rect2(right_x(896),header_top(),32,36).has_point(event.position):finish_entry();state.open_dependencies()
		for index in 4:
			if Rect2(right_x(720)-row_shift(true),size.y-192+index*36,32,36).has_point(event.position):state.add_suggestion(suggestion_first+index)
		if state.phase==state.Phase.Ready:
			for index in mini(state.snapshot.conditions.size()-condition_first,condition_capacity()):
				var row: Dictionary=state.snapshot.conditions[condition_first+index]
				var shift:=row_shift(false)
				if row.kind==0:
					if Rect2(right_x(592)-shift,condition_top()+index*36,32,36).has_point(event.position):editing_index=row.index;number_draft="";queue_redraw();break
					if Rect2(right_x(624)-shift,condition_top()+index*36,32,36).has_point(event.position):state.edit_amount(row,1);break
					if Rect2(right_x(656)-shift,condition_top()+index*36,32,36).has_point(event.position):state.edit_amount(row,-1);break
					if Rect2(right_x(688)-shift,condition_top()+index*36,32,36).has_point(event.position):state.edit_amount(row,0,true);break
					for kind in 3:
						if Rect2(right_x(720)+kind*32-shift,condition_top()+index*36,32,36).has_point(event.position):finish_entry();state.open_filter(row.index,kind);break
				elif Rect2(right_x(592)-shift,condition_top()+index*36,32,36).has_point(event.position):state.edit_dependency(row);break
				if Rect2(right_x(848)-shift,condition_top()+index*36,32,36).has_point(event.position):finish_entry();state.remove_condition(row);break
		accept_event()
func hover_kind(point: Vector2) -> String:
	if state==null or state.phase!=state.Phase.Ready or state.snapshot.is_empty():return ""
	if state.filter_kind>=0 and state.filter_kind<3:return ""
	var phase: int=state.snapshot.get("native_state",{}).get("phase",0)
	if phase in [1,2,3,4] and Rect2(16,header_top(),32,36).has_point(point):return ["","active","waiting","checking","ready"][phase]
	if state.filter_kind==3:
		for index in mini(page_rows,state.filter_rows.size()):
			phase=state.filter_rows[index].get("native_state",{}).get("phase",0)
			if phase in [1,2,3,4] and Rect2(16,filter_top()+index*36,32,36).has_point(point):return ["","active","waiting","checking","ready"][phase]
		return ""
	for index in 3:
		if Rect2(right_x(832)+index*32,header_top(),32,36).has_point(point):return ["frequency","add_item","add_order"][index]
	var shift:=row_shift(false)
	for index in mini(state.snapshot.conditions.size()-condition_first,condition_capacity()):
		var row: Dictionary=state.snapshot.conditions[condition_first+index]
		var y:=condition_top()+index*36
		if Rect2(right_x(848)-shift,y,32,36).has_point(point):return "remove_condition"
		if row.kind!=0:
			if Rect2(right_x(592)-shift,y,32,36).has_point(point):return "dependency"
			continue
		for button in 7:
			if Rect2(right_x(592)+button*32-shift,y,32,36).has_point(point):
				return ["condition_amount","condition_amount","condition_amount","comparison","item_type","material","traits"][button]
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
func condition(row: Dictionary,y: float,suggested: bool) -> void:
	var shift:=row_shift(suggested)
	var background: Texture2D=art.texture("BUTTON_RECTANGLE_DARK")
	if background!=null:
		for dy in 2:
			for dx in int((size.x-72)/8)-int(shift/8):draw_texture_rect_region(background,Rect2(16+dx*8,y+6+dy*12,8,12),Rect2(8,12,8,12))
	if row.get("kind",0)==1:
		text(row.get("description",""),Vector2(16,y+24),11)
		text("must first be completed" if row.dependency==1 else "must first be activated",Vector2(16,y+36))
		text("Satisfied for next check" if row.satisfied else "Not satisfied for next check",Vector2(416,y+24),10 if row.satisfied else 12)
		icon("WORK_ORDERS_CHANGE_ORDER_CONDITION_CHECK_TYPE",Vector2(right_x(592)-shift,y));icon("WORK_ORDERS_REMOVE",Vector2(right_x(848)-shift,y))
		return
	text("Amount of ",Vector2(16,y+24),11)
	text(row.get("item_caption",""),Vector2(96,y+24),14)
	text("available is ",Vector2(16,y+36),11)
	var comparison: int=row.get("compare",-1)
	if comparison>=0 and comparison<COMPARISONS.size():
		text(COMPARISONS[comparison],Vector2(120,y+36),13)
		text(number_draft if not suggested and row.index==editing_index else str(row.threshold),Vector2(128+COMPARISONS[comparison].length()*8,y+36),12)
	if suggested and row.get("editable",false):
		patch("BUTTON_RECTANGLE_DARK",Vector2i(int(right_x(720)/8)-int(shift/8),int(y/12)),4,3)
		icon("WORK_ORDERS_ADD_SUGGESTED_CONDITION",Vector2(right_x(720)-shift,y))
	elif not suggested:
		text("Satisfied for next check" if row.satisfied else "Not satisfied for next check",Vector2(416,y+24),10 if row.satisfied else 12)
		icon("WORK_ORDERS_ENTER_AMOUNT",Vector2(right_x(592)-shift,y))
		icon("WORK_ORDERS_INCREASE_AMOUNT",Vector2(right_x(624)-shift,y))
		icon("WORK_ORDERS_DECREASE_AMOUNT",Vector2(right_x(656)-shift,y))
		icon("WORK_ORDERS_CONDITIONS",Vector2(right_x(688)-shift,y))
		for kind in 3:icon(["WORK_ORDERS_CHANGE_TYPE","WORK_ORDERS_CHANGE_MAT","WORK_ORDERS_CHANGE_ADJ"][kind],Vector2(right_x(720)+kind*32-shift,y))
		icon("WORK_ORDERS_REMOVE",Vector2(right_x(848)-shift,y))
func draw_filter() -> void:
	var condition_row: Dictionary={}
	for row in state.snapshot.get("conditions",[]):
		if row.kind==0 and row.index==state.filter_index:condition_row=row;break
	if condition_row.is_empty():return
	text("Amount of ",Vector2(16,header_top()+24),11);text(condition_row.get("item_caption",""),Vector2(96,header_top()+24),14)
	text("available is ",Vector2(16,header_top()+36),11)
	var comparison: int=condition_row.compare
	if comparison>=0 and comparison<COMPARISONS.size():
		text(COMPARISONS[comparison],Vector2(120,header_top()+36),13)
		text(str(condition_row.threshold),Vector2(128+COMPARISONS[comparison].length()*8,header_top()+36),12)
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			var columns:=int((size.x-32)/8)
			for x in columns:
				var sx:=0 if x==0 else x-columns+6 if x>=columns-4 else 1
				draw_texture_rect_region(filter,Rect2(16+x*8,condition_top()+y*12,8,12),Rect2(sx*8,y*12,8,12))
	text(state.filter_query+("_" if blink else ""),Vector2(24,condition_top()+24))
	for index in mini(page_rows,state.filter_rows.size()):
		var row: Dictionary=state.filter_rows[index]
		var y:=filter_top()+index*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,int(y/12)),int((size.x-32)/8)-(2 if state.filter_total>page_rows else 0),3)
		var selected: bool=condition_row.get("traits",[]).has(str(row.id))
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(16,y+24),row.name,HORIZONTAL_ALIGNMENT_LEFT,right_x(832) if state.filter_kind==2 else right_x(888),12,colors[10 if selected else 6] if state.filter_kind==2 and colors.size()>10 else Color.WHITE)
		if state.filter_kind==2:icon("WORK_ORDERS_ADJECTIVE_SELECTED" if selected else "WORK_ORDERS_ADJECTIVE_NOT_SELECTED",Vector2(right_x(856) if state.filter_total>page_rows else right_x(872),y))
func draw_dependency_picker() -> void:
	var phases: Array=["","WORK_ORDERS_ACTIVE","WORK_ORDERS_WAITING","WORK_ORDERS_CHECKING","WORK_ORDERS_READY"]
	for index in mini(page_rows,state.filter_rows.size()):
		var row: Dictionary=state.filter_rows[index]
		var y:=filter_top()+index*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,int(y/12)),int((size.x-32)/8)-(2 if state.filter_total>page_rows else 0),3)
		var phase: int=row.get("native_state",{}).get("phase",0)
		if phase>0 and phase<phases.size():icon(phases[phase],Vector2(16,y))
		var name: String=row.name
		if name.length()>=22:name=name.left(18)+"..."
		text(name,Vector2(64,y+24),11)
		text("∞/∞" if row.total==0 else str(row.remaining)+"/"+str(row.total),Vector2(64,y+36),11)
		var frequency: String=FREQUENCIES[row.frequency]
		if not row.conditions.is_empty():frequency=frequency.replace(", checked",", conditions checked")
		text(frequency,Vector2(256,y+24))
func _draw() -> void:
	if world==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for row in groups.size():
		var x:=8.0
		for value in groups[row]:x+=tab(value,Vector2(x,12+row*24),value=="Work orders")
	if state==null or state.snapshot.is_empty():return
	if state.filter_kind>=0 and state.filter_kind<3:draw_filter();return
	var row: Dictionary=state.snapshot
	var phases: Array=["","WORK_ORDERS_ACTIVE","WORK_ORDERS_WAITING","WORK_ORDERS_CHECKING","WORK_ORDERS_READY"]
	var phase: int=row.get("native_state",{}).get("phase",0)
	if phase>0 and phase<phases.size():icon(phases[phase],Vector2(16,header_top()))
	var name: String=row.name
	if name.length()>=22:name=name.left(18)+"..."
	text(name,Vector2(64,header_top()+24),11)
	text("∞/∞" if row.total==0 else str(row.remaining)+"/"+str(row.total),Vector2(64,header_top()+36),11)
	var frequency_caption: String=FREQUENCIES[row.frequency]
	if not row.conditions.is_empty():frequency_caption=frequency_caption.replace(", checked",", conditions checked")
	text(frequency_caption,Vector2(256,header_top()+24))
	if state.filter_kind==3:draw_dependency_picker();return
	icon("WORK_ORDERS_CHANGE_FREQUENCY",Vector2(right_x(832),header_top()))
	icon("WORK_ORDERS_ADD_ITEM_CONDITION",Vector2(right_x(864),header_top()))
	icon("WORK_ORDERS_ADD_ORDER_CONDITION",Vector2(right_x(896),header_top()))
	var top:=size.y-192
	text("Suggested conditions",Vector2(16,top))
	for index in mini(4,row.get("suggested_conditions",[]).size()-suggestion_first):condition(row.suggested_conditions[suggestion_first+index],top+index*36,true)
	for index in mini(row.conditions.size()-condition_first,condition_capacity()):condition(row.conditions[condition_first+index],condition_top()+index*36,false)
