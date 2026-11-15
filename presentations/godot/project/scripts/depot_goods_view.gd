extends "res://scripts/location_staff_candidates_frame.gd"
# Staged read-only projection of native38a5b0. Not a public route: item artwork,
# contained rows, selection controls and commit-on-close remain unfinished.
signal cancelled
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var category_canvas: Control
var item_canvas: Control
var item_scrollbar
var search
var page: Array=[]
var requested:=false
func configure_goods(source,model) -> void:
	configure(source);state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
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
	search=preload("res://scripts/stocks_filter.gd").new();add_child(search);search.theme=theme;search.byte_limit=2048
	search.configure(inset,colors);search.edited.connect(func(bytes):state.set_query(bytes.get_string_from_utf8()))
	state.changed.connect(refresh)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func ready() -> bool:return allowed() and state!=null and state.phase==state.Phase.Ready
func category_width() -> int:return int(size.x/24)*8-40
func layout(view: Vector2) -> void:
	frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+floorf(fposmod(view.y,12)*0.5));size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	if state==null:return
	category_canvas.position=Vector2(16,24);category_canvas.size=Vector2(category_width(),int((frame_rows-3)/3)*36)
	item_canvas.position=Vector2(category_width()+56,60);item_canvas.size=Vector2(maxf(0,size.x-category_width()-88),category_canvas.size.y-36)
	scrollbar.position=Vector2(category_width()+16,24);scrollbar.size=Vector2(16,category_canvas.size.y)
	item_scrollbar.position=Vector2(size.x-32,60);item_scrollbar.size=Vector2(16,item_canvas.size.y)
	search.position=Vector2(category_width()+56,24);search.size=Vector2(maxf(0,size.x-category_width()-232),36)
	refresh()
func refresh() -> void:
	if state==null or item_canvas==null:return
	search.editable=state.phase in [state.Phase.Ready,state.Phase.Reading];search.set_bytes(state.query.to_utf8_buffer())
	scrollbar.page=maxi(0,int(category_canvas.size.y/36));scrollbar.set_rows(state.categories.size(),state.first_category)
	category_canvas.size.x=category_width()+(0 if scrollbar.visible else 16)
	item_scrollbar.page=maxi(0,int(item_canvas.size.y/12));item_scrollbar.set_rows(state.row_count()*3,state.first_item)
	item_canvas.size.x=maxf(0,size.x-category_width()-88)+(0 if item_scrollbar.visible else 16)
	page=state.page(int(item_scrollbar.first/3),ceili(item_canvas.size.y/36.0)+1)
	category_canvas.queue_redraw();item_canvas.queue_redraw();queue_redraw()
	if ready() and not requested and page.any(func(row):return row.has("id") and not state.items.has(row.id)):
		requested=true;_fetch.call_deferred()
func _fetch() -> void:
	requested=false
	if not ready():return
	var ids: Array=[]
	for row in page:
		if row.has("id"):ids.append(row.id)
	state.request_items(ids.slice(0,64))
func _patch(canvas: Control,token: String,origin: Vector2,columns: int) -> void:
	var texture: Texture2D=art.texture(token)
	if texture==null:return
	for y in 3:
		for x in columns:canvas.draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _text(canvas: Control,value: String,point: Vector2,color: int=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(canvas.get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _icon(canvas: Control,token: String,rect: Rect2) -> void:
	var texture: Texture2D=art.texture(token)
	if texture!=null:canvas.draw_texture_rect(texture,rect,false)
func exclusion_rect() -> Rect2:return Rect2(search.position+Vector2(search.size.x+8,0),Vector2(32,36))
func _draw_categories() -> void:
	for index in range(scrollbar.first,mini(state.categories.size(),scrollbar.first+scrollbar.page)):
		var row: Dictionary=state.categories[index];var y: int=(index-scrollbar.first)*36
		_patch(category_canvas,"BUTTON_CATEGORY_RECTANGLE_SELECTED" if row.type==state.category else "BUTTON_CATEGORY_RECTANGLE",Vector2(0,y),int(category_canvas.size.x/8))
		_text(category_canvas,row.caption,Vector2(16,y+24))
func _draw_items() -> void:
	for index in page.size():
		var entry: Dictionary=page[index];var y: int=index*36-(item_scrollbar.first%3)*12
		_patch(item_canvas,"BUTTON_CATEGORY_RECTANGLE" if entry.has("group") else "BUTTON_RECTANGLE",Vector2(0,y),int(item_canvas.size.x/8))
		if entry.has("group"):
			_text(item_canvas,entry.group.caption,Vector2(16,y+24))
			# Native38b49e gives the selected bit priority for mixed groups.
			var flags: int=entry.group.flags
			if flags&3:_icon(item_canvas,"ASSIGN_TRADE_SELECTED" if flags&1 else "ASSIGN_TRADE_NOT_SELECTED",Rect2(item_canvas.size.x-40,y,24,36))
		else:
			var row: Dictionary=state.items.get(entry.id,{})
			if row.is_empty():continue
			_text(item_canvas,row.caption,Vector2(56,y+24))
			_text(item_canvas,"Distance: "+str(row.distance),Vector2(item_canvas.size.x-208,y+24),10)
			# Native38bd9d..38bdf6: prohibition, resting haul state, selection.
			if row.prohibited:_icon(item_canvas,"ASSIGN_TRADE_PROHIBITED",Rect2(item_canvas.size.x-88,y,24,36))
			if row.tag in [2,3]:_icon(item_canvas,"ASSIGN_TRADE_IN_DEPOT" if row.tag==3 else "ASSIGN_TRADE_BEING_BROUGHT",Rect2(item_canvas.size.x-64,y,24,36))
			_icon(item_canvas,"ASSIGN_TRADE_SELECTED" if row.tag>0 else "ASSIGN_TRADE_NOT_SELECTED",Rect2(item_canvas.size.x-40,y,24,36))
func _draw() -> void:
	if world==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28))
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	if search!=null:
		_icon(self,"ASSIGN_TRADE_CULLING_MANDATES_ON" if state.exclude_prohibited else "ASSIGN_TRADE_CULLING_MANDATES_OFF",exclusion_rect())
		_icon(self,"SELECT_ALL",Rect2(size.x-64,24,32,36))
func _input(event: InputEvent) -> void:
	if not allowed():return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:cancelled.emit();get_viewport().set_input_as_handled()
		elif search.has_focus():search.feed_key(event);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if not ready():return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var bar=scrollbar if event.position.x<category_width()+40 else item_scrollbar
		bar.move_to(bar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(bar.page if event.shift_pressed else 1));return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	search.release_focus()
	if exclusion_rect().has_point(event.position):state.set_options(state.sort_by_distance,state.pending_on_top,not state.exclude_prohibited);return
	if Rect2(category_canvas.position,category_canvas.size).has_point(event.position):
		var index: int=int((event.position.y-category_canvas.position.y)/36)+scrollbar.first
		if index<state.categories.size():state.select_category(state.categories[index].type)
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
