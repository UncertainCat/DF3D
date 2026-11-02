extends "res://scripts/location_staff_candidates_frame.gd"
# Native two-column forced-workshop picker, protected183314. Search input and
# complete keyboard parity remain staged; native recipe order is never resorted.
signal cancelled
var state
var input_allowed: Callable
var building_name:=""
var building_icon:=""
var first:=0
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
	building_name=caption;building_icon=icon;first=0;state.open(id);show();queue_redraw()
func layout(view: Vector2) -> void:
	frame_rows=maxi(13,floori(view.y/12)-7);page_rows=maxi(1,int((frame_rows-8)/3))
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2(944,frame_rows*12)
	scrollbar.position=Vector2(912,60);scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	if state!=null:scrollbar.set_rows(state.rows.size(),first);first=scrollbar.first
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():return
	if input_allowed.is_valid() and not input_allowed.call():return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		cancelled.emit();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
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
	# Reserve the native search strip while its input path is being completed.
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			for x in 55:
				var sx:=0 if x==0 else x-49 if x>=51 else 1
				draw_texture_rect_region(filter,Rect2(488+x*8,24+y*12,8,12),Rect2(sx*8,y*12,8,12))
	if state==null:return
	for index in range(first,mini(first+page_rows,state.rows.size())):
		var y:=60+(index-first)*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(61,int(y/12)),55,3)
		caption(state.rows[index].name,Vector2(488,y+22),424)
