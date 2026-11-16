extends Control
# Native389b7b..38a22d action row. Captions/enablement are owned bridge facts.
var world
var state
var input_allowed: Callable
var art=preload("res://scripts/original_ui.gd").new()
var colors: Array[Color]=[]
var actions: Array=[]
var buttons: Array[Rect2]=[]
var panel_width:=944.0
func configure_actions(source,model) -> void:
	world=source;state=model;art.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root());texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
func set_actions(value: Array) -> void:
	actions=value.duplicate(true);layout(Vector2(panel_width,0))
func layout(panel_size: Vector2) -> void:
	panel_width=panel_size.x;size=Vector2(panel_size.x-32,36);buttons=[]
	var center: int=floori(panel_size.x/16)*8-16
	for action in actions:
		var cells: int=String(action.caption).length()+6
		var x: int=center-240 if action.kind==0 else center+160 if action.kind==2 else center-int(cells/2)*8
		buttons.append(Rect2(x,0,cells*8,36))
	queue_redraw()
func _draw() -> void:
	if colors.size()!=16:return
	draw_rect(Rect2(Vector2(216,0),Vector2(maxf(0,size.x-216),size.y)),Color8(28,28,28))
	for index in actions.size():
		var action: Dictionary=actions[index];var rect: Rect2=buttons[index]
		var texture: Texture2D=art.texture("HORIZONTAL_OPTION_CONFIRM" if action.enabled else "HORIZONTAL_OPTION_ACTIVE")
		if texture!=null:
			for y in 3:
				for x in int(rect.size.x/8):draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==int(rect.size.x/8)-1 else 8,y*12,8,12))
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),rect.position+Vector2(24,24),action.caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[15 if action.enabled else 0])
func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT or state==null or not state.goods_ready():return
	for index in buttons.size():
		if actions[index].enabled and buttons[index].has_point(event.position):
			match int(actions[index].kind):
				0:state.seize()
				1:state.exchange()
				2:state.offer_gift()
			return
