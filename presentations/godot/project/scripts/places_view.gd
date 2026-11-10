extends "res://scripts/standing_orders_view.gd"
# Staged Places layout from the 1200x800 native reference. Wider layouts,
# truncation and control hover still require native comparison before exposure.
signal navigation_requested(row: Dictionary,inspect: bool)
signal siege_requested(building_id: int,action: int)
const PLACE_TABS=["Zones","Locations","Stockpiles","Workshops","Farm plots","Siege engines"]
const SIEGE_ACTIONS=[3,4,2,1,0]
const SIEGE_TOKENS=["FIRE_AT_WILL","PRACTICE_FIRE","PREPARE_TO_FIRE","KEEP_LOADED","NOT_IN_USE"]
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var portraits: Dictionary={}
func tab(value: String,point: Vector2,token: String,selected: bool) -> float:
	if token!="SHORT_SUBTAB" or not selected:return super.tab(value,point,token,selected)
	var width:=value.length()+4;var texture: Texture2D=art.texture(token+"_SELECTED")
	if texture!=null:
		for y in 2:
			for x in width:
				var sx:=x if x<2 else x-width+5 if x>=width-2 else 2
				draw_texture_rect_region(texture,Rect2(point+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point+Vector2(16,18),value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color8(0,44,70))
	return width*8
func configure_places(source,model) -> void:
	configure_standing_orders(source,model);picture.configure(source)
	scrollbar.input_allowed=allowed;scrollbar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):state.seek(value,capacity()))
	state.changed.connect(refresh);refresh()
func list_top() -> int:return (96 if wide_tabs else 120)+(48 if state!=null and state.tab==5 and not state.rows.is_empty() else 0)
func capacity() -> int:return maxi(0,int((size.y-list_top()-24)/36))
func visible_first() -> int:return mini(state.first,maxi(0,state.rows.size()-capacity()))
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:refresh()
func tab_rect(index: int) -> Rect2:
	var x:=8
	for previous in range((index/3)*3,index):x+=(PLACE_TABS[previous].length()+4)*8
	return Rect2(x,(36 if wide_tabs else 60)+(index/3)*24,(PLACE_TABS[index].length()+4)*8,24)
func refresh() -> void:
	var retained: Dictionary={}
	for index in range(visible_first(),mini(state.rows.size(),visible_first()+capacity())):
		var row: Dictionary=state.rows[index]
		if not row.has("appearance"):continue
		var prior: Dictionary=portraits.get(row.building_id,{})
		retained[row.building_id]=prior if prior.get("recipe")==row.appearance else {"recipe":row.appearance.duplicate(true),"texture":world.candidate_icon(row.appearance)}
	portraits=retained
	scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),visible_first());queue_redraw()
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
func _input(event: InputEvent) -> void:
	# Native399c36 gates the shared contextual-scroll helper140f2b0 by
	# panel cells, starting above the ordinary list (also on the Siege tab).
	if allowed() and state!=null and state.phase==state.Phase.Ready and state.rows.size()>capacity() and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		var top:=84 if wide_tabs else 108
		if Rect2(0,top,size.x+8,size.y-top).has_point(point):
			var step: int=(capacity() if event.shift_pressed else 1)*(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)
			state.seek(visible_first()+step,capacity());get_viewport().set_input_as_handled();return
	super._input(event)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	for index in 6:
		if tab_rect(index).has_point(event.position):state.select_tab(index);return
	if state.phase!=state.Phase.Ready:return
	if state.tab==5 and not state.rows.is_empty():
		for slot in 5:
			if Rect2(264+slot*24,list_top()-48,24,36).has_point(event.position):siege_requested.emit(-1,SIEGE_ACTIONS[slot]);return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		for slot in 2:
			if row.has("position") and Rect2(480+slot*24,y,24,36).has_point(event.position):navigation_requested.emit(row.duplicate(true),slot==1);return
		if state.tab==5:
			for slot in 5:
				if Rect2(264+slot*24,y,24,36).has_point(event.position):siege_requested.emit(row.building_id,SIEGE_ACTIONS[slot]);return
func _siege_buttons(y: int,selected: int) -> void:
	for slot in 5:
		var token: String="BUILDING_INFO_SIEGE_ENGINE_"+SIEGE_TOKENS[slot]+("_ACTIVE" if selected==SIEGE_ACTIONS[slot] else "")
		var icon: Texture2D=art.texture(token)
		if icon!=null:draw_texture_rect(icon,Rect2(264+slot*24,y,24,36),false)
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Places")
	for index in 6:tab(PLACE_TABS[index],tab_rect(index).position,"SHORT_SUBTAB",index==state.tab)
	if state.phase!=state.Phase.Ready:return
	if state.tab==5 and not state.rows.is_empty():
		text("All siege engines",Vector2(72,list_top()-24),11)
		var selected: int=state.rows[0].siege_action
		for row in state.rows:
			if row.siege_action!=selected:selected=-1;break
		_siege_buttons(list_top()-48,selected)
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		patch("BUTTON_RECTANGLE",Vector2i(2,int(y/12)),int(size.x/8)-(6 if state.rows.size()>capacity() else 4),3)
		patch("",Vector2i(2,int(y/12)),5,3,picture.texture(false))
		var portrait: Texture2D=portraits.get(row.building_id,{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(18,y+2,32,32),false)
		text(row.name,Vector2(72,y+24),11)
		text(row.subtitle,Vector2(72,y+36),14 if state.tab>=4 else 15)
		if state.tab==5:
			_siege_buttons(y,row.siege_action);text(row.operator_caption,Vector2(264,y+36))
		else:
			text(row.job_caption if state.tab==3 else row.status_caption,Vector2(264,y+24),(0 if row.subtitle.is_empty() else 2) if state.tab==4 else 15)
			text(row.secondary_status,Vector2(264,y+36),10 if state.tab==4 else 15)
			text(row.status_overlay,Vector2(264,y+24))
		if row.has("position"):
			for slot in 2:
				var icon: Texture2D=art.texture(["STOCKS_RECENTER","STOCKS_VIEW_ITEM"][slot])
				if icon!=null:draw_texture_rect(icon,Rect2(480+slot*24,y,24,36),false)
