extends "res://scripts/location_staff_candidates_frame.gd"
# Native Details renderer2143b0; workshop reference232341. Other option
# families, native search/counts and global/responsive geometry remain staged.
signal cancelled
var state
var input_allowed: Callable
var colors: Array[Color]=[]
func configure_details(source,model) -> void:
	super.configure(source);state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	scrollbar.row_changed.connect(func(value):state.seek(value))
	scrollbar.input_allowed=func():return state.phase==state.Phase.Ready and (not input_allowed.is_valid() or input_allowed.call())
	state.changed.connect(func():
		if state.phase==state.Phase.Closed:hide()
		sync_scroll();queue_redraw())
func open(building: int,order: int) -> void:
	state.open(building,order);show();queue_redraw()
func layout(view: Vector2) -> void:
	var rows_count:=maxi(13,floori(view.y/12)-10)
	var origin:=Vector2(72,48+fposmod(view.y,12)*0.5)
	if position==origin and size==Vector2(832,rows_count*12):return
	position=origin;frame_rows=rows_count;size=Vector2(832,frame_rows*12);sync_scroll();queue_redraw()
func sync_scroll() -> void:
	if state==null or scrollbar==null:return
	page_rows=maxi(1,int((size.y-144)/36))
	scrollbar.position=Vector2(800,120);scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	if state.snapshot.get("selected_option",-1)>=0:scrollbar.set_rows(state.rows.size(),state.first)
	else:scrollbar.hide()
func back() -> void:
	if state.ticket!=0:return
	if state.snapshot.get("selected_option",-1)>=0:state.read_root()
	else:cancelled.emit()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		back();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready or not event is InputEventMouseButton or not event.pressed:return
	var selected: int=state.snapshot.get("selected_option",-1)
	if selected>=0 and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var top:=120 if selected>=0 else 48
	if not Rect2(16,top,784,size.y-top-24).has_point(event.position):return
	var index:=int((event.position.y-top)/36)
	if selected>=0:
		index+=state.first
		if index<state.rows.size():state.choose(state.rows[index].id)
	elif index<state.snapshot.get("options",[]).size():state.select_option(index)
	accept_event()
func text(value: String,point: Vector2,color:=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,size.x-point.x-16,12,colors[color] if colors.size()>color else Color.WHITE)
func _draw() -> void:
	if world==null or state==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,104,frame_rows)
	if state.snapshot.is_empty():return
	text(state.snapshot.get("caption",""),Vector2(16,32))
	var selected: int=state.snapshot.get("selected_option",-1)
	if selected<0:
		for index in state.snapshot.options.size():text(state.snapshot.options[index].caption,Vector2(16,68+index*36))
		return
	var kind: int=state.snapshot.options[selected].kind
	# Captured native setting headings for the two wired semantic families.
	if kind in [0,6]:text("Setting material" if kind==0 else "Setting plant",Vector2(16,68))
	for index in mini(page_rows,state.rows.size()-state.first):
		var row: Dictionary=state.rows[state.first+index]
		text(row.caption,Vector2(16,140+index*36))
		if row.has("count_caption"):text(row.count_caption,Vector2(720,140+index*36),13 if row.get("estimated",false) else 14)
