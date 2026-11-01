extends Control
const State=preload("res://scripts/creature_expel_state.gd")
const NameColor=preload("res://scripts/native_name_color.gd")
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var state
var world
var input_allowed: Callable
var rows: Array=[]
var colors: Array=[]
var first:=0
var retired:=false
var scrollbar=preload("res://scripts/reports_scrollbar.gd").new()

func configure(source,model) -> void:
	world=source;state=model;art.configure(world);picture.configure(world);theme=art.theme
	preload("res://scripts/native_creature_text.gd").load_text(world)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(refresh);resized.connect(refresh)
	scrollbar.use_standalone_sheet=false
	scrollbar.configure(source);scrollbar.input_allowed=func():return _allowed() and state.phase in [State.Phase.Choosing,State.Phase.Confirming]
	scrollbar.row_changed.connect(func(value):first=value;refresh())
	refresh()
func _allowed() -> bool:
	return not retired and (not input_allowed.is_valid() or input_allowed.call())
func _exit_tree() -> void:
	retired=true
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
	if is_instance_valid(scrollbar) and scrollbar.get_parent()==null:scrollbar.free()
func label(text: String,position_: Vector2,width: float,color:=Color.WHITE) -> Label:
	var value:=Label.new();value.text=text;value.position=position_;value.size=Vector2(width,12)
	value.add_theme_font_size_override("font_size",12);value.add_theme_color_override("font_color",color)
	value.mouse_filter=Control.MOUSE_FILTER_IGNORE;value.clip_text=true;add_child(value);return value
func style(token: String) -> StyleBoxTexture:
	var value:=art.make_style(token,8)
	value.set_texture_margin(SIDE_TOP,12);value.set_texture_margin(SIDE_BOTTOM,12)
	value.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:value.set_content_margin(side,0)
	return value
func button(text: String,rect: Rect2,token: String,action: Callable) -> Button:
	var value:=Button.new();value.text=text;value.position=rect.position;value.size=rect.size
	value.focus_mode=Control.FOCUS_NONE;value.add_theme_font_size_override("font_size",12)
	for key in ["normal","hover","pressed","disabled","focus"]:value.add_theme_stylebox_override(key,style(token))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]:value.add_theme_color_override(key,Color.WHITE)
	value.pressed.connect(func():if _allowed():action.call())
	add_child(value);value.size=rect.size;return value
func refresh() -> void:
	if world==null or retired:return
	if scrollbar.get_parent()==self:remove_child(scrollbar)
	for child in get_children():remove_child(child);child.queue_free()
	rows.clear();colors.clear()
	var snapshot: Dictionary=state.snapshot()
	if state.phase==State.Phase.Refused:
		# Preserve the recorded native refusal-renderer bug pending approval.
		var yellow: Color=preload("res://scripts/native_creature_text.gd").colors[14]
		label("Cannot expel or send away:",Vector2(8,0),size.x-24,yellow)
		label("Nobility",Vector2(8,24),size.x-24,yellow);return
	if state.phase not in [State.Phase.Choosing,State.Phase.Confirming,State.Phase.Applying]:return
	var choosing: bool=state.phase==State.Phase.Choosing
	rows=snapshot.get("destinations",[]) if choosing else snapshot.get("units",[])
	var capacity:=maxi(0,int((size.y-(0 if choosing else 36))/36))
	var overflow:=capacity>0 and rows.size()>capacity
	var row_width:=size.x-(32 if overflow else 16)
	first=clampi(first,0,maxi(0,rows.size()-capacity))
	for index in range(first,mini(rows.size(),first+capacity)):
		var row: Dictionary=rows[index];var y: int=(index-first)*36
		var background:=Panel.new();background.position=Vector2(8,y);background.size=Vector2(row_width,36)
		background.add_theme_stylebox_override("panel",style("BUTTON_RECTANGLE"));background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
		if choosing:
			var id: int=row.id
			var hit:=button("",Rect2(8,y,row_width,36),"BUTTON_RECTANGLE",func():first=0;state.choose(id))
			hit.name="Destination_"+str(id)
			label("Expel" if id==-1 else "Send to "+str(row.name),Vector2(8,y+12),row_width)
		else:
			var frame:=Panel.new();frame.position=Vector2(8,y);frame.size=Vector2(40,36)
			var frame_style:=style("BUTTON_PICTURE_BOX");frame_style.texture=picture.texture(false)
			frame.add_theme_stylebox_override("panel",frame_style);frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(frame)
			var icon:=TextureRect.new();icon.position=Vector2(10,y+2);icon.size=Vector2(32,32)
			icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_SCALE
			icon.texture=world.candidate_icon(row.sheet_icon);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(icon)
			var name:=str(row.name);var columns:=maxi(0,int(size.x/8)-15)
			if name.length()>columns:name=name.left(columns-3)+"..." if columns>3 else name.left(columns)
			colors.append({"label":label(name,Vector2(64,y+12),size.x-80),"color":row.name_color})
	if not choosing:
		var accept:=button("Expel" if state.destination_id==-1 else "Send away",Rect2(8,size.y-36,88,36),"HORIZONTAL_OPTION_CONFIRM",state.confirm)
		accept.name="ConfirmExpel";accept.disabled=state.phase!=State.Phase.Confirming
		button("Cancel",Rect2(size.x-72,size.y-36,64,36),"HORIZONTAL_OPTION_REMOVE",state.close).name="CancelExpel"
	if overflow:
		add_child(scrollbar);scrollbar.position=Vector2(size.x-24,0);scrollbar.size=Vector2(16,capacity*36)
		scrollbar.count=rows.size();scrollbar.page=capacity;scrollbar.first=first;scrollbar.queue_redraw()
	_process(0)
func _process(_delta: float) -> void:
	for row in colors:
		var color:=NameColor.choose(row.color,Time.get_ticks_msec(),randi_range(0,1))
		if not color.is_empty():row.label.add_theme_color_override("font_color",preload("res://scripts/native_creature_text.gd").colors[color[0]+8*color[2]])
