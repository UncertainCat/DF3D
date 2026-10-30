extends Control
# Staged item sheet; native semantic transport/owner must precede public exposure.
signal flag_requested(item_id: int, flag: String, value: bool)
signal holder_requested(building_id: int)
signal camera_requested(item_id: int)
const FLAGS=["forbid","dump","melt","hidden"]
const BUTTONS=["SHORT_FORBID","SHORT_DUMP","SHORT_MELT","SHORT_HIDE"]
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var source
var snapshot: Dictionary={}
var colors: Array[Color]=[]
var icon: Texture2D
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO
var pending:=false
var following:=false
var input_allowed: Callable

func configure(world,help=null) -> void:
	hover_help=help;mouse_exited.connect(_leave_hover)
	source=world;art.configure(world);picture.configure(world);theme=art.theme
	colors=art.installed_palette(world.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	size=Vector2(488,708)

func present(value: Dictionary) -> void:
	if snapshot.get("id",-1)!=value.get("id",-1):_leave_hover()
	snapshot=value.duplicate(true);icon=null
	if not snapshot.is_empty() and snapshot.get("item_type",-1)==53:
		var material: PackedStringArray=snapshot.get("material_token","").split(":")
		if material.size()==3 and material[0]=="PLANT":icon=source.farm_seed_icon(material[1])
	visible=not snapshot.is_empty();queue_redraw()

func set_following(value: bool) -> void:
	following=value;queue_redraw()

func allowed() -> bool:return not pending and not snapshot.is_empty() and (not input_allowed.is_valid() or input_allowed.call())
func flag_rect(index: int) -> Rect2:return Rect2(376+index*24,12,24,24)
func camera_rect() -> Rect2:return Rect2(424,36,32,36)
func holder_rect() -> Rect2:return Rect2(328,180,144,36)
func eligible(index: int) -> bool:
	return index!=1 and index!=2 or snapshot.get("can_dump" if index==1 else "can_melt",false)

func _leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())

func help_at(point: Vector2) -> String:
	if snapshot.is_empty():return ""
	for index in 4:
		if eligible(index) and flag_rect(index).has_point(point):return ["forbid","dump","melt","visibility"][index]
	return "camera" if camera_rect().has_point(point) else ""

func _process(_delta: float) -> void:
	if not is_instance_valid(hover_help):return
	if pointer_known and is_visible_in_tree() and allowed():
		var kind:=help_at(pointer_position)
		if not kind.is_empty():hover_help.enter_item(get_instance_id(),kind);return
	hover_help.leave(get_instance_id())

func _exit_tree() -> void:_leave_hover()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:pointer_known=true;pointer_position=event.position;_process(0)
	if not allowed() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for index in 4:
		if eligible(index) and flag_rect(index).has_point(event.position):
			flag_requested.emit(snapshot.id,FLAGS[index],not snapshot[FLAGS[index]]);accept_event();return
	if camera_rect().has_point(event.position):camera_requested.emit(snapshot.id);accept_event()
	elif snapshot.get("holder_id",-1)>=0 and holder_rect().has_point(event.position):holder_requested.emit(snapshot.holder_id);accept_event()

func patch(texture: Texture2D,rect: Rect2,rows:=3) -> void:
	if texture==null:return
	var columns:=int(rect.size.x/8)
	for y in int(rect.size.y/12):
		for x in columns:
			var sy:=0 if y==0 else rows-1 if y==int(rect.size.y/12)-1 else 1
			draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,sy*12,8,12))

func text_at(value: String,point: Vector2,color:=Color.WHITE) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)

static func description_lines(value: String) -> PackedStringArray:
	# Native item renderer 155565 uses panel column span minus six (54 here).
	# Preserve sentence spacing, but discard spaces at a wrapped line's start.
	var lines: PackedStringArray=[]
	var offset:=0
	while value.length()-offset>54:
		var split:=value.substr(offset,54).rfind(" ")
		if split<=0:split=54
		lines.append(value.substr(offset,split))
		offset+=split
		while offset<value.length() and value.unicode_at(offset)==32:offset+=1
	if offset<value.length():lines.append(value.substr(offset))
	return lines

func _draw() -> void:
	if snapshot.is_empty():return
	patch(art.texture("HOVER_RECTANGLE"),Rect2(Vector2.ZERO,size))
	patch(picture.texture(false),Rect2(8,12,40,36))
	if icon!=null:draw_texture_rect(icon,Rect2(10,14,32,32),false)
	text_at(snapshot.get("name",""),Vector2(56,36))
	if not snapshot.get("weight","").is_empty():text_at("Weight: "+snapshot.weight,Vector2(56,48),colors[14])
	var lines:=description_lines(snapshot.get("description",""))
	for index in lines.size():text_at(lines[index],Vector2(16,84+index*12))
	for index in 4:
		if not eligible(index):continue
		var texture: Texture2D=art.texture(BUTTONS[index]+("_ACTIVE" if snapshot.get(FLAGS[index],false) else ""))
		if texture!=null:draw_texture_rect(texture,flag_rect(index),false)
	var camera: Texture2D=art.texture("UNIT_SHEET_CAMERA_ACTIVE" if following else "UNIT_SHEET_CAMERA_INACTIVE")
	if camera!=null:draw_texture_rect(camera,camera_rect(),false)
	if snapshot.get("holder_id",-1)>=0:
		var holder: Texture2D=art.texture(snapshot.get("holder_art",""))
		if holder!=null:draw_texture_rect(holder,Rect2(10,182,32,32),false)
		text_at(snapshot.get("holder_name",""),Vector2(56,204))
		patch(art.texture("HORIZONTAL_OPTION_ACTIVE"),holder_rect())
		text_at("View",Vector2(384,204),colors[10])
