extends Control
# Native3891b4..389b1f summary and bulk selection. Exchange actions are owned by
# outer trade screen; this component never submits them.
var world
var state
var input_allowed: Callable
var art=preload("res://scripts/original_ui.gd").new()
var colors: Array[Color]=[]
var columns: Array[Rect2]=[]
var buttons: Array[Rect2]=[]
func configure_footer(source,model) -> void:
	world=source;state=model;art.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root());texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP;state.changed.connect(queue_redraw)
func layout(panel_size: Vector2) -> void:
	size=Vector2(panel_size.x-32,36) # Capacity text draws below without intercepting the action row.
	var left: int=floori(panel_size.x/16)*8-24
	columns=[Rect2(0,0,left,48),Rect2(left+24,0,size.x-left-24,48)]
	buttons=[]
	for column in columns:
		buttons.append(Rect2(column.end.x-232,0,96,36));buttons.append(Rect2(column.end.x-112,0,112,36))
	queue_redraw()
func text(value: String,point: Vector2,color: int) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _draw() -> void:
	if state==null or columns.size()!=2 or colors.size()!=16:return
	draw_rect(Rect2(Vector2.ZERO,Vector2(size.x,36)),Color8(28,28,28))
	if state.footer.is_empty():return
	var texture: Texture2D=art.texture("HORIZONTAL_OPTION_CONFIRM")
	for index in buttons.size():
		var rect: Rect2=buttons[index];var width: int=int(rect.size.x/8)
		if texture!=null:
			for y in 3:
				for x in width:draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==width-1 else 8,y*12,8,12))
	var f: Dictionary=state.footer
	text(state.entry.get("title",""),Vector2(0,12),15);text(state.entry.get("fortress",""),Vector2(columns[1].position.x,12),15)
	text(f.merchant_value,Vector2(0,24),14);text(f.fortress_value,Vector2(columns[1].position.x,24),14)
	text(f.profit,Vector2(0,36),int(f.profit_color)+8);text(f.capacity,Vector2(0,48),int(f.capacity_color)+8)
	for index in buttons.size():
		var rect: Rect2=buttons[index]
		text("Mark all" if index%2==0 else "Unmark all",rect.position+Vector2(16,24),15)
func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT or state==null or not state.goods_ready():return
	for index in buttons.size():
		if buttons[index].has_point(event.position):state.mark_all(int(index/2),index%2==0);return
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(queue_redraw):state.changed.disconnect(queue_redraw)
