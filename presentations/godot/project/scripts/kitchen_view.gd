extends "res://scripts/standing_orders_view.gd"
# Staged Kitchen drawing. Native controls/hover and responsive geometry still
# require acceptance before the Labor owner exposes this surface.
var icons: Dictionary={}
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var search
signal standing_requested
const TYPE_LABELS=[" All"," Veg/Fruit/Leaves"," Seeds"," Drinks"," Meat/Fish/Other"]
func configure_kitchen(source,model) -> void:
	configure_standing_orders(source,model);picture.configure(source)
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/area_owner_filter.gd").new();add_child(search);search.theme=theme;search.byte_limit=26;search.ascii_only=true
	search.configure(inset,colors);search.edited.connect(state.set_search)
	scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(value):state.seek(value,capacity()))
	state.changed.connect(refresh);refresh()
func rows_top() -> int:return list_top()+24
func capacity() -> int:return maxi(0,int((size.y-rows_top()-85)/36))
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:refresh()
func refresh() -> void:
	if search!=null:
		search.position=Vector2(32,size.y-60);search.size=Vector2(312,36);search.editable=state.phase in [state.Phase.Ready,state.Phase.Reading]
		search.set_bytes(str(state.query.query).to_utf8_buffer())
	var retained: Dictionary={}
	for index in range(state.first,mini(state.rows.size(),state.first+capacity())):
		var row: Dictionary=state.rows[index];var token: String=row.material_token;var kind: int=row.receipt.key.item_type
		var key:=str(kind)+":"+token
		if icons.has(key):retained[key]=icons[key];continue
		var texture: Texture2D
		if kind in [53,54]:
			var parts:=token.split(":")
			if parts.size()>1:texture=world.farm_seed_icon(parts[1]) if kind==53 else world.farm_crop_icon(parts[1])
		else:texture=world.item_sheet_icon(kind,{"material_token":token,"subtype_raw":"","color_token":"","stack":1,"flags":0},-1)
		retained[key]=texture
	icons=retained
	# Native keeps the list at least80 cells wide; its track uses the remaining
	# height even when that leaves a partial row below the last visible food.
	scrollbar.position=Vector2(maxf(688,size.x-40),rows_top());scrollbar.size=Vector2(16,size.y-rows_top()-84);scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),state.first)
	queue_redraw()
func _input(event: InputEvent) -> void:
	if not allowed():return
	if event is InputEventKey and event.pressed and event.keycode!=KEY_ESCAPE and search!=null and search.has_focus():
		search.feed_key(event);get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.alt_pressed and not event.ctrl_pressed and not event.shift_pressed:
		var steps: Dictionary={KEY_UP:-1,KEY_8:-1,KEY_KP_8:-1,KEY_DOWN:1,KEY_2:1,KEY_KP_2:1,KEY_PAGEUP:-capacity(),KEY_9:-capacity(),KEY_KP_9:-capacity(),KEY_PAGEDOWN:capacity(),KEY_3:capacity(),KEY_KP_3:capacity()}
		if steps.has(event.keycode):state.move_selection(steps[event.keycode],capacity());get_viewport().set_input_as_handled();return
	super._input(event)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if search!=null:search.release_focus()
	if work_details_rect().has_point(event.position):work_details_requested.emit();accept_event();return
	if Rect2(136,list_top()-60,152,24).has_point(event.position):standing_requested.emit();accept_event();return
	if Rect2(88,list_top()-24,24,12).has_point(event.position):state.cycle_type(-1);accept_event();return
	if Rect2(256,list_top()-24,24,12).has_point(event.position):state.cycle_type(1);accept_event();return
	for permission in [1,2]:
		if Rect2(680+(permission-1)*32,list_top()-24,32,36).has_point(event.position):state.toggle_capability(permission);accept_event();return
	var positions: Array=[88,168,584,680,712]
	for column in 5:
		if Rect2(positions[column],list_top()+12,80 if column<3 else 32,12).has_point(event.position):state.select_sort(column,event.shift_pressed);accept_event();return
	var index:=int(floor((event.position.y-rows_top())/36))
	if index<0 or index>=capacity():return
	if state.first+index<state.rows.size():state.selected=state.first+index;queue_redraw()
	if Rect2(680,rows_top()+index*36,32,36).has_point(event.position):state.toggle(state.first+index,1);accept_event()
	elif Rect2(712,rows_top()+index*36,32,36).has_point(event.position):state.toggle(state.first+index,2);accept_event()
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Labor")
	var x:=8.0
	for caption in ["Work Details","Standing orders","Kitchen","Stone use"]:x+=tab(caption,Vector2(x,list_top()-60),"SHORT_SUBTAB",caption=="Kitchen")
	for cell in 24:
		var token: String="TYPE_FILTER_LEFT" if cell<3 else "TYPE_FILTER_RIGHT" if cell>=21 else "TYPE_FILTER_TEXT"
		var part: int=cell if cell<3 else cell-21 if cell>=21 else 0 if cell==3 else 2 if cell==20 else 1
		var texture:=strip(token,part)
		if texture!=null:draw_texture_rect(texture,Rect2(88+cell*8,list_top()-24,8,12),false)
	text(TYPE_LABELS[int(state.query.type_filter)+1],Vector2(112,list_top()-12))
	for permission in [1,2]:
		var texture: Texture2D=art.texture("EXPAND_LIST" if int(state.query.capability_filter)&permission else "CONTRACT_LIST")
		if texture!=null:draw_texture_rect(texture,Rect2(680+(permission-1)*32,list_top()-24,32,36),false)
	var positions: Array=[88,168,584,680,712]
	for index in 5:
		var active: bool=state.sort_active(index)
		for cell in 4:
			var texture:=strip("SORT_"+("ASCENDING_" if state.sort_directions[index] else "DESCENDING_")+("ACTIVE" if active else "INACTIVE"),cell)
			if texture!=null:draw_texture_rect(texture,Rect2(positions[index]+cell*8,list_top()+12,8,12),false)
		if index<2:
			for cell in 6:
				var texture:=strip("SORT_TEXT_"+("ACTIVE" if active else "INACTIVE"),0 if cell==0 else 2 if cell==5 else 1)
				if texture!=null:draw_texture_rect(texture,Rect2(positions[index]+32+cell*8,list_top()+12,8,12),false)
			text("Type" if index==0 else "Name",Vector2(positions[index]+40,list_top()+24),0 if active else 7)
	for index in mini(capacity(),state.rows.size()-state.first):
		var row: Dictionary=state.rows[state.first+index];var y:=rows_top()+index*36
		patch("BUTTON_RECTANGLE_SELECTED" if state.first+index==state.selected else "BUTTON_RECTANGLE",Vector2i(4,int(y/12)),maxi(80,int(size.x/8)-10),3)
		patch("",Vector2i(4,int(y/12)),5,3,picture.texture(state.first+index==state.selected))
		var icon: Texture2D=icons.get(str(row.receipt.key.item_type)+":"+row.material_token)
		if icon!=null:draw_texture_rect(icon,Rect2(34,y+2,32,32),false)
		text(row.name,Vector2(88,y+24));text(row.count_caption,Vector2(584,y+24),13 if row.estimated else 14)
		for permission in [1,2]:
			var suffix: String="CANNOT" if not (int(row.receipt.capabilities)&permission) else "RESTRICTED" if int(row.excluded)&permission else "ALLOWED"
			var texture: Texture2D=art.texture("LABOR_KITCHEN_"+("COOK_" if permission==1 else "BREW_")+suffix)
			if texture!=null:draw_texture_rect(texture,Rect2(680+(permission-1)*32,y,32,36),false)
