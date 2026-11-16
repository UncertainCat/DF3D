extends "res://scripts/location_staff_candidates_frame.gd"
# Native384850 chooser. Kept staged until choice/session transport is connected.
signal cancelled
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var rows: Control
func configure_catalog(source,model) -> void:
	configure(source);state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	rows=Control.new();add_child(rows);rows.mouse_filter=Control.MOUSE_FILTER_IGNORE;rows.clip_contents=true
	rows.draw.connect(_draw_rows)
	scrollbar.use_classic_art=false;scrollbar.wheel_enabled=false;scrollbar.input_allowed=ready
	scrollbar.row_changed.connect(func(_value):refresh())
	state.changed.connect(refresh)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func ready() -> bool:return allowed() and state!=null and state.phase==state.Phase.Ready
func layout(view: Vector2) -> void:
	frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+floorf(fposmod(view.y,12)*0.5));size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	if rows==null:return
	# Native384a37 uses (bottom_cell-9)/3; scrollbar384cf1 spans
	# screen cells9..3*(page+2), inset one cell from the row buttons.
	var page: int=int((frame_rows-6)/3)
	rows.position=Vector2(16,48);rows.size=Vector2(size.x-32,page*36)
	scrollbar.position=Vector2(size.x-32,60);scrollbar.size=Vector2(16,(page*3-2)*12);scrollbar.page=page
	refresh()
func refresh() -> void:
	if rows==null or state==null:return
	scrollbar.set_rows(state.choices.size(),0 if state.phase in [state.Phase.Closed,state.Phase.Reading,state.Phase.Unavailable] else scrollbar.first)
	rows.size.x=size.x-32-(16 if scrollbar.visible else 0)
	rows.queue_redraw();queue_redraw()
func _draw_rows() -> void:
	if state==null or colors.size()!=16:return
	var texture: Texture2D=art.texture("BUTTON_RECTANGLE")
	for index in range(scrollbar.first,mini(state.choices.size(),scrollbar.first+scrollbar.page)):
		var y: int=(index-scrollbar.first)*36
		if texture!=null:
			var columns:=int(rows.size.x/8)
			for dy in 3:
				for x in columns:rows.draw_texture_rect_region(texture,Rect2(x*8,y+dy*12,8,12),Rect2(0 if x==0 else 16 if x==columns-1 else 8,dy*12,8,12))
		var row: Dictionary=state.choices[index]
		if theme.default_font!=null:theme.default_font.draw_string(rows.get_canvas_item(),Vector2(0,y+24),row.race+state.from_text+row.name,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[15])
func _draw() -> void:
	if world==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28))
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	if state!=null and colors.size()==16 and theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(16,36),state.title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[14])
func _input(event: InputEvent) -> void:
	if not allowed():return
	if (event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		state.close();cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed():return
	if event is InputEventMouseButton and event.pressed:
		if ready() and event.button_index==MOUSE_BUTTON_LEFT and Rect2(rows.position,rows.size).has_point(event.position):
			var index: int=scrollbar.first+int((event.position.y-rows.position.y)/36)
			if index<state.choices.size():state.choose(state.choices[index].token)
		elif ready() and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:scrollbar.move_to(scrollbar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
		accept_event()
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
