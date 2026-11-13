extends Control
signal choose_requested
signal unit_requested(id: int)
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var state
var world
var unit_icon: Texture2D
var icon_elapsed:=0.0
var input_allowed: Callable
# Native assigned row187739..188093, protected165239. Captions from16013d8,
# 16013b8 and1601390; the native name formatter owns the sex/training suffix.
func configure(source,model) -> void:
	world=source;state=model;art.configure(source);picture.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(refresh)
func refresh() -> void:
	unit_icon=null
	if not state.assigned.is_empty():unit_icon=world.selection_icon(1,state.assigned.id,true)
	queue_redraw()
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	icon_elapsed+=delta
	if icon_elapsed>=0.25:icon_elapsed=0;refresh()
func assign_rect() -> Rect2:return Rect2(0,36 if not state.permitted_workers.is_empty() else 0,32,36)
func remove_rect() -> Rect2:return Rect2(416,0,32,36)
func specialization_rect() -> Rect2:return Rect2(0,96,456,36)
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready:return
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	if assign_rect().has_point(event.position):choose_requested.emit();accept_event();return
	if state.permitted_workers.is_empty():return
	if remove_rect().has_point(event.position):state.remove_worker();accept_event();return
	if state.assigned.get("can_specialize",false) and specialization_rect().has_point(event.position):
		state.set_specialized(not state.assigned.specialized);accept_event();return
	if not state.assigned.is_empty() and Rect2(0,0,40,36).has_point(event.position):unit_requested.emit(state.assigned.id);accept_event()
func patch(texture: Texture2D,rect: Rect2) -> void:
	if texture==null:return
	var columns:=int(rect.size.x/8)
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func caption(value: String,point: Vector2) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
func assigned_caption() -> String:
	var value: String=state.assigned.get("caption","")
	return value.left(38)+"..." if value.length()>=42 else value
func _draw() -> void:
	if state==null or state.phase!=state.Phase.Ready:return
	patch(art.texture("BUTTON_RECTANGLE"),Rect2(0,0,456,36))
	var icon: Texture2D=art.texture("BUILDING_SHEET_ASSIGN_WORKER")
	if icon!=null:draw_texture_rect(icon,assign_rect(),false)
	if state.permitted_workers.is_empty():
		caption("This workshop is free for anybody to use.",Vector2(56,24));return
	if not state.assigned.is_empty():
		patch(picture.texture(false),Rect2(0,0,40,36))
		if unit_icon!=null:draw_texture_rect(unit_icon,Rect2(2,2,32,32),false)
		caption(assigned_caption(),Vector2(56,24))
	var remove: Texture2D=art.texture("LOCATION_OCCUPATION_REMOVE_WORKER")
	if remove!=null:draw_texture_rect(remove,remove_rect(),false)
	caption("Only one master may be assigned to each workshop.",Vector2(56,58))
	if state.assigned.get("specialization_visible",false):
		var specialized: bool=state.assigned.specialized
		var mode: Texture2D=art.texture("WORKER_ONLY_DO_ASSIGNED_JOBS" if specialized else "WORKER_DO_ANY_AVAILABLE_JOB")
		if mode!=null:draw_texture_rect(mode,Rect2(0,96,32,36),false)
		caption(assigned_caption(),Vector2(56,106))
		caption("will only do assigned tasks" if specialized else "will do available tasks anywhere",Vector2(56,118))
