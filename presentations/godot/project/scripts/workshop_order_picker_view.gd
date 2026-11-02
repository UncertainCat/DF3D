extends "res://scripts/location_staff_candidates_frame.gd"
# Native two-column forced-workshop picker, protected183314. Recipe filtering
# belongs to DF; this view owns the byte-oriented text draft and its focus.
signal cancelled
var state
var input_allowed: Callable
var building_name:=""
var building_icon:=""
var first:=0
var query_bytes:=PackedByteArray()
var search_focused:=false
var blink:=false
func configure_picker(source,model) -> void:
	super.configure(source);state=model;mouse_filter=Control.MOUSE_FILTER_STOP
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	scrollbar.input_allowed=allowed
	state.changed.connect(func():
		if state.phase==state.Phase.Closed:hide()
		first=clampi(first,0,maxi(0,state.rows.size()-page_rows));scrollbar.set_rows(state.rows.size(),first);queue_redraw())
func allowed() -> bool:
	return (not input_allowed.is_valid() or input_allowed.call()) and state!=null and state.phase==state.Phase.Ready
func open(id: int,caption: String,icon: String) -> void:
	building_name=caption;building_icon=icon;first=0;query_bytes=PackedByteArray();search_focused=false;state.open(id);show();queue_redraw()
func query_text() -> String:
	var result:=""
	for value in query_bytes:result+=String.chr(value if value<128 else art.CP437_HIGH[value-128])
	return result
func _process(_delta: float) -> void:
	var next:=Time.get_ticks_msec()%1000<500
	if search_focused and next!=blink:blink=next;queue_redraw()
func layout(view: Vector2) -> void:
	frame_rows=maxi(13,floori(view.y/12)-7);page_rows=maxi(1,int((frame_rows-8)/3))
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2(944,frame_rows*12)
	scrollbar.position=Vector2(912,60);scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	if state!=null:scrollbar.set_rows(state.rows.size(),first);first=scrollbar.first
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():return
	if input_allowed.is_valid() and not input_allowed.call():return
	if search_focused and event is InputEventKey and event.pressed and event.keycode!=KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:search_focused=false;queue_redraw();return
		if state.phase not in [state.Phase.Ready,state.Phase.Reading]:return
		var before:=query_bytes.duplicate()
		if event.keycode==KEY_BACKSPACE:
			if not query_bytes.is_empty():query_bytes.resize(query_bytes.size()-1)
		elif event.unicode>=32:
			# Native8bc1d4 uses capacity76, flags0xb: letters and spaces,
			# folding lowercase ASCII to uppercase; other bytes are ignored.
			for value in String.chr(event.unicode).to_utf8_buffer():
				if query_bytes.size()>=76:break
				if value>=97 and value<=122:value-=32
				if value==32 or (value>=65 and value<=90):query_bytes.append(value)
		if before!=query_bytes:first=0;state.set_query(query_text());queue_redraw()
		return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		cancelled.emit();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index==MOUSE_BUTTON_LEFT and Rect2(488,24,440,36).has_point(event.position) and state.phase in [state.Phase.Ready,state.Phase.Reading]:
		search_focused=not search_focused;queue_redraw();accept_event();return
	if not allowed():return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index==MOUSE_BUTTON_LEFT and Rect2(488,60,440,page_rows*36).has_point(event.position):
		var index:=first+int((event.position.y-60)/36)
		if index<state.rows.size():state.choose(state.rows[index].key)
		accept_event()
func caption(value: String,point: Vector2,width: float) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,width,12,Color.WHITE)
func _draw() -> void:
	if world==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,118,frame_rows)
	var border: Texture2D=art.texture("HOVER_RECTANGLE")
	if border!=null:
		for y in range(1,frame_rows-1):draw_texture_rect_region(border,Rect2(472,y*12,8,12),Rect2(16,12,8,12))
	patch("BUTTON_RECTANGLE_SELECTED",Vector2i(2,2),56,3)
	var icon: Texture2D=art.texture(building_icon)
	if icon!=null:draw_texture_rect(icon,Rect2(24,26,32,32),false)
	caption(building_name,Vector2(72,46),384)
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			for x in 55:
				var sx:=0 if x==0 else x-49 if x>=51 else 1
				draw_texture_rect_region(filter,Rect2(488+x*8,24+y*12,8,12),Rect2(sx*8,y*12,8,12))
	caption(query_text()+("_" if search_focused and blink else "..." if not search_focused and query_bytes.is_empty() else ""),Vector2(504,46),400)
	if state==null:return
	for index in range(first,mini(first+page_rows,state.rows.size())):
		var y:=60+(index-first)*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(61,int(y/12)),55,3)
		caption(state.rows[index].name,Vector2(488,y+22),424)
