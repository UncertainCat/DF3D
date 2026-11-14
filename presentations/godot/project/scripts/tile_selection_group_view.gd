extends Control
# Staged item-group body. Candidate order/captions belong to the bridge;
# images resolve through the world API from owned semantic appearance data.
const C=preload("res://scripts/management_contract.gd")
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var state
var world
var rows: Array=[]
var icons: Dictionary={}
var receipt:=0
var first:=0
var capacity:=18
var scrollbar
var input_allowed: Callable

func configure(source,model) -> void:
	world=source;state=model;art.configure(source);picture.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(scrollbar);scrollbar.configure(source)
	scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	state.changed.connect(refresh);layout(708);refresh()

func layout(sheet_height: float) -> void:
	position=Vector2(8,48);capacity=maxi(0,floori((sheet_height-60)/36))
	size=Vector2(472,capacity*36)
	scrollbar.position=Vector2(456,0);scrollbar.size=Vector2(16,size.y);scrollbar.page=capacity
	first=clampi(first,0,maxi(0,rows.size()-capacity))
	scrollbar.set_rows(rows.size(),first);scrollbar.visible=capacity>0 and rows.size()>capacity
	queue_redraw()

func allowed() -> bool:
	return capacity>0 and state.phase==state.Phase.Ready and state.ticket==0 and (not input_allowed.is_valid() or input_allowed.call())

func refresh() -> void:
	var next: int=state.snapshot.get("receipt",0)
	if receipt!=next:first=0;icons.clear();receipt=next
	rows=state.snapshot.get("members",[]) if state.snapshot.get("kind",0)==C.SelectionKind.ItemList else []
	for row in rows:
		if row.has("appearance") and not icons.has(row.id):icons[row.id]=world.item_sheet_icon(row.item_type,row.appearance,row.id)
	visible=state.snapshot.get("open",false) and state.snapshot.get("kind",0)==C.SelectionKind.ItemList
	first=clampi(first,0,maxi(0,rows.size()-capacity))
	scrollbar.set_rows(rows.size(),first);scrollbar.visible=capacity>0 and rows.size()>capacity
	if not allowed():scrollbar.dragging=false
	queue_redraw()

func set_icons(expected_receipt: int,images: Dictionary) -> void:
	if expected_receipt!=receipt:return
	icons=images.duplicate();queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:return
	if allowed():
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
		elif event.button_index==MOUSE_BUTTON_LEFT:
			var index:=first+floori(event.position.y/36)
			if index>=first and index<mini(rows.size(),first+capacity):state.choose_member(index)
	accept_event()

func patch(texture: Texture2D,top: Vector2,columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:draw_texture_rect_region(texture,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))

func _draw() -> void:
	var columns:=57 if rows.size()>capacity else 59
	for offset in mini(capacity,rows.size()-first):
		var row: Dictionary=rows[first+offset];var top:=Vector2(0,offset*36)
		patch(art.texture("BUTTON_RECTANGLE"),top,columns);patch(picture.texture(false),top,5)
		var icon: Texture2D=icons.get(row.id)
		if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var caption: String=row.name
		if caption.length()>=columns-15:caption=caption.left(columns-19)+"..."
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
