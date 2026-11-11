extends "res://scripts/places_view.gd"
# Native39faf0 uses the shared information frame, three-cell rows and item art.
const OBJECT_TABS=["Artifacts","Symbols","Named objects","Written content"]
const OBJECT_EMPTY=[[
	[0,"There aren't any crafted artifacts here."],[2,"Your workers will rarely make them on their own."],[4,"You may also send a squad to obtain one."]],
	[[0,"You haven't named any position symbols yet."],[2,"You can do this from the Nobles and Administrators menu."]],
	[[0,"There are no named objects here."],[2,"Citizens, especially soldiers, will rarely name items."]],
	[[0,"There is no written content here."],[2,"Prepare writing material and assign scholars to a library."],[4,"Writing materials include paper and parchment sheets."],[5,"Use these to make scrolls and quires."],[7,"Libraries are a location that can be created at a zone."]]]
func configure_objects(source,model) -> void:configure_places(source,model)
func information_rows() -> Array:
	var groups:=InfoTabs.rows(wide_tabs)
	# Objects keeps its active group next to the category tabs at narrow widths.
	if not wide_tabs:groups.reverse()
	return groups
func information_caption_at(point: Vector2) -> String:
	var groups:=information_rows()
	for row in groups.size():
		var x:=8
		for caption in groups[row]:
			var width: int=(caption.length()+4)*8
			if Rect2(x,12+row*24,width,24).has_point(point):return caption
			x+=width
	return ""
func list_top() -> int:return 72 if wide_tabs else 96
func tab_rect(index: int) -> Rect2:
	var x:=8
	for previous in index:x+=(OBJECT_TABS[previous].length()+4)*8
	return Rect2(x,36 if wide_tabs else 60,(OBJECT_TABS[index].length()+4)*8,24)
func right_cell() -> int:return int(size.x/8)+2-(2 if state.rows.size()>capacity() else 0)
func extra_cells() -> int:return maxi(0,int(2*(right_cell()-74)/3))
func navigation_x() -> int:return (32+extra_cells())*8
func ownership_x() -> int:return (40+extra_cells())*8
func clipped(value: String,cells: int) -> String:
	if value.length()<=cells:return value
	return value.left(cells-3)+"..." if cells>3 else value.left(maxi(0,cells))
func refresh() -> void:
	var retained: Dictionary={}
	for index in range(visible_first(),mini(state.rows.size(),visible_first()+capacity())):
		var row: Dictionary=state.rows[index]
		if not row.has("appearance"):continue
		var prior: Dictionary=portraits.get(row.item_id,{})
		retained[row.item_id]=prior if prior.get("recipe")==row.appearance else {"recipe":row.appearance.duplicate(true),"texture":world.ammunition_icon(row.appearance,row.item_id) if row.item_type==39 else world.item_sheet_icon(row.item_type,row.appearance,row.item_id)}
	portraits=retained
	scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),visible_first());queue_redraw()
func update_hover() -> void:
	if not is_instance_valid(hover_help):return
	var target:=hover_target(pointer_position) if pointer_known and allowed() else ""
	if target.is_empty():hover_help.leave(get_instance_id())
	else:hover_help.enter_objects(get_instance_id(),target)
func _input(event: InputEvent) -> void:
	if allowed() and state!=null and state.phase==state.Phase.Ready and state.rows.size()>capacity() and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		var top:=60 if wide_tabs else 84
		if Rect2(0,top,size.x+8,size.y-top).has_point(point):
			var step: int=(capacity() if event.shift_pressed else 1)*(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)
			state.seek(visible_first()+step,capacity());get_viewport().set_input_as_handled();return
	super._input(event)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var caption:=information_caption_at(event.position)
	if not caption.is_empty():
		if caption!="Objects":information_requested.emit(caption)
		return
	for index in 4:
		if tab_rect(index).has_point(event.position):state.select_tab(index);return
	if state.phase!=state.Phase.Ready:return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		for slot in 2:
			if row.has("position") and Rect2(navigation_x()+slot*24,y,24,36).has_point(event.position):navigation_requested.emit(row.duplicate(true),slot==1);return
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=information_rows()
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Objects")
	for index in 4:tab(OBJECT_TABS[index],tab_rect(index).position,"SHORT_SUBTAB",index==state.tab)
	if state.phase!=state.Phase.Ready:return
	if state.rows.is_empty():
		for line in OBJECT_EMPTY[state.tab]:text(line[1],Vector2(16,list_top()+24+int(line[0])*12))
		return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		patch("BUTTON_RECTANGLE",Vector2i(2,int(y/12)),int(size.x/8)-(6 if state.rows.size()>capacity() else 4),3)
		patch("",Vector2i(2,int(y/12)),5,3,picture.texture(false))
		var icon: Texture2D=portraits.get(row.item_id,{}).get("texture")
		if icon!=null:draw_texture_rect(icon,Rect2(18,y+2,32,32),false)
		var name_cells:=int(navigation_x()/8)-10
		text(clipped(row.native_name,name_cells),Vector2(72,y+24),14)
		text(clipped(row.translated_name,name_cells),Vector2(72,y+36))
		text(clipped(row.ownership,right_cell()-int(ownership_x()/8)-7),Vector2(ownership_x(),y+24))
		if row.has("position"):
			for slot in 2:
				var button: Texture2D=art.texture(["STOCKS_RECENTER","STOCKS_VIEW_ITEM"][slot])
				if button!=null:draw_texture_rect(button,Rect2(navigation_x()+slot*24,y,24,36),false)
