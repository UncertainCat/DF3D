extends Control
# Native item-sheet contents (157872..1589c3), fed only by owned snapshot rows.
signal child_requested(kind: int,id: int)
signal child_flag_requested(id: int,operation: int,value: bool)
const MASKS=[0x80000,0x200000,0x800000,0x1000000]
const ART=["STOCKS_FORBID","STOCKS_DUMP","STOCKS_MELT","STOCKS_HIDE"]
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var world
var rows: Array=[]
var icons: Dictionary={}
var scrollbar
var page:=0
var input_allowed: Callable
var owner_id: int=-1
func configure(source) -> void:
	world=source;art.configure(source);picture.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(scrollbar);scrollbar.configure(source)
	scrollbar.wheel_enabled=false;scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(_first):_refresh_icons();queue_redraw())
func allowed() -> bool:return page>0 and (not input_allowed.is_valid() or input_allowed.call())
func present(id: int,value: Array,extent: Vector2) -> void:
	var reset:=id!=owner_id;owner_id=id;rows=value.duplicate(true);size=extent
	page=maxi(0,floori(size.y/36));size.y=page*36
	scrollbar.position=Vector2(size.x-16,0);scrollbar.size=Vector2(16,size.y);scrollbar.page=page*3
	if reset:scrollbar.dragging=false
	scrollbar.set_rows(rows.size()*3,0 if reset else scrollbar.first)
	scrollbar.visible=page>0 and rows.size()>page
	if not allowed():scrollbar.dragging=false
	_refresh_icons();queue_redraw()
func _refresh_icons() -> void:
	icons.clear()
	for index in range(first_row(),mini(rows.size(),first_row()+page+1)):
		var row: Dictionary=rows[index]
		if row.kind==1:icons[index]=world.item_sheet_icon(row.item_type,row.appearance,int(row.id))
		elif world.has_method("selection_icon"):icons[index]=world.selection_icon(1,int(row.id),true)
func first_row() -> int:return scrollbar.first/3
func offset() -> int:return scrollbar.first%3*12
func controls_offset() -> int:return 0 if scrollbar.visible else 16
func control_rect(index: int,control: int) -> Rect2:return Rect2(296+controls_offset()+control*24,(index-first_row())*36-offset(),24,36)
func eligible(row: Dictionary,control: int) -> bool:
	return row.kind==1 and (control!=0 or bool(row.flags&2)) and (control!=3 or row.can_dump) and (control!=4 or row.can_melt)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(scrollbar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var index:=first_row()+floori((event.position.y+offset())/36)
	if index<0 or index>=rows.size():return
	var row: Dictionary=rows[index]
	for control in range(1,6):
		if eligible(row,control) and control_rect(index,control).has_point(event.position):
			if control==1:child_requested.emit(row.kind,row.id)
			else:child_flag_requested.emit(row.id,control-2,not bool(row.flags&MASKS[control-2]))
			accept_event();return
func patch(texture: Texture2D,origin: Vector2,columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _draw() -> void:
	for index in range(first_row(),mini(rows.size(),first_row()+page+1)):
		var row: Dictionary=rows[index];var top:=Vector2(0,(index-first_row())*36-offset())
		patch(art.texture("BUTTON_RECTANGLE"),top,57+controls_offset()/8)
		patch(picture.texture(false),top,5)
		var icon: Texture2D=icons.get(index)
		if icon!=null and top.y>=0 and top.y+36<=size.y:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var reserved:=3 if row.kind==1 and row.flags&0x22 else 0
		var caption: String=row.caption
		if caption.length()>=34+controls_offset()/8-reserved:caption=caption.left(30+controls_offset()/8-reserved)+"..."
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),top+Vector2(48,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		for control in 6:
			if not eligible(row,control):continue
			var token: String="BUILDING_ITEM_TASK" if control==0 else "STOCKS_VIEW_ITEM" if control==1 else ART[control-2]+("_ACTIVE" if row.flags&MASKS[control-2] else "")
			var texture: Texture2D=art.texture(token)
			if texture!=null:draw_texture_rect(texture,control_rect(index,control),false)
