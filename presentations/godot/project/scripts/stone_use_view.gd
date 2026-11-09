extends "res://scripts/standing_orders_view.gd"
# Native default layout: native_stone_use.json. Staged until rendered input,
# responsive layout, hover and Labor ownership have independent acceptance.
signal standing_requested
var icons: Dictionary={}
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
func configure_stone_use(source,model) -> void:
	configure_standing_orders(source,model);picture.configure(source)
	scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(value):state.seek(value,capacity()))
	state.changed.connect(refresh);refresh()
func rows_top() -> int:return list_top()+24
func capacity() -> int:return maxi(0,int((size.y-rows_top()-24)/36))
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:refresh()
func category_rect(index: int) -> Rect2:return Rect2(8+index*144,list_top()-36,144 if index==0 else 120,24)
func restriction_rect(index: int) -> Rect2:return Rect2(size.x-72,rows_top()+index*36,32,36)
func refresh() -> void:
	var values: Array=state.category_rows();var retained: Dictionary={}
	for index in range(state.first[state.category],mini(values.size(),state.first[state.category]+capacity())):
		var token: String=values[index].material_token
		retained[token]=icons.get(token)
		if retained[token]==null:retained[token]=world.item_sheet_icon(4,{"material_token":token,"subtype_raw":"","color_token":"","stack":1,"flags":0},-1)
	icons=retained
	scrollbar.position=Vector2(size.x-32,rows_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(values.size(),state.first[state.category])
	queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if work_details_rect().has_point(event.position):work_details_requested.emit();return
	if Rect2(136,list_top()-60,152,24).has_point(event.position):standing_requested.emit();return
	if kitchen_rect().has_point(event.position):kitchen_requested.emit();return
	for kind in 2:
		if category_rect(kind).has_point(event.position):state.select_category(kind);return
	var values: Array=state.category_rows()
	for index in mini(capacity(),values.size()-state.first[state.category]):
		if restriction_rect(index).has_point(event.position):state.toggle(int(values[state.first[state.category]+index].index));return
func shortened(value: String,cells: int) -> String:
	return value if value.length()<=cells else value.left(maxi(0,cells-3))+"..."
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Labor")
	var x:=8.0
	for caption in ["Work Details","Standing orders","Kitchen","Stone use"]:x+=tab(caption,Vector2(x,list_top()-60),"SHORT_SUBTAB",caption=="Stone use")
	x=8.0
	for kind in 2:x+=tab(["Economic stone","Other stone"][kind],Vector2(x,list_top()-36),"SHORT_SUBSUBTAB",state.category==kind)
	text("Stone type",Vector2(16,list_top()+12));text("Magma-safe",Vector2(216,list_top()+12))
	text("Economic uses",Vector2(312,list_top()+12))
	text("Select to use in non-economic jobs.",Vector2(size.x-328,list_top()+12))
	var values: Array=state.category_rows()
	for index in mini(capacity(),values.size()-state.first[state.category]):
		var row: Dictionary=values[state.first[state.category]+index];var y:=rows_top()+index*36
		patch("BUTTON_RECTANGLE",Vector2i(2,int(y/12)),int(size.x/8)-6,3)
		patch("",Vector2i(2,int(y/12)),5,3,picture.texture(false))
		var icon: Texture2D=icons.get(row.material_token)
		if icon!=null:draw_texture_rect(icon,Rect2(18,y+2,32,32),false)
		text(shortened(row.name,17),Vector2(72,y+24))
		var safety: Texture2D=art.texture("LABOR_STONE_USE_MAGMA_"+("SAFE" if row.magma_safe else "UNSAFE"))
		draw_rect(Rect2(240,y,32,36),Color.BLACK)
		if safety!=null:draw_texture_rect(safety,Rect2(240,y,32,36),false)
		if state.category==0:text(shortened(row.uses,maxi(0,int((size.x-392)/8))),Vector2(312,y+24))
		var permission: Texture2D=art.texture("LABOR_STONE_USE_"+("RESTRICTED" if row.restricted else "ALLOWED"))
		if permission!=null:draw_texture_rect(permission,restriction_rect(index),false)
