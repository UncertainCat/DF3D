extends Control
# Staged sheet composition. The owner must connect header actions before exposure.
signal rename_requested
signal removal_requested
const SEASONS=["Spring","Summer","Autumn","Winter"]
var art=preload("res://scripts/original_ui.gd").new()
var state
var body
var title: String="Farm Plot"
var current_season: int=-1
var target: int=-1
var input_allowed: Callable

func configure(source,model) -> void:
	state=model;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	body=preload("res://scripts/farm_body_view.gd").new();add_child(body);body.configure(source,model)
	body.position=Vector2(16,144);body.input_allowed=allowed
	state.changed.connect(refresh);refresh()

func allowed() -> bool:return not input_allowed.is_valid() or input_allowed.call()
func layout(view: Vector2) -> void:
	position=Vector2((floori(view.x/8)-98)*8,48+fposmod(view.y,12)*0.5)
	size=Vector2(488,floori(view.y/12)*12-84);queue_redraw()

func refresh() -> void:
	if target!=state.building_id:target=state.building_id;current_season=-1
	visible=target>=0
	if not state.snapshot.is_empty():current_season=int(state.snapshot.current_season)
	queue_redraw()

func tab_rect(season: int) -> Rect2:return Rect2(8+season*120,60,112 if season==3 else 120,24)

func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
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
		var texture: Texture2D=art.texture(entry[0])
		if texture!=null:draw_texture_rect(texture,Rect2(entry[1],entry[2]),false)
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(64,36),title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
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

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
