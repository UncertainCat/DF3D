extends Control
# Composite native Trade surface; public depot exposure remains gated separately.
signal cancelled
var world
var state
var input_allowed: Callable
var art=preload("res://scripts/original_ui.gd").new()
var catalog=preload("res://scripts/trade_catalog_view.gd").new()
var goods=preload("res://scripts/trade_goods_view.gd").new()
var header=preload("res://scripts/trade_header_view.gd").new()
var footer=preload("res://scripts/trade_footer_view.gd").new()
var actions=preload("res://scripts/trade_action_view.gd").new()
var frame:=Control.new()
var viewport_size:=Vector2(1200,800)
func configure_trade(source,model) -> void:
	world=source;state=model;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(catalog);catalog.configure_catalog(source,model);catalog.input_allowed=allowed
	catalog.cancelled.connect(func():cancelled.emit())
	add_child(frame);frame.mouse_filter=Control.MOUSE_FILTER_STOP;frame.draw.connect(_draw_frame)
	frame.add_child(header);header.configure_header(source)
	frame.add_child(goods);goods.configure_goods(source,model);goods.input_allowed=allowed
	goods.cancelled.connect(func():cancelled.emit())
	frame.add_child(footer);footer.configure_footer(source,model);footer.input_allowed=allowed
	frame.add_child(actions);actions.configure_actions(source,model);actions.input_allowed=allowed
	state.changed.connect(refresh);layout(viewport_size)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func layout(view: Vector2) -> void:
	viewport_size=view;size=view
	catalog.layout(view)
	frame.position=Vector2(32,48+floorf(fposmod(view.y,12)*0.5))
	frame.size=Vector2((floori(view.x/8)-32)*8,maxi(13,floori(view.y/12)-7)*12)
	header.position=Vector2(8,12);header.layout(frame.size)
	goods.position=Vector2(16,96);goods.layout(frame.size)
	footer.position=Vector2(16,frame.size.y-84);footer.layout(frame.size)
	actions.position=Vector2(16,frame.size.y-48);actions.layout(frame.size)
	refresh()
func refresh() -> void:
	if state==null:return
	catalog.visible=state.phase==state.Phase.Ready
	frame.visible=not catalog.visible and state.phase!=state.Phase.Closed
	if header.facts!=state.header:header.set_header(state.header)
	if actions.actions!=state.actions:actions.set_actions(state.actions)
	frame.queue_redraw()
func _draw_frame() -> void:
	var texture: Texture2D=art.texture("HOVER_RECTANGLE")
	if texture==null:return
	frame.draw_rect(Rect2(Vector2(4,4),frame.size-Vector2(8,8)),Color8(28,28,28))
	var columns:=int(frame.size.x/8);var rows:=int(frame.size.y/12)
	for y in rows:
		for x in columns:frame.draw_texture_rect_region(texture,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else 24 if y==rows-1 else 12,8,12))
	for y in [84,int(frame.size.y)-96]:
		for x in range(1,columns-1):frame.draw_texture_rect_region(texture,Rect2(x*8,y,8,12),Rect2(8,0,8,12))
	for y in range(96,int(frame.size.y)-96,12):frame.draw_texture_rect_region(texture,Rect2(floori(frame.size.x/16)*8,y,8,12),Rect2(0,12,8,12))
func _input(event: InputEvent) -> void:
	if not allowed() or catalog.visible or goods.allowed():return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		state.close();cancelled.emit();get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
