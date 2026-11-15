extends Control
# Staged native farm contents. View hands item identity to the independent sheet owner.
signal view_requested(item_id: int)
const C=preload("res://scripts/management_contract.gd")
const ACTIONS=[C.FarmOperation.ItemForbid,C.FarmOperation.ItemDump,C.FarmOperation.ItemMelt,C.FarmOperation.ItemHidden]
const FLAGS=["forbid","dump","melt","hidden"]
const ART=["STOCKS_FORBID","STOCKS_DUMP","STOCKS_MELT","STOCKS_HIDE"]
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var state
var world
var scrollbar
var rows: Array=[]
var icons: Dictionary={}
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO
var page:=6
var cell_first:=0
var input_allowed: Callable
var inspect_removing:=false
var building_type: int=-1

func configure(source,model,help=null) -> void:
	hover_help=help
	mouse_exited.connect(_leave_hover)
	visibility_changed.connect(func():if not is_visible_in_tree():_leave_hover())
	world=source;state=model;art.configure(source);picture.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(scrollbar);scrollbar.configure(source)
	scrollbar.input_allowed=can_scroll
	scrollbar.row_changed.connect(_scroll_to_cell)
	state.changed.connect(refresh);set_capacity(6)

func set_capacity(value: int) -> void:
	if page==maxi(0,value) and size==Vector2(472,maxi(0,value)*36):return
	page=maxi(0,value);size=Vector2(472,page*36)
	scrollbar.position=Vector2(456,0);scrollbar.size=Vector2(16,page*36);scrollbar.page=page*3
	refresh()

func _scroll_to_cell(value: int) -> void:
	cell_first=value
	var cursor:=floori(cell_first/3.0)
	if cursor!=int(state.snapshot.get("cursor",0)):state.seek(cursor)
	else:refresh()

func row_offset() -> int:return (cell_first%3)*12
func visible_count() -> int:return mini(page+(1 if row_offset()>0 else 0),rows.size())

func permitted() -> bool:return not input_allowed.is_valid() or input_allowed.call()
func available() -> bool:
	return permitted() and page>0 and state!=null and state.phase==state.Phase.Ready and state.ticket==0 and not state.snapshot.is_empty() and (state.snapshot.completed or state.edit_unfinished) and (not state.snapshot.removing or inspect_removing)
func can_scroll() -> bool:
	return permitted() and page>0 and state!=null and state.phase in [state.Phase.Ready,state.Phase.Reading] and not state.snapshot.is_empty()

func refresh() -> void:
	rows=[];icons.clear()
	if state==null:return
	rows=state.rows()
	var cursor:=int(state.snapshot.get("cursor",0))
	if state.snapshot.is_empty() or (state.phase!=state.Phase.Reading and floori(cell_first/3.0)!=cursor):cell_first=cursor*3
	if state.phase==state.Phase.Reading and floori(cell_first/3.0)!=cursor:rows=[]
	for row in rows.slice(0,visible_count()):
		# Native planted seeds and delivered fertilizer use original page colors.
		var material: PackedStringArray=String(row.material_token).split(":")
		if row.item_type==53 and material.size()==3 and material[0]=="PLANT" and material[2]=="SEED":
			icons[row.id]=world.farm_seed_icon(material[1])
		elif row.item_type==0 and row.material_token=="POTASH":icons[row.id]=world.farm_potash_icon()
		elif row.has("appearance"):icons[row.id]=world.item_sheet_icon(row.item_type,row.appearance,int(row.id))
	scrollbar.set_rows(int(state.snapshot.get("total",0))*3,cell_first)
	scrollbar.visible=page>0 and int(state.snapshot.get("total",0))>page
	if not can_scroll():scrollbar.dragging=false
	queue_redraw()

func controls_offset() -> int:return 0 if int(state.snapshot.get("total",0))>page else 16

func control_rect(index: int,control: int) -> Rect2:return Rect2(296+controls_offset()+control*24,index*36-row_offset(),24,36)
func eligible(row: Dictionary,control: int) -> bool:
	return (control!=3 or row.can_dump) and (control!=4 or row.can_melt)

func _leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())

func help_at(point: Vector2) -> String:
	var index:=floori((point.y+row_offset())/36)
	if index<0 or index>=visible_count():return ""
	var row: Dictionary=rows[index]
	for control in 6:
		if not control_rect(index,control).has_point(point) or not eligible(row,control):continue
		if control==0:
			if row.in_job:return "task"
			if row.in_building:return "permanent" if row.role==2 else "resting" if building_type==3 else "other"
			return ""
		return ["view","forbid","dump","melt","visibility"][control-1]
	return ""

func _process(_delta: float) -> void:
	if not is_instance_valid(hover_help):return
	if pointer_known and is_visible_in_tree() and available():
		var kind:=help_at(pointer_position)
		if not kind.is_empty():hover_help.enter_contents(get_instance_id(),kind);return
	hover_help.leave(get_instance_id())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:pointer_known=true;pointer_position=event.position;_process(0)
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if can_scroll():scrollbar.move_to(scrollbar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
		accept_event();return
	if not available() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	var index:=floori((event.position.y+row_offset())/36)
	if index<0 or index>=visible_count():return
	var row: Dictionary=rows[index]
	for control in range(1,6):
		if not control_rect(index,control).has_point(event.position) or not eligible(row,control):continue
		if control==1:view_requested.emit(row.id)
		else:state.set_flag(row.id,ACTIONS[control-2],not row[FLAGS[control-2]])
		accept_event();return

func patch(texture: Texture2D,origin: Vector2,columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))

func _draw() -> void:
	if state==null or state.snapshot.is_empty():return
	for index in visible_count():
		var row: Dictionary=rows[index];var top:=Vector2(0,index*36-row_offset())
		patch(art.texture("BUTTON_RECTANGLE"),top,57+controls_offset()/8)
		patch(picture.texture(false),top,5)
		var icon: Texture2D=icons.get(row.id)
		if icon!=null and top.y>=0 and top.y+36<=size.y:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var reserved:=3 if row.in_job or row.in_building else 0
		var name: String=row.name
		if name.length()>=34+controls_offset()/8-reserved:name=name.left(30+controls_offset()/8-reserved)+"..."
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,24),name,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		# Native19db25..19dcb6 selects the temporary-content indicator by
		# building type after task/PERM precedence; Coffin3 uses DEAD.
		var role: String="BUILDING_ITEM_TASK" if row.in_job else ("BUILDING_ITEM_INCORPORATED" if row.role==2 else "BUILDING_ITEM_DEAD" if building_type==3 else "BUILDING_ITEM_OTHER") if row.in_building else ""
		for control in 6:
			if not eligible(row,control):continue
			var token: String=role if control==0 else "STOCKS_VIEW_ITEM" if control==1 else ART[control-2]+("_ACTIVE" if row[FLAGS[control-2]] else "")
			if token.is_empty():continue
			var texture: Texture2D=art.texture(token)
			if texture!=null:draw_texture_rect(texture,control_rect(index,control),false)

func _exit_tree() -> void:
	_leave_hover()
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
