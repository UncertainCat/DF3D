extends Control
# Native384850 goods body, composed with the dialogue/footer by trade_view.
# All membership, grouping, selection and item status comes from owned DF pages.
signal cancelled
var world
var state
var input_allowed: Callable
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var colors: Array[Color]=[]
var canvases: Array[Control]=[]
var bars: Array=[]
var searches: Array=[]
var counter=preload("res://scripts/trade_counter_view.gd").new()
var icons: Dictionary={}
var _requested:=false
func configure_goods(source,model) -> void:
	world=source;state=model;art.configure(source);theme=art.theme;picture.configure(source)
	colors=art.installed_palette(source.assets_root());texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	for side in range(2):
		var canvas:=Control.new();add_child(canvas);canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.clip_contents=true;canvas.draw.connect(_draw_side.bind(side));canvases.append(canvas)
		var bar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(bar);bar.configure(source);bar.input_allowed=ready;bar.wheel_enabled=false;bars.append(bar)
		bar.row_changed.connect(func(_value):refresh())
		var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER");inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
		for edge in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(edge,12)
		var search=preload("res://scripts/stocks_filter.gd").new();add_child(search);search.theme=theme;search.byte_limit=256;search.configure(inset,colors);search.placeholder_ink=Color8(160,160,160)
		search.edited.connect(func(bytes):state.set_filter(side,bytes.get_string_from_utf8()));searches.append(search)
	add_child(counter);counter.configure_counter(source);counter.input_allowed=ready;counter.dismissed.connect(state.dismiss_counteroffer);counter.scrolled.connect(refresh)
	state.changed.connect(refresh)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func ready() -> bool:return allowed() and state!=null and state.goods_ready()
func layout(panel_size: Vector2) -> void:
	size=Vector2(panel_size.x-32,maxf(0,panel_size.y-192))
	var left: int=floori(panel_size.x/16)*8-24
	for side in range(2):
		var x: int=0 if side==0 else left+24
		var width: int=left if side==0 else int(size.x)-x
		searches[side].position=Vector2(x,0);searches[side].size=Vector2(width,36)
		canvases[side].position=Vector2(x,36);canvases[side].size=Vector2(width,maxi(0,floori((size.y-36)/36)*36))
		bars[side].position=Vector2(x+width-16,36);bars[side].size=Vector2(16,canvases[side].size.y);bars[side].page=int(canvases[side].size.y/12)
	# Native counteroffer rows extend one cell farther right than ordinary goods.
	counter.position=Vector2(left+24,0);counter.layout(Vector2(size.x-left-16,size.y))
	refresh()
func refresh() -> void:
	if state==null or canvases.is_empty():return
	for side in range(2):
		var page: Dictionary=state.pages[side]
		bars[side].set_rows(int(page.get("total",0))*3,0 if state.phase==state.Phase.Closed else bars[side].first)
		# Native indented row art retains its full width beyond the unindented controls.
		canvases[side].size.x=_row_width(side)+16
		searches[side].editable=state.phase in [state.Phase.Active,state.Phase.Applying,state.Phase.GoodsReading]
		# Keep locally typed text while native filtering is pending.
		if state.goods_ready() and not searches[side].has_focus():searches[side].set_bytes(String(page.get("query","")).to_utf8_buffer())
		canvases[side].queue_redraw()
	var retained: Dictionary={}
	for id in state.appearances:
		var appearance: Dictionary=state.appearances[id]
		if appearance.is_empty() or state.item_type(id)<0:continue
		var cached: Dictionary=icons.get(id,{})
		if cached.get("appearance")!=appearance:cached={"appearance":appearance.duplicate(true),"texture":world.ammunition_icon(appearance,id) if state.item_type(id)==39 else world.item_sheet_icon(state.item_type(id),appearance,id)}
		retained[id]=cached
	icons=retained
	counter.visible=not state.counter_page.is_empty()
	if counter.visible:
		searches[1].release_focus();searches[1].hide();canvases[1].hide();bars[1].hide()
		var counter_icons: Dictionary={}
		for row in state.counter_page.rows:counter_icons[row.id]=icons.get(row.id,{}).get("texture")
		counter.set_page(state.counter_page,counter_icons,int(state.pages[1].total))
	else:counter.set_page({},{});searches[1].show();canvases[1].show()
	queue_redraw()
	if ready() and not _requested:_requested=true;_fetch.call_deferred()
func _fetch() -> void:
	_requested=false
	if not ready():return
	var ids: Array=[]
	for side in range(2):
		if side==1 and counter.visible:continue
		var page: Dictionary=state.pages[side]
		var first: int=int(bars[side].first/3)
		var count: int=ceili((canvases[side].size.y+(bars[side].first%3)*12)/36)
		if first<int(page.offset) or mini(first+count,int(page.total))>int(page.offset)+page.rows.size():state.read_page(side,first,mini(64,maxi(1,count)));return
		for row in page.rows.slice(maxi(0,first-int(page.offset)),maxi(0,first-int(page.offset))+count):
			if not row.group and not ids.has(row.id):ids.append(row.id)
	if counter.visible:
		var page: Dictionary=state.counter_page
		var first: int=counter.visible_first();var count: int=counter.visible_count()
		if first<int(page.offset) or mini(first+count,int(page.total))>int(page.offset)+page.rows.size():state.read_counter_page(first,mini(64,maxi(1,count)));return
		for row in page.rows.slice(maxi(0,first-int(page.offset)),maxi(0,first-int(page.offset))+count):
			if not ids.has(row.id):ids.append(row.id)
	state.request_appearances(ids.slice(0,64))
func _patch(canvas: Control,token: String,origin: Vector2,columns: int) -> void:
	var texture: Texture2D=art.texture(token)
	if texture==null:return
	for y in 3:
		for x in columns:canvas.draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _text(canvas: Control,value: String,point: Vector2,color: int) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(canvas.get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _row_width(side: int) -> float:return searches[side].size.x-(16 if bars[side].visible else 0)
func _draw_side(side: int) -> void:
	if state==null or colors.size()!=16:return
	var canvas: Control=canvases[side];var width: float=_row_width(side);var page: Dictionary=state.pages[side]
	for index in page.get("rows",[]).size():
		var row: Dictionary=page.rows[index];var y: int=(int(page.offset)+index)*36-bars[side].first*12
		if y+36<=0 or y>=canvas.size.y:continue
		var indent:=16 if row.parent>=0 else 0
		_patch(canvas,"BUTTON_CATEGORY_RECTANGLE" if row.group else "BUTTON_RECTANGLE",Vector2(indent,y),int(width/8))
		if row.group:_text(canvas,row.caption,Vector2(16,y+24),15)
		else:
			var frame: Texture2D=picture.texture(false)
			if frame!=null:
				for fy in 3:
					for fx in 5:canvas.draw_texture_rect_region(frame,Rect2(indent+fx*8,y+fy*12,8,12),Rect2(0 if fx==0 else 16 if fx==4 else 8,fy*12,8,12))
			var icon: Texture2D=icons.get(row.id,{}).get("texture")
			if icon!=null and y>=0 and y+36<=canvas.size.y:canvas.draw_texture_rect(icon,Rect2(indent+2,y+2,32,32),false)
			var caption: String=row.caption;var length: int=maxi(0,int((width-indent)/8)-24)
			if caption.length()>length:caption=caption.substr(0,length-3)+"..." if length>3 else caption.substr(0,length)
			if row.appraisal>0:caption=caption.substr(0,maxi(0,int((width-264-indent)/8)))
			_text(canvas,caption,Vector2(indent+56,y+24),[14,15,13,12,10][row.disposition])
			if row.contained_count>0:_text(canvas,row.contents_caption.substr(0,maxi(0,int((width-264-indent)/8))),Vector2(indent+56,y+36),14)
			if row.appraisal>0:_text(canvas,"Value: "+row.value_caption,Vector2(width-208,y+24),14)
			_text(canvas,"Weight: "+row.weight_caption,Vector2(width-208,y+36),15)
		if not row.group or row.flags&3:
			var texture: Texture2D=art.texture("ASSIGN_TRADE_SELECTED" if row.flags&1 else "ASSIGN_TRADE_NOT_SELECTED")
			if texture!=null:canvas.draw_texture_rect(texture,Rect2(width-40,y,24,36),false)
func _draw() -> void:
	for side in range(searches.size()):draw_rect(Rect2(searches[side].position,Vector2(searches[side].size.x,size.y)),Color8(28,28,28))
func _input(event: InputEvent) -> void:
	if not allowed():return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		state.close();cancelled.emit();get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		for search in searches:
			if search.has_focus():search.feed_key(event);get_viewport().set_input_as_handled();return
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if not ready():return
	for side in range(2):
		var canvas: Control=canvases[side];var local: Vector2=event.position-canvas.position
		if not canvas.visible or not Rect2(Vector2.ZERO,Vector2(_row_width(side),canvas.size.y)).has_point(local):continue
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:bars[side].move_to(bars[side].first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));return
		if event.button_index!=MOUSE_BUTTON_LEFT:return
		for search in searches:search.release_focus()
		var index: int=int((local.y+bars[side].first*12)/36)-int(state.pages[side].offset)
		if index<0 or index>=state.pages[side].rows.size():return
		state.toggle_row(side,index,not (local.x>=_row_width(side)-40 and local.x<_row_width(side)-16));return
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
