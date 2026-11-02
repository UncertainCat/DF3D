extends Control
# Native renderer1882fe/189a22 and protected workshop-work-orders reference.
# Order creation, row details and the numeric-entry action are still staged.
var art=preload("res://scripts/original_ui.gd").new()
var state
var input_allowed: Callable
var colors: Array[Color]=[]
func configure(source,model) -> void:
	state=model;art.configure(source);theme=art.theme;colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(queue_redraw)
func button_rect(index: int) -> Rect2:return Rect2(360+index*32,size.y-36,32,36)
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if state.phase!=state.Phase.Ready:return
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for index in [1,2]:
		if button_rect(index).has_point(event.position):state.step(1 if index==1 else -1);accept_event();return
func caption(value: String,point: Vector2,color: Color) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
func _draw() -> void:
	if state==null or state.snapshot.is_empty():return
	if not state.snapshot.manager_available:
		caption("A manager is required to add work orders to the shop.",Vector2(0,22),colors[12] if colors.size()>12 else Color.WHITE)
	caption("General work orders allowed: "+str(state.snapshot.general_order_limit),Vector2(0,size.y-14),Color.WHITE)
	for index in 3:
		var texture: Texture2D=art.texture(["WORK_ORDERS_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"][index])
		if texture!=null:draw_texture_rect(texture,button_rect(index),false)
