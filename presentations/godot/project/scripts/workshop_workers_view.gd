extends Control
signal choose_requested
var art=preload("res://scripts/original_ui.gd").new()
var state
var input_allowed: Callable
func configure(source,model) -> void:
	state=model;art.configure(source);theme=art.theme;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP;state.changed.connect(queue_redraw)
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready:return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and Rect2(0,0,32,36).has_point(event.position):
		choose_requested.emit();accept_event()
func _draw() -> void:
	if state==null or state.phase!=state.Phase.Ready:return
	var icon: Texture2D=art.texture("BUILDING_SHEET_ASSIGN_WORKER")
	if icon!=null:draw_texture_rect(icon,Rect2(0,0,32,36),false)
	var caption:=""
	if state.permitted_workers.is_empty():caption="This workshop is free for anybody to use."
	else:
		for row in state.rows:
			if row.unit_id==state.permitted_workers[0]:caption=row.name;break
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(56,22),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
