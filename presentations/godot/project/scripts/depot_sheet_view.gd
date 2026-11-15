extends "res://scripts/well_sheet_view.gd"
# Staged native depot body. Goods/trade navigation must be connected before exposure.
signal goods_requested
signal trade_requested
signal broker_requested(id: int)
const MODES=["Broker requested at depot","Anyone requested at depot","No trader needed at depot"]
var broker_recipe: Dictionary={}
var broker_texture: Texture2D
func refresh() -> void:
	super.refresh()
	var recipe: Dictionary=state.snapshot.get("depot",{}).get("broker_appearance",{})
	if recipe!=broker_recipe:
		broker_recipe=recipe.duplicate(true)
		broker_texture=null if recipe.is_empty() else native_header_source.candidate_icon(recipe)
func mode_top() -> int:
	var body: Dictionary=state.snapshot.get("depot",{})
	return 96+36*maxi(1,int(body.get("goods_available",false))+int(body.get("trade_available",false)))+24
func mode_rect(index: int) -> Rect2:return Rect2(16,mode_top()+36*index,224,36)
func broker_rect() -> Rect2:return Rect2(16,mode_top()+144,size.x-32,36)
func _patch(texture: Texture2D,rect: Rect2) -> void:
	if texture==null:return
	var columns:=int(rect.size.x/8)
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _gui_input(event: InputEvent) -> void:
	if not removing and state.snapshot.get("type",-1)==6 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for index in 3:
			if mode_rect(index).has_point(event.position):state.set_depot_mode(index);accept_event();return
		var body: Dictionary=state.snapshot.depot
		var top:=96
		if body.goods_available:
			if Rect2(16,top,216,36).has_point(event.position):goods_requested.emit();accept_event();return
			top+=36
		if body.trade_available and Rect2(16,top,112,36).has_point(event.position):trade_requested.emit();accept_event();return
		if body.broker_id>=0 and broker_rect().has_point(event.position):broker_requested.emit(body.broker_id);accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.get("type",-1)!=6 or colors.size()!=16 or theme.default_font==null:return
	var body: Dictionary=state.snapshot.get("depot",{})
	if body.is_empty():return
	var top:=96
	if body.goods_available:
		_patch(art.texture("HORIZONTAL_OPTION_ACTIVE"),Rect2(16,top,216,36))
		_body_text("Move goods to/from depot",Vector2(32,top+24),7)
		if body.awaiting_items>0:_body_text("Awaiting "+str(body.awaiting_items)+(" item" if body.awaiting_items==1 else " items"),Vector2(272,top+24),14)
		top+=36
	if body.trade_available:
		_patch(art.texture("HORIZONTAL_OPTION_ACTIVE"),Rect2(16,top,112,36))
		_body_text("Trade",Vector2(32,top+24),7)
	if not body.goods_available and not body.trade_available:_body_text("There are no merchants trading right now.",Vector2(16,108))
	for index in 3:
		var rect:=mode_rect(index)
		var selected: bool=(not body.requested) if index==2 else (body.requested and body.anyone==(index==1))
		_patch(art.texture("HORIZONTAL_OPTION_ACTIVE" if selected else "HORIZONTAL_OPTION_INACTIVE"),rect)
		_body_text(MODES[index],rect.position+Vector2(16,24),10 if selected else 7)
	var rect:=broker_rect()
	if body.broker_id<0:
		_body_text("You do not have a broker.",rect.position+Vector2(0,24));return
	_patch(art.texture("BUTTON_RECTANGLE"),rect)
	_patch(picture.texture(false,false),Rect2(rect.position,Vector2(40,36)))
	if broker_texture!=null:draw_texture_rect(broker_texture,Rect2(rect.position+Vector2(2,2),Vector2(32,32)),false)
	var name: String=body.broker_name
	var limit:=int(size.x/8)-17
	if name.length()>=limit:name=name.left(limit-1);name=name.left(maxi(0,name.length()-3))+"..." if name.length()>3 else name
	_body_text("Broker: "+name,rect.position+Vector2(40,12))
	_body_text(body.activity,rect.position+Vector2(40,24),body.foreground+(8 if body.bright else 0))
	_body_text("Broker can access depot" if body.accessible else "Broker cannot access depot",rect.position+Vector2(40,36),10 if body.accessible else 12)
