extends Control
# Native Items rows: owned semantic text/targets; local drawing and navigation.
signal inspect_requested(kind: int,id: int)
const NativeText=preload("res://scripts/native_creature_text.gd")
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var world
var rows: Array=[]
var icons: Array=[]
var first:=0
var input_allowed: Callable
var scrollbar=preload("res://scripts/reports_scrollbar.gd").new()

func fact(row: Dictionary,key: String,fallback=null):
	for value in row.get("facts",[]):
		if value.key==key:return value.number if value.has_number else value.text
	return fallback
func configure(source,records: Array) -> void:
	world=source;rows=records;art.configure(source);picture.configure(source);theme=art.theme
	NativeText.load_text(source);texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	scrollbar.configure(source);scrollbar.use_standalone_sheet=false;add_child(scrollbar)
	scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	for row in rows:
		var kind:=int(fact(row,"row_kind",0));var target:=int(row.get("related_id",-1))
		icons.append(world.selection_icon(1 if kind==2 else 2,target) if target>=0 and kind!=3 else null)
	resized.connect(layout);layout()
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func capacity() -> int:return maxi(0,int(size.y/36))
func layout() -> void:
	first=clampi(first,0,maxi(0,rows.size()-capacity()))
	scrollbar.position=Vector2(size.x-24,0);scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.count=rows.size();scrollbar.page=capacity();scrollbar.first=first
	scrollbar.visible=capacity()>0 and rows.size()>capacity();scrollbar.queue_redraw();queue_redraw()
func inspect_rect(index: int) -> Rect2:
	return Rect2(size.x-(48 if scrollbar.visible else 32),(index-first)*36,24,36)
func patch(texture: Texture2D,origin: Vector2,columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _draw() -> void:
	if world==null or theme.default_font==null:return
	var width:=size.x-(32 if scrollbar.visible else 16)
	for index in range(first,mini(rows.size(),first+capacity())):
		var row: Dictionary=rows[index];var kind:=int(fact(row,"row_kind",0))
		var top:=Vector2(8,(index-first)*36)
		patch(art.texture("BUTTON_RECTANGLE"),top,int(width/8))
		if kind!=3:
			patch(picture.texture(false),top,5)
			if icons[index]!=null:draw_texture_rect(icons[index],Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var columns:=maxi(0,int(width/8)-14-(1 if kind==2 else 0))
		var caption:=str(row.get("name",""));var role:=str(fact(row,"native_role",""))
		if caption.length()>=columns:caption=caption.left(maxi(0,columns-4))+"..." if columns>4 else caption.left(maxi(0,columns-1))
		if role.length()>=columns:role=role.left(maxi(0,columns-4))+"..." if columns>4 else role.left(maxi(0,columns-1))
		var color: Color=NativeText.colors[15 if kind==3 else 10 if kind==2 else 14]
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(56+(8 if kind==2 else 0),24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,36),role,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[11])
		if kind!=3 and int(row.get("related_id",-1))>=0:
			var texture: Texture2D=art.texture("STOCKS_VIEW_ITEM")
			if texture!=null:draw_texture_rect(texture,inspect_rect(index),false)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var index:=first+floori(event.position.y/36)
	if index<first or index>=mini(rows.size(),first+capacity()) or not inspect_rect(index).has_point(event.position):return
	var row: Dictionary=rows[index];var kind:=int(fact(row,"row_kind",0));var target:=int(row.get("related_id",-1))
	if kind!=3 and target>=0:
		accept_event()
		inspect_requested.emit(1 if kind==2 else 2,target)
