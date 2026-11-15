extends "res://scripts/farm_contents_view.gd"
signal recenter_requested(position: Vector3i)

func available() -> bool:
	return permitted() and page>0 and state!=null and state.phase==state.Phase.Ready and not state.snapshot.is_empty()
func refresh() -> void:
	rows=[];icons.clear()
	if state==null:return
	rows=state.rows()
	var cursor:=int(state.snapshot.get("cursor",0))
	if state.snapshot.is_empty() or (state.phase!=state.Phase.Reading and floori(cell_first/3.0)!=cursor):cell_first=cursor*3
	if state.phase==state.Phase.Reading and floori(cell_first/3.0)!=cursor:rows=[]
	for index in visible_count():
		if rows[index].has("appearance"):icons[index]=world.candidate_icon(rows[index].appearance)
	scrollbar.set_rows(int(state.snapshot.get("total",0))*3,cell_first)
	scrollbar.visible=page>0 and int(state.snapshot.get("total",0))>page
	if not can_scroll():scrollbar.dragging=false
	queue_redraw()
func recenter_rect(index: int) -> Rect2:return Rect2(416+controls_offset(),index*36-row_offset(),24,36)
func help_at(point: Vector2) -> String:
	var index:=floori((point.y+row_offset())/36)
	return "linked-building" if index>=0 and index<visible_count() and recenter_rect(index).has_point(point) else ""
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:pointer_known=true;pointer_position=event.position;_process(0)
	if not available() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(scrollbar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
		accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	for index in visible_count():
		if recenter_rect(index).has_point(event.position):
			var row: Dictionary=rows[index];recenter_requested.emit(Vector3i(row.x,row.y,row.z));accept_event();return
func _draw() -> void:
	if state==null or state.snapshot.is_empty():return
	for index in visible_count():
		var row: Dictionary=rows[index];var top:=Vector2(0,index*36-row_offset())
		patch(art.texture("BUTTON_RECTANGLE"),top,57+controls_offset()/8)
		patch(picture.texture(false),top,5)
		var icon: Texture2D=icons.get(index)
		if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var name: String=row.name
		if name.length()>=35+controls_offset()/8:name=name.left(31+controls_offset()/8)+"..."
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,24),name,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		var button: Texture2D=art.texture("STOCKS_RECENTER")
		if button!=null:draw_texture_rect(button,recenter_rect(index),false)
