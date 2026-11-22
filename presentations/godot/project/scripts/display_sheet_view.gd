extends "res://scripts/siege_sheet_view.gd"
signal display_requested
var display
var display_scroll
var display_icons: Dictionary={}
var display_owner: int=-1
var _details_pending:=false
func configure_display(model) -> void:
	display=model
	display_scroll=preload("res://scripts/area_location_scrollbar.gd").new();add_child(display_scroll)
	display_scroll.configure(native_header_source);display_scroll.page=7
	display_scroll.input_allowed=display_allowed
	display_scroll.row_changed.connect(func(_first):_display_changed())
	display.changed.connect(_display_changed);_display_changed()
func display_allowed() -> bool:
	return contents_allowed() and not removing and display!=null and display.building_id==state.building_id and display.category==-1 and display.phase==display.Phase.Ready
func display_rect(index: int) -> Rect2:
	return Rect2(16,84+36*(index-display_scroll.first),size.x-32-(16 if display.body.size()>7 else 0),36)
func display_check(index: int) -> Rect2:
	var rect:=display_rect(index);return Rect2(rect.end.x-32,rect.position.y,32,36)
func assign_rect() -> Rect2:return Rect2(16,336,224,36)
func _display_changed() -> void:
	if display_owner!=display.building_id:display_owner=display.building_id;display_scroll.first=0;display_icons={}
	display_scroll.position=Vector2(size.x-32,96);display_scroll.size=Vector2(16,228)
	display_scroll.set_rows(display.body.size(),display_scroll.first)
	display_scroll.visible=state.snapshot.get("type",-1)==53 and not removing and display.category==-1 and display.body.size()>7
	if display_allowed() and display.ticket==0 and not _details_pending:_details_pending=true;_fetch_display.call_deferred()
	queue_redraw()
func _fetch_display() -> void:
	_details_pending=false
	if not display_allowed() or display.ticket!=0:return
	var ids: Array=[]
	for i in range(display_scroll.first,mini(display.body.size(),display_scroll.first+7)):
		var row: Dictionary=display.body[i]
		if row.resolved and not display.items.has(row.id):ids.append(row.id)
	if not ids.is_empty():display.request_items(ids)
func refresh() -> void:
	super.refresh()
	if display!=null:_display_changed()
func layout(view: Vector2) -> void:
	super.layout(view)
	if display_scroll!=null:display_scroll.position=Vector2(size.x-32,96)
func _process(delta: float) -> void:
	super._process(delta)
	if not is_visible_in_tree() or display==null or state.snapshot.get("type",-1)!=53:return
	for row in display.items.values():
		if row.has("appearance") and (display_icons.get(row.id,{}).get("appearance")!=row.appearance or display_icons.get(row.id,{}).get("texture")==null):
			display_icons[row.id]={"appearance":row.appearance.duplicate(true),"texture":native_header_source.item_sheet_icon(row.type,row.appearance,row.id)};queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if display_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if assign_rect().has_point(event.position):display_requested.emit();accept_event();return
		for i in range(display_scroll.first,mini(display.body.size(),display_scroll.first+7)):
			if display.body[i].resolved and display_check(i).has_point(event.position):display.remove_item(display.body[i].id);accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.get("type",-1)!=53 or display==null or display.building_id!=state.building_id or display.category!=-1:return
	for i in range(display_scroll.first,mini(display.body.size(),display_scroll.first+7)):
		var row: Dictionary=display.body[i]
		if not row.resolved:continue
		var rect:=display_rect(i)
		_patch(art.texture("BUTTON_RECTANGLE"),rect)
		_patch(picture.texture(false,false),Rect2(rect.position,Vector2(40,36)))
		var icon: Texture2D=display_icons.get(row.id,{}).get("texture")
		if icon!=null:draw_texture_rect(icon,Rect2(rect.position+Vector2(2,2),Vector2(32,32)),false)
		_body_text(row.name,rect.position+Vector2(56,24))
		_body_text(row.status,rect.position+Vector2(56,36),row.status_color)
		var texture: Texture2D=art.texture("BUILDING_SHEET_DISPLAY_FURNITURE_ITEM_ON")
		if texture!=null:draw_texture_rect(texture,display_check(i),false)
	_patch(art.texture("HORIZONTAL_OPTION_ACTIVE"),assign_rect())
	_body_text("Assign new display items",assign_rect().position+Vector2(16,24),10)
