extends Control
# Native Link prompt (DF53.16 renderer150a05..151249). The owner supplies
# current item snapshots and native building name; this view has no commands.
signal cancelled
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var world
var state
var building_name:=""
var items: Dictionary={}
var icons: Dictionary={}
var colors: Array[Color]=[]
var panel: StyleBox

func configure(source,model,native_name: String) -> void:
	world=source;state=model;building_name=native_name
	art.configure(source);picture.configure(source);theme=art.theme;panel=art.native_message_panel()
	colors=art.installed_palette(source.assets_root())
	size=Vector2(456,156);texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(refresh);refresh()
func set_items(snapshots: Array) -> void:
	items.clear();icons.clear()
	for value in snapshots:items[int(value.id)]=value.duplicate(true)
	refresh()
func refresh() -> void:
	if state==null:return
	for key in ["source_mechanism","target_mechanism"]:
		var id: int=state.snapshot.get(key,-1)
		var value: Dictionary=items.get(id,{})
		if not value.is_empty() and value.has("appearance"):
			icons[id]=world.item_sheet_icon(value.item_type,value.appearance,id)
	queue_redraw()
func ready_art() -> bool:
	return state!=null and icons.get(state.snapshot.get("source_mechanism",-1))!=null and icons.get(state.snapshot.get("target_mechanism",-1))!=null
func _patch(texture: Texture2D,origin: Vector2,columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _draw() -> void:
	if state==null or state.snapshot.is_empty() or panel==null:return
	draw_style_box(panel,Rect2(Vector2.ZERO,size))
	var font: Font=theme.default_font
	if font==null or colors.size()!=16:return
	font.draw_string(get_canvas_item(),Vector2(16,36),"Click a building to link to "+building_name+".",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[15])
	for index in 2:
		var top:=Vector2(16,72+index*36)
		_patch(art.texture("BUTTON_RECTANGLE"),top,53)
		_patch(picture.texture(false),top,5)
		var id: int=state.snapshot.get("source_mechanism" if index==0 else "target_mechanism",-1)
		var icon: Texture2D=icons.get(id)
		if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		font.draw_string(get_canvas_item(),Vector2(64,96+index*36),state.snapshot.get("source_name" if index==0 else "target_name",""),HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[15])
		font.draw_string(get_canvas_item(),Vector2(64,108+index*36),"will be installed at "+(building_name if index==0 else "target"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[7])
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		cancelled.emit();accept_event()
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
