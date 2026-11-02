extends "res://scripts/location_staff_candidates_frame.gd"
# Native Conditions reference: protected200556; comparison strings392edc.
# Staged: item/dependency editing, tab navigation and overflow remain unfinished.
signal cancelled
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var editing_index: int=-1
var number_draft:=""
const COMPARISONS=["at least","at most","greater than","less than","exactly","not"]
const FREQUENCIES=["One-time order","Restarts if completed, checked daily","Restarts if completed, checked monthly","Restarts if completed, checked seasonally","Restarts if completed, checked yearly"]
func configure_conditions(source,model) -> void:
	super.configure(source);scrollbar.hide();state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(func():
		if state.phase in [state.Phase.Closed,state.Phase.Unavailable]:hide()
		if state.phase not in [state.Phase.Ready,state.Phase.Reading,state.Phase.Applying]:finish_entry()
		queue_redraw())
func open(building: int,order: int) -> void:
	finish_entry();state.open(building,order);show();queue_redraw()
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
	if frame_rows==rows and position==origin and size==Vector2(944,rows*12):return
	frame_rows=rows
	position=origin;size=Vector2(944,frame_rows*12);queue_redraw()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if editing_index>=0 and event is InputEventKey and event.keycode!=KEY_ESCAPE:
		feed_number(event);get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		cancelled.emit();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if Rect2(832,72,32,36).has_point(event.position):state.cycle_frequency()
		for index in 5:
			if Rect2(720,size.y-192+index*36,32,36).has_point(event.position):state.add_suggestion(index)
		if state.phase==state.Phase.Ready:
			for index in mini(state.snapshot.conditions.size(),maxi(0,int((size.y-300)/36))):
				var row: Dictionary=state.snapshot.conditions[index]
				if row.kind==0:
					if Rect2(592,108+index*36,32,36).has_point(event.position):editing_index=row.index;number_draft="";queue_redraw();break
					if Rect2(624,108+index*36,32,36).has_point(event.position):state.edit_amount(row,1);break
					if Rect2(656,108+index*36,32,36).has_point(event.position):state.edit_amount(row,-1);break
					if Rect2(688,108+index*36,32,36).has_point(event.position):state.edit_amount(row,0,true);break
				if Rect2(848,108+index*36,32,36).has_point(event.position):state.remove_condition(state.snapshot.conditions[index]);break
		accept_event()
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
	if row.get("kind",0)!=0:return
	var background: Texture2D=art.texture("BUTTON_RECTANGLE_DARK")
	if background!=null:
		for dy in 2:
			for dx in 109:draw_texture_rect_region(background,Rect2(16+dx*8,y+6+dy*12,8,12),Rect2(8,12,8,12))
	text("Amount of ",Vector2(16,y+24),11)
	text(row.get("item_caption",""),Vector2(96,y+24),14)
	text("available is ",Vector2(16,y+36),11)
	var comparison: int=row.get("compare",-1)
	if comparison>=0 and comparison<COMPARISONS.size():
		text(COMPARISONS[comparison],Vector2(120,y+36),13)
		text(number_draft if not suggested and row.index==editing_index else str(row.threshold),Vector2(128+COMPARISONS[comparison].length()*8,y+36),12)
	if suggested and row.get("editable",false):
		patch("BUTTON_RECTANGLE_DARK",Vector2i(90,int(y/12)),4,3)
		icon("WORK_ORDERS_ADD_SUGGESTED_CONDITION",Vector2(720,y))
	elif not suggested:
		icon("WORK_ORDERS_ENTER_AMOUNT",Vector2(592,y))
		icon("WORK_ORDERS_INCREASE_AMOUNT",Vector2(624,y))
		icon("WORK_ORDERS_DECREASE_AMOUNT",Vector2(656,y))
		icon("WORK_ORDERS_CONDITIONS",Vector2(688,y))
		icon("WORK_ORDERS_REMOVE",Vector2(848,y))
func _draw() -> void:
	if world==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,118,frame_rows)
	var x:=8.0
	for value in ["Nobles and administrators","Objects","Justice"]:x+=tab(value,Vector2(x,12))
	x=8.0
	for value in ["Creatures","Tasks","Places","Labor","Work orders"]:x+=tab(value,Vector2(x,36),value=="Work orders")
	if state==null or state.snapshot.is_empty():return
	var row: Dictionary=state.snapshot
	var phases: Array=["","WORK_ORDERS_ACTIVE","WORK_ORDERS_WAITING","WORK_ORDERS_CHECKING","WORK_ORDERS_READY"]
	var phase: int=row.get("native_state",{}).get("phase",0)
	if phase>0 and phase<phases.size():icon(phases[phase],Vector2(16,72))
	text(row.name,Vector2(64,96),11)
	text("∞/∞" if row.total==0 else str(row.remaining)+"/"+str(row.total),Vector2(64,108),11)
	var frequency_caption: String=FREQUENCIES[row.frequency]
	if not row.conditions.is_empty():frequency_caption=frequency_caption.replace(", checked",", conditions checked")
	text(frequency_caption,Vector2(256,96))
	icon("WORK_ORDERS_CHANGE_FREQUENCY",Vector2(832,72))
	icon("WORK_ORDERS_ADD_ITEM_CONDITION",Vector2(864,72))
	icon("WORK_ORDERS_ADD_ORDER_CONDITION",Vector2(896,72))
	var top:=size.y-192
	text("Suggested conditions",Vector2(16,top))
	for index in mini(5,row.suggested_conditions.size()):condition(row.suggested_conditions[index],top+index*36,true)
	for index in mini(row.conditions.size(),maxi(0,int((top-108)/36))):condition(row.conditions[index],108+index*36,false)
