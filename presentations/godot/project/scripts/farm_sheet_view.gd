extends Control
# Staged sheet composition. The owner must connect header actions before exposure.
signal rename_requested
signal removal_requested
signal cancel_removal_requested
signal name_edited(value: String)
signal name_submitted
const SEASONS=["Spring","Summer","Autumn","Winter"]
var art=preload("res://scripts/original_ui.gd").new()
var state
var body
var contents
var title: String=""
var removing:=false
var current_season: int=-1
var target: int=-1
var input_allowed: Callable
var name_entry
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO

func configure(source,model,help=null,contents_model=null) -> void:
	state=model;hover_help=help;art.configure(source);theme=art.theme
	mouse_exited.connect(_leave_hover)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	body=preload("res://scripts/farm_body_view.gd").new();add_child(body);body.configure(source,model)
	body.position=Vector2(16,144);body.input_allowed=body_allowed
	if contents_model!=null:
		contents=preload("res://scripts/farm_contents_view.gd").new();add_child(contents);contents.configure(source,contents_model)
		contents.position=Vector2(8,456);contents.input_allowed=contents_allowed
	name_entry=preload("res://scripts/farm_name_entry.gd").new();add_child(name_entry);name_entry.hide()
	name_entry.edited.connect(func(value):name_edited.emit(value))
	name_entry.submitted.connect(func():name_submitted.emit())
	name_entry.caption_changed.connect(queue_redraw)
	if state.has_method("begin_name_entry"):
		rename_requested.connect(_begin_owned_rename)
		name_edited.connect(state.edit_name_entry)
		name_submitted.connect(_finish_owned_rename)
		removal_requested.connect(state.request_removal)
		cancel_removal_requested.connect(state.cancel_removal)
	state.changed.connect(refresh);refresh()

func allowed() -> bool:return not input_allowed.is_valid() or input_allowed.call()
func body_allowed() -> bool:return allowed() and not removing and (contents==null or contents.state.phase!=contents.state.Phase.Applying)
func contents_allowed() -> bool:return allowed() and not removing and state.phase==state.Phase.Ready and state.ticket==0
func layout(view: Vector2) -> void:
	position=Vector2((floori(view.x/8)-98)*8,48+fposmod(view.y,12)*0.5)
	size=Vector2(488,floori(view.y/12)*12-84)
	if contents!=null:
		contents.set_capacity(maxi(0,floori((size.y-480)/36)) if int(size.y/12)>=45 else 0)
		contents.visible=contents.page>0 and not removing
	queue_redraw()

func refresh() -> void:
	if target!=state.building_id:
		finish_rename();target=state.building_id;current_season=-1
	visible=target>=0
	title=state.snapshot.get("header_name","")
	removing=state.snapshot.get("removing",false)
	body.visible=not removing
	if contents!=null:
		contents.visible=contents.page>0 and not removing
		if not contents_allowed():contents.scrollbar.dragging=false
	if removing:body.scrollbar.dragging=false;finish_rename()
	if state.snapshot.is_empty():finish_rename()
	if not state.snapshot.is_empty():current_season=int(state.snapshot.current_season)
	queue_redraw()

func begin_rename() -> bool:
	if not allowed() or removing or state.phase!=state.Phase.Ready or state.ticket!=0 or state.snapshot.is_empty():return false
	name_entry.begin(state.snapshot.custom_name)
	# The sheet draws the caption on its exact native baseline.
	name_entry.hide();queue_redraw();return true

func finish_rename() -> void:
	if name_entry!=null:name_entry.finish()
	queue_redraw()

func feed_name_key(event: InputEventKey) -> void:
	if allowed() and not removing:name_entry.feed_key(event)

func _begin_owned_rename() -> void:
	if begin_rename() and not state.begin_name_entry():finish_rename()

func _finish_owned_rename() -> void:
	finish_rename();state.finish_name_entry()

func tab_rect(season: int) -> Rect2:return Rect2(8+season*120,60,112 if season==3 else 120,24)
func cancel_rect() -> Rect2:return Rect2(16,132,192,36)

func _leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())

func _process(_delta: float) -> void:
	if not is_instance_valid(hover_help):return
	if pointer_known and is_visible_in_tree() and allowed() and not removing and not state.snapshot.is_empty():
		for entry in [["rename",Rect2(368,12,32,36)],["remove",Rect2(400,12,32,36)]]:
			if entry[1].has_point(pointer_position):hover_help.enter_building(get_instance_id(),entry[0]);return
	hover_help.leave(get_instance_id())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:pointer_known=true;pointer_position=event.position;_process(0)
	if not allowed() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	if removing:
		if state.phase==state.Phase.Ready and state.ticket==0 and cancel_rect().has_point(event.position):cancel_removal_requested.emit();accept_event()
		return
	for season in 4:
		if tab_rect(season).has_point(event.position):state.select_season(season);accept_event();return
	if state.phase!=state.Phase.Ready or state.ticket!=0:return
	if Rect2(368,12,32,36).has_point(event.position):rename_requested.emit();accept_event()
	elif Rect2(400,12,32,36).has_point(event.position):removal_requested.emit();accept_event()

func _draw() -> void:
	var frame: Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null:return
	var lines:=int(size.y/12)
	for y in lines:
		for x in 61:
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 16 if x==60 else 8,0 if y==0 else 24 if y==lines-1 else 12,8,12))
	var border: Texture2D=art.texture("INTERIOR_BORDER_W_E")
	# Native 17f5f2..17f619: bottom (grid rows - 4) minus top (4) >= 44.
	if border!=null and lines>=45:
		for x in range(1,60):draw_texture(border,Vector2(x*8,444))
	var picture: Texture2D=body.picture.texture(false)
	if picture!=null:
		for y in 3:
			for x in 5:draw_texture_rect_region(picture,Rect2(8+x*8,12+y*12,8,12),Rect2(0 if x==0 else 16 if x==4 else 8,y*12,8,12))
	for entry in [["BUILDING_ICON_FARM_PLOT",Vector2(10,14),Vector2(32,32)],["UNIT_SHEET_CUSTOMIZE",Vector2(368,12),Vector2(32,36)],["BUILDING_SHEET_REMOVE",Vector2(400,12),Vector2(32,36)]]:
		if removing and entry[0]!="BUILDING_ICON_FARM_PLOT":continue
		var texture: Texture2D=art.texture(entry[0])
		if texture!=null:draw_texture_rect(texture,Rect2(entry[1],entry[2]),false)
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(64,36),name_entry.text if name_entry.editing else title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	if removing:
		draw_removal()
		return
	for season in 4:
		var rect:=tab_rect(season);var columns:=int(rect.size.x/8)
		var texture: Texture2D=art.texture("SHORT_TAB_SELECTED" if season==state.season else "SHORT_TAB")
		if texture!=null:
			for y in 2:
				for x in columns:
					var sx:=x if x<2 else 4-(columns-1-x) if x>=columns-2 else 2
					draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
		var caption: String=SEASONS[season]+("(now)" if season==current_season else "")
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),rect.position+Vector2(16,18),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color8(70,44,0) if season==state.season else Color.WHITE)

func draw_removal() -> void:
	# Native renderer180bfe..180fd3; first-job suspension takes precedence.
	if body.colors.size()!=16:return
	var font: Font=theme.default_font
	if font==null:return
	font.draw_string(get_canvas_item(),Vector2(16,96),"Slated for removal",HORIZONTAL_ALIGNMENT_LEFT,-1,12,body.colors[7])
	if state.snapshot.removal_suspended:
		font.draw_string(get_canvas_item(),Vector2(16,120),"Removal suspended.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,body.colors[12])
	elif not state.snapshot.removal_has_worker:
		font.draw_string(get_canvas_item(),Vector2(16,120),"Removal inactive.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,body.colors[14])
	var texture: Texture2D=art.texture("HORIZONTAL_OPTION_ACTIVE")
	if texture!=null:
		for y in 3:
			for x in 24:draw_texture_rect_region(texture,Rect2(cancel_rect().position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==23 else 8,y*12,8,12))
	font.draw_string(get_canvas_item(),Vector2(32,156),"Cancel removal",HORIZONTAL_ALIGNMENT_LEFT,-1,12,body.colors[12])

func _exit_tree() -> void:
	_leave_hover()
	if state!=null and state.has_method("finish_name_entry"):state.finish_name_entry()
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
