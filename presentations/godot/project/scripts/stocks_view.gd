extends "res://scripts/location_staff_candidates_frame.gd"
# Staged native Stocks surface. Individual artwork/actions and complete resize,
# input acceptance remain prerequisites for public exposure.
signal cancelled
signal item_requested(id: int)
signal recenter_requested(id: int)
signal item_flag_requested(id: int,operation: int,value: bool)
const FLAGS=[0x80000,0x200000,0x800000,0x1000000]
const BUTTONS=["STOCKS_FORBID","STOCKS_DUMP","STOCKS_MELT","STOCKS_HIDE"]
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var category_canvas: Control
var item_canvas: Control
var item_scrollbar
var search
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var page: Array=[]
var total_rows:=0
var requested:=false
var icons: Dictionary={}
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO
func configure_stocks(source,model,help=null) -> void:
	hover_help=help;mouse_exited.connect(_leave_hover)
	visibility_changed.connect(func():if not is_visible_in_tree():_leave_hover())
	configure(source);state=model;picture.configure(source)
	colors=art.installed_palette(source.assets_root());mouse_filter=Control.MOUSE_FILTER_STOP
	category_canvas=Control.new();add_child(category_canvas);category_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;category_canvas.clip_contents=true
	category_canvas.draw.connect(_draw_categories)
	item_canvas=Control.new();add_child(item_canvas);item_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;item_canvas.clip_contents=true
	item_canvas.draw.connect(_draw_items)
	item_scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(item_scrollbar);item_scrollbar.configure(source)
	for bar in [scrollbar,item_scrollbar]:bar.input_allowed=ready;bar.use_classic_art=true;bar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):state.first_category=value;refresh())
	item_scrollbar.row_changed.connect(func(value):state.first_item=value;refresh())
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/stocks_filter.gd").new();add_child(search);search.theme=theme;search.byte_limit=4096
	search.configure(inset,colors);search.edited.connect(func(bytes):state.set_query(bytes.get_string_from_utf8()))
	state.changed.connect(refresh)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func ready() -> bool:return allowed() and state!=null and state.phase==state.Phase.Ready
func layout(view: Vector2) -> void:
	frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	if state==null:return
	category_canvas.position=Vector2(16,24);category_canvas.size=Vector2(272,size.y-60)
	item_canvas.position=Vector2(328,60);item_canvas.size=Vector2(maxf(0,size.x-360),size.y-96)
	scrollbar.position=Vector2(288,24);scrollbar.size=Vector2(16,category_canvas.size.y)
	item_scrollbar.position=Vector2(size.x-32,60);item_scrollbar.size=Vector2(16,item_canvas.size.y)
	search.position=Vector2(328,24);search.size=Vector2(maxf(0,size.x-344),36)
	refresh()
func refresh() -> void:
	if state==null or item_canvas==null:return
	search.editable=state.phase in [state.Phase.Ready,state.Phase.Reading]
	search.set_bytes(state.query.to_utf8_buffer())
	var categories: Array=state.visible_categories()
	scrollbar.page=maxi(0,int(category_canvas.size.y/36));scrollbar.set_rows(categories.size(),state.first_category)
	page=[];total_rows=0
	for group in state.groups:
		if group.matches:total_rows+=1+(group.item_ids.size() if state.expanded(group) else 0)
	item_scrollbar.page=maxi(0,int(item_canvas.size.y/12));item_scrollbar.set_rows(total_rows*3,state.first_item)
	var first:=int(item_scrollbar.first/3);var limit:=ceili(item_canvas.size.y/36.0)+1;var offset:=0
	for group in state.groups:
		if not group.matches:continue
		if offset>=first and page.size()<limit:page.append({"group":group})
		offset+=1
		if not state.expanded(group):continue
		var ids: Array=group.item_ids
		for index in range(maxi(0,first-offset),mini(ids.size(),first+limit-offset)):
			if page.size()<limit:page.append({"id":ids[index]})
		offset+=ids.size()
	var retained: Dictionary={}
	for entry in page:
		if not entry.has("id"):continue
		var row: Dictionary=state.items.get(entry.id,{})
		# Native Stocks3a2a92 uses the same diagonal ammunition artwork as
		# the accepted Hunter view. Other families await their own acceptance.
		if row.get("type")!=39 or not row.has("appearance"):continue
		var cached: Dictionary=icons.get(row.id,{})
		if cached.get("appearance")!=row.appearance:
			cached={"appearance":row.appearance.duplicate(true),"texture":world.ammunition_icon(row.appearance,row.id)}
		retained[row.id]=cached
	icons=retained
	category_canvas.queue_redraw();item_canvas.queue_redraw();queue_redraw()
	if ready() and not requested:
		var ids: Array=[];var missing:=false
		for row in page:
			if row.has("id"):
				ids.append(row.id)
				if not state.items.has(row.id):missing=true
		if missing:requested=true;_fetch.call_deferred(ids.slice(0,64))
func _fetch(ids: Array) -> void:
	requested=false
	if ready():state.request_items(ids)
func _patch(canvas: Control,token: String,origin: Vector2,columns: int,texture: Texture2D=null) -> void:
	if texture==null:texture=art.texture(token)
	if texture==null:return
	for y in 3:
		for x in columns:canvas.draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _text(canvas: Control,value: String,point: Vector2,color: int=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(canvas.get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _draw_categories() -> void:
	var rows: Array=state.visible_categories()
	for index in range(scrollbar.first,mini(rows.size(),scrollbar.first+scrollbar.page)):
		var row: Dictionary=rows[index];var y: int=(index-scrollbar.first)*36
		_patch(category_canvas,"BUTTON_CATEGORY_RECTANGLE_SELECTED" if row.type==state.category else "BUTTON_CATEGORY_RECTANGLE",Vector2(0,y),34)
		_text(category_canvas,row.caption,Vector2(16,y+24))
		_text(category_canvas,row.stored,Vector2(208,y+24),7 if row.stored=="None" else 15)
		_text(category_canvas,row.unavailable,Vector2(208,y+36),12)
func control_rect(index: int,operation: int) -> Rect2:
	return Rect2(item_canvas.size.x-112+operation*24,index*36-(item_scrollbar.first%3)*12,24,36)
func _draw_items() -> void:
	for index in page.size():
		var entry: Dictionary=page[index];var y: int=index*36-(item_scrollbar.first%3)*12
		if entry.has("group"):
			var group: Dictionary=entry.group
			_patch(item_canvas,"BUTTON_CATEGORY_RECTANGLE",Vector2(0,y),int(item_canvas.size.x/8))
			_text(item_canvas,group.caption,Vector2(16,y+24))
			for operation in 4:
				var mask:=1<<operation
				if not (group.flags&(mask|(mask<<4))):continue
				var texture: Texture2D=art.texture(BUTTONS[operation]+("_ACTIVE" if group.flags&mask else ""))
				if texture!=null:item_canvas.draw_texture_rect(texture,control_rect(index,operation),false)
		else:
			_patch(item_canvas,"BUTTON_RECTANGLE",Vector2(0,y),int(item_canvas.size.x/8))
			_patch(item_canvas,"",Vector2(0,y),5,picture.texture(false))
			var row: Dictionary=state.items.get(entry.id,{})
			if row.is_empty():continue
			var icon: Texture2D=icons.get(row.id,{}).get("texture")
			if icon!=null and y>=0 and y+36<=item_canvas.size.y:item_canvas.draw_texture_rect(icon,Rect2(2,y+2,32,32),false)
			_text(item_canvas,row.caption,Vector2(56,y+24))
			for control in 6:
				var operation:=control-2
				if operation==1 and not row.can_dump or operation==2 and not row.can_melt:continue
				var token: String=["STOCKS_RECENTER","STOCKS_VIEW_ITEM"][control] if control<2 else BUTTONS[operation]+("_ACTIVE" if row.flags&FLAGS[operation] else "")
				var texture: Texture2D=art.texture(token)
				if texture!=null:item_canvas.draw_texture_rect(texture,control_rect(index,operation),false)
func _draw() -> void:
	if world==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28))
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
func _input(event: InputEvent) -> void:
	if not allowed():return
	if event is InputEventMouseMotion:
		pointer_known=true;pointer_position=get_global_transform_with_canvas().affine_inverse()*event.position
		_process(0)
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:cancelled.emit();get_viewport().set_input_as_handled()
		elif search.has_focus():search.feed_key(event);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func help_at(point: Vector2) -> String:
	if state==null or item_canvas==null:return ""
	point-=item_canvas.position
	if not Rect2(Vector2.ZERO,item_canvas.size).has_point(point):return ""
	var index:=int((point.y+(item_scrollbar.first%3)*12)/36)
	if index<0 or index>=page.size():return ""
	var entry: Dictionary=page[index]
	for operation in range(-2,4):
		if not control_rect(index,operation).has_point(point):continue
		if entry.has("group"):
			if operation<0:return ""
			var mask:=1<<operation
			if not (entry.group.flags&(mask|(mask<<4))):return ""
		else:
			var row: Dictionary=state.items.get(entry.id,{})
			if row.is_empty() or (operation==1 and not row.can_dump) or (operation==2 and not row.can_melt):return ""
		return ["recenter","view","forbid","dump","melt","visibility"][operation+2]
	return ""
func _leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
func _process(_delta: float) -> void:
	if not is_instance_valid(hover_help):return
	if pointer_known and ready():
		var kind:=help_at(pointer_position)
		if not kind.is_empty():hover_help.enter_stocks(get_instance_id(),kind);return
	hover_help.leave(get_instance_id())
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT or not ready():return
	search.release_focus()
	if Rect2(category_canvas.position,category_canvas.size).has_point(event.position):
		var index: int=int((event.position.y-category_canvas.position.y)/36)+scrollbar.first
		var rows: Array=state.visible_categories()
		if index<rows.size():state.select_category(int(rows[index].type))
		return
	var point: Vector2=event.position-item_canvas.position
	if not Rect2(Vector2.ZERO,item_canvas.size).has_point(point):return
	var index:=int((point.y+(item_scrollbar.first%3)*12)/36)
	if index>=page.size():return
	var entry: Dictionary=page[index]
	if entry.has("group"):
		var row: Dictionary=entry.group
		for operation in 4:
			var mask:=1<<operation
			if control_rect(index,operation).has_point(point):
				if row.flags&(mask|(mask<<4)):state.apply_group(state.key(row),operation,not bool(row.flags&mask))
				return
		state.toggle_expansion(state.key(row));return
	var row: Dictionary=state.items.get(entry.id,{})
	if row.is_empty():return
	for operation in range(-2,4):
		if not control_rect(index,operation).has_point(point):continue
		if operation==-2:recenter_requested.emit(row.id)
		elif operation==-1:item_requested.emit(row.id)
		elif (operation!=1 or row.can_dump) and (operation!=2 or row.can_melt):item_flag_requested.emit(row.id,operation,not bool(row.flags&FLAGS[operation]))
		return
func _exit_tree() -> void:
	_leave_hover()
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
