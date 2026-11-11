extends "res://scripts/standing_orders_view.gd"
# Staged overview from native4257d0. Action workflows remain pending.
var hovered: Dictionary={}
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var portraits: Dictionary={}
signal appointment_requested(row: Dictionary)
signal symbol_requested(row: Dictionary)
signal accounting_requested(row: Dictionary,setting: int)
const INTRO=["Members of the nobility have required rooms and can make demands. They cannot be reassigned.","Administrators handle various aspects of your fortress and can be reassigned. Many administrators also require rooms."]
const ROOM_TOKENS=["OFFICE","BEDROOM","DINING","TOMB"]
func configure_nobles(source,model) -> void:
	configure_standing_orders(source,model);picture.configure(source)
	scrollbar.input_allowed=allowed;scrollbar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):state.seek(value,capacity()))
	state.changed.connect(refresh);refresh()
func groups() -> Array:
	var result:=InfoTabs.rows(wide_tabs)
	if not wide_tabs:result.reverse()
	return result
func list_top() -> int:return 84 if wide_tabs else 108
func capacity() -> int:return maxi(0,int((size.y-list_top()-24)/36))
func visible_first() -> int:return mini(state.first,maxi(0,state.rows.size()-capacity()))
func spacing_columns() -> int:return maxi(0,int((int(size.x/8)-121-(2 if state.rows.size()>capacity() else 0))/2))
func status_x() -> int:return (62+spacing_columns())*8
func content_columns() -> int:return int(size.x/8)-4-(2 if state.rows.size()>capacity() else 0)
func accounting_visible(row: Dictionary) -> bool:return content_columns()>=122 and row.get("help",{}).has("accounting")
func hover_at(point: Vector2) -> Dictionary:
	if state==null or state.phase!=state.Phase.Ready or point.y<list_top():return {}
	var index:=int((point.y-list_top())/36)
	if index<0 or index>=mini(capacity(),state.rows.size()-visible_first()):return {}
	var row: Dictionary=state.rows[visible_first()+index]
	if not row.has("help"):return {}
	var help: Dictionary=row.help
	if point.x>=16 and point.x<status_x()+48 and not help.description.is_empty():return {"kind":"description","data":help.description}
	if not row.has_room_assessment or content_columns()<101:return {}
	for entry in [["rooms",48,128],["furniture",176,32],["demands",224,32],["mandates",256,32]]:
		if point.x>=status_x()+entry[1] and point.x<status_x()+entry[1]+entry[2]:return {"kind":entry[0],"data":help[entry[0]]}
	if accounting_visible(row) and point.x>=status_x()+304 and point.x<status_x()+464:return {"kind":"accounting","data":help.accounting}
	return {}
func _process(_delta: float) -> void:
	var next: Dictionary=hover_at(get_local_mouse_position()) if allowed() else {}
	if next!=hovered:hovered=next;queue_redraw()
func intro_lines() -> Array:
	var result: Array=[];var baseline:=list_top()-24
	var kind: String=hovered.get("kind","")
	if kind in ["rooms","furniture"]:
		for index in 4:
			var part: Dictionary=hovered.data[index];var point:=Vector2(16+int(index/2)*432,baseline+(index%2)*12)
			result.append({"text":part.actual,"point":point,"color":part.color})
			result.append({"text":part.required,"point":point+Vector2(216,0),"color":part.color})
	elif kind in ["demands","mandates"]:
		for index in mini(hovered.data.size(),maxi(0,int((content_columns()-1)/30))*3):
			var item: Dictionary=hovered.data[index]
			result.append({"text":item.text,"point":Vector2(16+int(index/3)*240,baseline+(index%3)*12),"color":item.color})
	elif kind=="accounting":
		for entry in [["title",0,0],["examples",168,0],["attained",0,12],["progress",0,24]]:
			result.append({"text":hovered.data[entry[0]],"point":Vector2(16+entry[1],baseline+entry[2]),"color":15})
	else:
		var paragraphs: Array=[hovered.data] if kind=="description" else INTRO
		for paragraph in paragraphs:
			var line: String=""
			for word in paragraph.split(" "):
				if not line.is_empty() and line.length()+1+word.length()>content_columns():
					result.append({"text":line,"point":Vector2(16,baseline+result.size()*12),"color":15});line=""
				line+=(" " if not line.is_empty() else "")+word
			result.append({"text":line,"point":Vector2(16,baseline+result.size()*12),"color":15})
		if result.size()>3:result.resize(3)
	return result
func holder_caption(row: Dictionary) -> String:
	if row.unit_id<0:return row.holder_caption
	var cells:=int(status_x()/8)-35-2
	var value: String=row.holder_caption
	if value.length()<cells:return value
	return value.left(maxi(0,cells-4))+"..." if cells>4 else value.left(maxi(0,cells-1))
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:refresh()
func refresh() -> void:
	hovered=hover_at(get_local_mouse_position()) if is_inside_tree() and allowed() else {}
	var retained: Dictionary={}
	for index in range(visible_first(),mini(state.rows.size(),visible_first()+capacity())):
		var row: Dictionary=state.rows[index]
		if not row.has("appearance"):continue
		var prior: Dictionary=portraits.get(row.unit_id,{})
		retained[row.unit_id]=prior if prior.get("recipe")==row.appearance else {"recipe":row.appearance.duplicate(true),"texture":world.candidate_icon(row.appearance)}
	portraits=retained
	scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),visible_first());queue_redraw()
func _exit_tree() -> void:
	hovered={}
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
func _input(event: InputEvent) -> void:
	if allowed() and state!=null and state.phase==state.Phase.Ready and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		if Rect2(0,list_top(),size.x,size.y-list_top()).has_point(point):
			state.seek(visible_first()+(capacity() if event.shift_pressed else 1)*(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),capacity());get_viewport().set_input_as_handled();return
	super._input(event)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var tabs:=groups()
	for index in tabs.size():
		var x:=8
		for caption in tabs[index]:
			var width: int=(caption.length()+4)*8
			if Rect2(x,12+index*24,width,24).has_point(event.position):
				if caption!="Nobles and administrators":information_requested.emit(caption)
				return
			x+=width
	if state.phase!=state.Phase.Ready:return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		if accounting_visible(row) and Rect2(status_x()+304,y,160,36).has_point(event.position):
			accounting_requested.emit(row.duplicate(true),int((event.position.x-status_x()-304)/32));return
		if row.can_appoint and Rect2(184,y,32,36).has_point(event.position):appointment_requested.emit(row.duplicate(true));return
		if row.assignment_id>=0 and Rect2(status_x(),y,32,36).has_point(event.position):symbol_requested.emit(row.duplicate(true));return
func icon(token: String,point: Vector2) -> void:
	var texture: Texture2D=art.texture(token)
	if texture!=null:draw_texture_rect(texture,Rect2(point,Vector2(32,36)),false)
func room_suffix(required: int,actual: int) -> String:
	return "NA" if required<=0 else "GOOD" if actual>=required else "MISSING" if actual<=0 else "PARTIAL"
func furniture_suffix(row: Dictionary) -> String:
	var result: String="NA"
	for index in 4:
		if row.actual_furniture[index]>=row.required_furniture[index]:continue
		if row.actual_furniture[index]<=0:return "MISSING"
		result="PARTIAL"
	return result
func obligation_suffix(value: int) -> String:return "NA" if value<0 else "TIME_GOOD" if value==0 else "TIME_WARN_%d"%value
func _draw() -> void:
	if state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var tabs:=groups()
	for index in tabs.size():
		var x:=8.0
		for caption in tabs[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Nobles and administrators")
	for line in intro_lines():text(line.text,line.point,line.color)
	if state.phase!=state.Phase.Ready:return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var top:=list_top()+index*36
		patch("BUTTON_RECTANGLE",Vector2i(2,int(top/12)),int(size.x/8)-(6 if state.rows.size()>capacity() else 4),3)
		text(row.title,Vector2(16,top+24),11);text(row.squad_caption,Vector2(16,top+36))
		text(holder_caption(row),Vector2(280,top+24),15 if row.unit_id>=0 or row.nemesis_id>=0 else 14)
		if row.unit_id>=0:
			patch("",Vector2i(28,int(top/12)),5,3,picture.texture(false))
			var portrait: Texture2D=portraits.get(row.unit_id,{}).get("texture")
			if portrait!=null:draw_texture_rect(portrait,Rect2(226,top+2,32,32),false)
		if row.can_appoint:icon("NOBLES_ADD",Vector2(184,top))
		if row.assignment_id>=0:icon("NOBLES_ASSIGN_SYMBOL",Vector2(status_x(),top))
		if not row.has_room_assessment or content_columns()<101:continue
		for room in 4:icon("NOBLES_"+ROOM_TOKENS[room]+"_"+room_suffix(row.required_rooms[room],row.actual_rooms[room]),Vector2(status_x()+48+room*32,top))
		icon("NOBLES_FURN_"+furniture_suffix(row),Vector2(status_x()+176,top))
		icon("NOBLES_DEMANDS_"+obligation_suffix(row.demand_status),Vector2(status_x()+224,top))
		icon("NOBLES_MANDATES_"+obligation_suffix(row.mandate_status),Vector2(status_x()+256,top))
		if accounting_visible(row):
			for setting in 5:icon("NOBLES_ACCOUNTING_%d_%s"%[setting+1,"ACTIVE" if row.help.accounting.setting==setting else "INACTIVE"],Vector2(status_x()+304+setting*32,top))
