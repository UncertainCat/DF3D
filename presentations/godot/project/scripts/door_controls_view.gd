extends Control
# Child of the building sheet; coordinates are relative to its native frame.
var art=preload("res://scripts/original_ui.gd").new()
var state
var colors: Array[Color]=[]
var input_allowed: Callable

func configure(source,model) -> void:
	state=model;art.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	size=Vector2(488,168)
	mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(queue_redraw)
	queue_redraw()

func allowed() -> bool:
	return state!=null and state.phase==state.Phase.Ready and state.ticket==0 and (not input_allowed.is_valid() or input_allowed.call())

func _has_point(point: Vector2) -> bool:
	return Rect2(8,72,472,84).has_point(point)

func _gui_input(event: InputEvent) -> void:
	if not allowed() or state.snapshot.is_empty() or state.snapshot.controlled:return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if Rect2(424,84,24,36).has_point(event.position):state.set_forbidden(true);accept_event()
		elif Rect2(448,84,24,36).has_point(event.position):state.set_forbidden(false);accept_event()

func _draw() -> void:
	if state==null or state.snapshot.is_empty() or colors.size()!=16 or theme.default_font==null:return
	var value: Dictionary=state.snapshot
	var font: Font=theme.default_font
	if value.operated_by_mechanisms:
		font.draw_string(get_canvas_item(),Vector2(16,96),"Operated by Mechanisms",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[15])
		return
	font.draw_string(get_canvas_item(),Vector2(16,96),"Forbidden" if value.forbidden else "Passable",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[12] if value.forbidden else colors[10])
	if value.taken_by_invaders or value.used_by_intruder:
		font.draw_string(get_canvas_item(),Vector2(16,120),"DOOR TAKEN BY INVADERS" if value.taken_by_invaders else "DOOR USED BY INTRUDER",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[12] if value.taken_by_invaders else colors[14])
		font.draw_string(get_canvas_item(),Vector2(16,144),"Retake door to forbid it.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[4] if value.taken_by_invaders else colors[6])
		return
	for forbidden in [true,false]:
		var token: String="BUILDING_INFO_DOOR_FORBIDDEN" if forbidden else "BUILDING_INFO_DOOR_PERMITTED"
		if value.forbidden==forbidden:token+="_ACTIVE"
		var texture: Texture2D=art.texture(token)
		if texture!=null:draw_texture_rect(texture,Rect2(424 if forbidden else 448,84,24,36),false)

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(queue_redraw):state.changed.disconnect(queue_redraw)
