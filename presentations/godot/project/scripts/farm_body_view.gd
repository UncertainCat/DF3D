extends Control
# Native crop/fertilizer body. The sheet owner supplies tabs, frame and target.
const PAGE:=7
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var state
var world
var colors: Array[Color]=[]
var rows: Array=[]
var icons: Dictionary={}
var first:=0
var identity:=Vector2i(-1,-1)
var input_allowed: Callable

func configure(source,model) -> void:
	world=source;state=model;art.configure(source);picture.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root())
	size=Vector2(456,300);texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(refresh);refresh()

func refresh() -> void:
	rows=[];icons.clear()
	if state==null:return
	var next:=Vector2i(state.building_id,state.season)
	if next!=identity:first=0;identity=next
	if not state.snapshot.is_empty():
		rows=[{"id":-1,"name":"Leave fallow"}]
		rows.append_array(state.choices())
		for row in rows:
			icons[row.id]=art.texture("FARMPLOT") if row.id==-1 else world.farm_crop_icon(row.raw_id)
	first=clampi(first,0,maxi(0,rows.size()-PAGE));queue_redraw()

func available() -> bool:
	return state!=null and state.phase==state.Phase.Ready and state.ticket==0 and (not input_allowed.is_valid() or input_allowed.call())

func checkbox_rect(index: int) -> Rect2:return Rect2(424,index*36,32,36)
func fertilizer_rect(seasonal: bool) -> Rect2:return Rect2(216 if seasonal else 8,264,24,36)

func _gui_input(event: InputEvent) -> void:
	if not available() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for index in mini(PAGE,rows.size()-first):
		if checkbox_rect(index).has_point(event.position):
			state.choose_crop(int(rows[first+index].id));accept_event();return
	if fertilizer_rect(false).has_point(event.position):
		state.toggle_fertilization();accept_event()
	elif fertilizer_rect(true).has_point(event.position):
		state.set_seasonal_fertilization(not state.snapshot.seasonal_fertilization);accept_event()

func patch(texture: Texture2D, origin: Vector2, columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))

func option(selected: bool, at: Vector2) -> void:
	var texture: Texture2D=art.texture("BUILDING_SHEET_FARM_ACTIVE_OPTION" if selected else "BUILDING_SHEET_FARM_INACTIVE_OPTION")
	if texture!=null:draw_texture_rect(texture,Rect2(at,Vector2(32,36)),false)

func label(text: String, at: Vector2, color: int) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])

func _draw() -> void:
	if state==null or state.snapshot.is_empty() or colors.size()!=16:return
	var selected: int=state.snapshot.seasonal_crops[state.season]
	for index in mini(PAGE,rows.size()-first):
		var row: Dictionary=rows[first+index];var top:=Vector2(0,index*36)
		patch(art.texture("BUTTON_RECTANGLE"),top,57)
		patch(picture.texture(false),top,5)
		var icon: Texture2D=icons.get(row.id)
		if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var color:=4 if row.get("current_season_warning",false) and state.season==state.snapshot.current_season else 7
		if row.id==selected:color+=8
		var name: String=row.name
		if name.length()>=42:name=name.left(38)+"..."
		label(name,top+Vector2(56,24),color)
		if row.id>=0 and not row.seeds_available:label("No seeds",top+Vector2(56,36),12)
		option(row.id==selected,top+Vector2(424,0))
	var fertilizing: bool=state.snapshot.current_fertilization+state.snapshot.pending_fertilization>=state.snapshot.max_fertilization
	option(fertilizing,Vector2(8,264))
	option(state.snapshot.seasonal_fertilization,Vector2(216,264))
	label("Set to fertilize" if fertilizing else "Not set to fertilize",Vector2(40,288),15)
	label("Current amount: %d/%d"%[state.snapshot.current_fertilization,state.snapshot.max_fertilization],Vector2(40,300),15)
	label("Fertilize",Vector2(248,288),15);label("every season",Vector2(248,300),15)

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
