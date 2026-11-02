extends "res://scripts/location_staff_candidates_frame.gd"
# Native Details renderer2143b0; workshop reference232341. Other option
# families and global/responsive geometry remain staged.
signal cancelled
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var search_focused:=false
var blink:=false
func configure_details(source,model) -> void:
	super.configure(source);state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	scrollbar.row_changed.connect(func(value):state.seek(value))
	scrollbar.input_allowed=func():return state.phase==state.Phase.Ready and (not input_allowed.is_valid() or input_allowed.call())
	state.changed.connect(func():
		if state.phase==state.Phase.Closed:search_focused=false;hide()
		if state.snapshot.get("selected_option",-1)<0:search_focused=false
		if state.has_art() and state.art_page()<0:search_focused=false
		sync_scroll();queue_redraw())
func open(building: int,order: int) -> void:
	state.open(building,order);show();queue_redraw()
func layout(view: Vector2) -> void:
	var global: bool=state!=null and (state.building_id==-2 or state.has_art())
	var rows_count:=maxi(13,floori(view.y/12)-(5 if global else 10))
	var origin:=Vector2(16 if global else 72,(36 if global else 48)+fposmod(view.y,12)*0.5)
	var width:=976 if global else 832
	if position==origin and size==Vector2(width,rows_count*12):return
	position=origin;frame_rows=rows_count;size=Vector2(width,frame_rows*12);sync_scroll();queue_redraw()
func selected_kind() -> int:
	var selected: int=state.snapshot.get("selected_option",-1) if state!=null else -1
	return int(state.snapshot.options[selected].kind) if selected>=0 else -1
func list_top() -> int:
	if state!=null and state.has_art():return 132 if state.art_page()>=0 else 96
	return 84 if selected_kind()==3 else 120
func sync_scroll() -> void:
	if state==null or scrollbar==null:return
	page_rows=maxi(1,int((size.y-list_top()-24)/36))
	state.visible_rows=page_rows
	scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	if state.has_art():
		if state.art_page()>=0:scrollbar.set_rows(state.snapshot.art.total,state.first)
		else:scrollbar.hide()
	elif state.snapshot.get("selected_option",-1)>=0:scrollbar.set_rows(state.rows.size(),state.first)
	else:scrollbar.hide()
func back() -> void:
	if state.ticket!=0:return
	if state.has_art():
		search_focused=false
		if state.art_page()>=0:state.art_back()
		else:cancelled.emit()
		return
	if state.snapshot.get("selected_option",-1)>=0:state.read_root()
	else:cancelled.emit()
func _process(_delta: float) -> void:
	var value:=Time.get_ticks_msec()%1000<500
	if search_focused and value!=blink:blink=value;queue_redraw()
func feed_search(event: InputEventKey) -> void:
	if not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:search_focused=false;queue_redraw();return
	var value: String=state.query
	if event.keycode==KEY_BACKSPACE:value=value.left(maxi(0,value.length()-1))
	elif event.unicode>=32:
		# Native8b9c67/8b9d03: capacity20, flags0x17, raw text bytes.
		for byte in String.chr(event.unicode).to_utf8_buffer():
			if value.length()>=(60 if state.has_art() else 20):break
			value+=String.chr(byte if byte<128 else art.CP437_HIGH[byte-128])
	state.set_query(value)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	# Artwork's native Back route is right-click; Escape does not leave it.
	if state.has_art() and event is InputEventKey and event.keycode==KEY_ESCAPE:get_viewport().set_input_as_handled();return
	if search_focused and event is InputEventKey and event.keycode!=KEY_ESCAPE:
		feed_search(event);get_viewport().set_input_as_handled();return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		back();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready or not event is InputEventMouseButton or not event.pressed:return
	var selected: int=state.snapshot.get("selected_option",-1)
	if selected>=0 and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var searching: bool=(state.has_art() and state.art_page()>=0) or (not state.has_art() and selected_kind() in [0,6])
	if searching and Rect2(16,96 if state.has_art() else 84,size.x-32,36).has_point(event.position):
		search_focused=not search_focused;queue_redraw();accept_event();return
	var top:=list_top() if selected>=0 else 48
	if not Rect2(16,top,size.x-48,size.y-top-24).has_point(event.position):return
	var index:=int((event.position.y-top)/36)
	if selected>=0:
		if state.has_art() and state.art_page()<0 and event.position.x>=360:return
		index+=state.first-state.row_base()
		if index<state.rows.size():state.choose(state.rows[index].id)
	elif index<state.snapshot.get("options",[]).size():state.select_option(index)
	accept_event()
func text(value: String,point: Vector2,color:=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point+Vector2(0,4),value,HORIZONTAL_ALIGNMENT_LEFT,size.x-point.x-16,12,colors[color] if colors.size()>color else Color.WHITE)
func _draw() -> void:
	if world==null or state==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	if state.snapshot.is_empty():return
	if state.has_art():draw_art();return
	text(state.snapshot.get("caption",""),Vector2(16,32))
	var selected: int=state.snapshot.get("selected_option",-1)
	if selected<0:
		for index in state.snapshot.options.size():text(state.snapshot.options[index].caption,Vector2(16,68+index*36))
		return
	var kind: int=state.snapshot.options[selected].kind
	# Captured native setting headings for the two wired semantic families.
	if kind in [0,6]:text("Setting material" if kind==0 else "Setting plant",Vector2(16,68))
	if kind==3:text("Setting type",Vector2(16,68)) # Native literal1615920.
	if kind in [0,6]:
		var filter: Texture2D=art.texture("BUTTON_FILTER")
		var columns:=int((size.x-32)/8)
		if filter!=null:
			for y in 3:
				for x in columns:
					var sx:=0 if x==0 else x-columns+6 if x>=columns-4 else 1
					draw_texture_rect_region(filter,Rect2(16+x*8,84+y*12,8,12),Rect2(sx*8,y*12,8,12))
		text(state.query+("_" if search_focused and blink else "") if search_focused or not state.query.is_empty() else "...",Vector2(32,104),15 if search_focused or not state.query.is_empty() else 8)
	for index in mini(page_rows,state.rows.size()-state.first):
		var row: Dictionary=state.rows[state.first+index]
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,int(list_top()/12)+index*3),int((size.x-32)/8)-(2 if scrollbar.visible else 0),3)
		text(row.caption,Vector2(16,list_top()+20+index*36))
		if row.has("count_caption"):text(row.count_caption,Vector2(size.x-(32 if scrollbar.visible else 16)-str(row.count_caption).length()*8,list_top()+20+index*36),13 if row.get("estimated",false) else 14)
func draw_art() -> void:
	var caption: String=state.snapshot.art.caption
	text(caption,Vector2(maxf(16,(size.x-caption.length()*8)*0.5),20))
	if state.art_page()<0:
		for index in state.rows.size():
			patch("BUTTON_CATEGORY_RECTANGLE_ON",Vector2i(2,8+index*3),43,3)
			text(state.rows[index].caption,Vector2(24,116+index*36))
		return
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	var columns:=int((size.x-32)/8)
	if filter!=null:
		for y in 3:
			for x in columns:
				var sx:=0 if x==0 else x-columns+6 if x>=columns-4 else 1
				draw_texture_rect_region(filter,Rect2(16+x*8,96+y*12,8,12),Rect2(sx*8,y*12,8,12))
	text(state.query+("_" if search_focused and blink else "") if search_focused or not state.query.is_empty() else "...",Vector2(32,116),15 if search_focused or not state.query.is_empty() else 8)
	var offset: int=state.first-state.row_base()
	for index in mini(page_rows,state.rows.size()-offset):
		var row: Dictionary=state.rows[offset+index]
		var width:=columns-(2 if scrollbar.visible else 0)
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,11+index*3),width,3)
		var label: String=row.caption
		if label.length()>width-2:label=label.left(maxi(0,width-5))+"..."
		text(label,Vector2(16,152+index*36),11)
