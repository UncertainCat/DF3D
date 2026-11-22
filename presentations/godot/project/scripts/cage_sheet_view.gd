extends "res://scripts/depot_sheet_view.gd"
signal cage_requested
var occupants
var occupant_scroll
var occupant_textures: Dictionary={}
var occupant_target: int=-1
var occupant_rows: Array=[]
func configure_occupants(model) -> void:
	occupants=model
	occupant_scroll=preload("res://scripts/area_location_scrollbar.gd").new();add_child(occupant_scroll)
	occupant_scroll.configure(native_header_source);occupant_scroll.page=7
	occupant_scroll.input_allowed=occupants_allowed
	occupant_scroll.row_changed.connect(func(_first):queue_redraw())
	occupants.changed.connect(_occupants_changed);_occupants_changed()
func occupants_allowed() -> bool:
	return contents_allowed() and not removing and occupants!=null and occupants.building_id==state.building_id and not occupants.busy()
func _occupants_changed() -> void:
	if occupant_rows!=occupants.rows or occupant_target!=occupants.building_id:
		occupant_textures.clear();occupant_rows=occupants.rows.duplicate()
	if occupant_target!=occupants.building_id:occupant_scroll.first=0;occupant_target=occupants.building_id
	occupant_scroll.position=Vector2(size.x-32,96);occupant_scroll.size=Vector2(16,228)
	occupant_scroll.set_rows(occupants.rows.size(),occupant_scroll.first)
	occupant_scroll.visible=state.snapshot.get("type",-1)==28 and not removing and occupants.rows.size()>7
	queue_redraw()
func layout(view: Vector2) -> void:
	super.layout(view)
	if occupant_scroll!=null:occupant_scroll.position=Vector2(size.x-32,96)
func refresh() -> void:
	super.refresh()
	if occupants!=null:_occupants_changed()
func _occupant_visible(row: Dictionary) -> bool:
	# Native18d450/18d959 loses the contained-item pointer. Preserve the blank
	# slot and inactive input until a maintainer approves correcting that bug.
	return row.get("resolved",false) and not (row.entity==2 and row.contained)
func _process(_delta: float) -> void:
	if not is_visible_in_tree() or occupants==null or state.snapshot.get("type",-1) not in [27,28]:return
	for i in range(occupant_scroll.first,mini(occupants.rows.size(),occupant_scroll.first+7)):
		if not occupant_textures.has(i) and _occupant_visible(occupants.rows[i]):
			var recipe: Dictionary=occupants.rows[i].get("appearance",{})
			occupant_textures[i]=null if recipe.is_empty() else native_header_source.candidate_icon(recipe);queue_redraw()
func occupant_rect(index: int) -> Rect2:
	return Rect2(16,84+36*(index-occupant_scroll.first),size.x-32-(16 if occupants.rows.size()>7 else 0),36)
func occupant_check(index: int) -> Rect2:
	var row:=occupant_rect(index);return Rect2(row.end.x-40,row.position.y,32,36)
# Native Cage28 assignment control, protected105758 at1200x800.
func cage_rect() -> Rect2:
	var count: int=occupants.rows.size() if occupants!=null and occupants.building_id==state.building_id else 0
	return Rect2(16,84+36*count if state.snapshot.get("type",-1)==27 else 336,32,36)
func aquarium_rect(aquarium: bool) -> Rect2:return Rect2(392 if aquarium else 304,336,80 if aquarium else 88,36)
func _gui_input(event: InputEvent) -> void:
	if occupants_allowed() and state.snapshot.get("type",-1) in [27,28] and event is InputEventMouseButton and event.pressed:
		if state.snapshot.get("type",-1)==28 and Rect2(16,84,size.x-32,252).has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			occupant_scroll.move_to(occupant_scroll.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
		if event.button_index==MOUSE_BUTTON_LEFT and not state.snapshot.get("cage",{}).get("justice_restraint",true) and not occupants.snapshot.get("justice_restraint",true):
			for i in range(occupant_scroll.first,mini(occupants.rows.size(),occupant_scroll.first+7)):
				var row: Dictionary=occupants.rows[i]
				if _occupant_visible(row) and occupant_check(i).has_point(event.position):occupants.toggle_animal(row.entity,row.id);accept_event();return
	if not removing and state.snapshot.get("type",-1)==28 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var body: Dictionary=state.snapshot.get("cage",{})
		if body.get("glass",false) and not body.get("justice_restraint",true):
			for aquarium in [false,true]:
				if aquarium_rect(aquarium).has_point(event.position):state.set_cage_aquarium(aquarium);accept_event();return
	if not removing and state.snapshot.get("type",-1) in [27,28] and not state.snapshot.get("cage",{}).get("justice_restraint",true) and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and cage_rect().has_point(event.position):
		cage_requested.emit();accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.get("type",-1) not in [27,28]:return
	var body: Dictionary=state.snapshot.get("cage",{})
	if body.is_empty():return
	if occupants!=null and occupants.building_id==state.building_id:
		for i in range(occupant_scroll.first,mini(occupants.rows.size(),occupant_scroll.first+7)):
			var row: Dictionary=occupants.rows[i]
			if not _occupant_visible(row):continue
			var rect:=occupant_rect(i)
			var chain: bool=state.snapshot.get("type",-1)==27
			if not chain:
				_patch(art.texture("BUTTON_RECTANGLE"),rect)
				_patch(picture.texture(false,false),Rect2(rect.position,Vector2(40,36)))
			var portrait: Texture2D=occupant_textures.get(i)
			if portrait!=null:draw_texture_rect(portrait,Rect2(rect.position+Vector2(2,2),Vector2(32,32)),false)
			var caption: String=row.name
			var limit:=int(rect.size.x/8)-16
			if caption.length()>=limit+1:caption=caption.left(limit);caption=caption.left(maxi(0,caption.length()-3))+"..." if limit>3 else caption
			_body_text(caption,rect.position+Vector2(48,24) if chain else rect.position+Vector2(56,24),15)
			_body_text(row.status,rect.position+Vector2(48,36) if chain else rect.position+Vector2(56,36),row.status_color)
			var check: Texture2D=art.texture("LABOR_WORKER_ASSIGNED" if row.assigned else "LABOR_WORKER_UNASSIGNED")
			if check!=null and (not chain or not body.justice_restraint):draw_texture_rect(check,occupant_check(i),false)
	if not body.justice_restraint:
		var texture: Texture2D=art.texture("ZONE_PICK_ANIMALS")
		if texture!=null:draw_texture_rect(texture,cage_rect(),false)
	if body.glass and not body.justice_restraint:
		for aquarium in [false,true]:
			var rect:=aquarium_rect(aquarium)
			_patch(art.texture("HORIZONTAL_OPTION_CONFIRM" if body.aquarium==aquarium else "HORIZONTAL_OPTION_ACTIVE"),rect)
			_body_text("Aquarium" if aquarium else "Terrarium",rect.position+Vector2(8,24),15)
	var room: Dictionary=body.room
	if room.room_id>=0:
		_body_text(room.introduction,Vector2(16,384))
		var frame: Texture2D=art.texture("BUILDING_PLACEMENT_INACTIVE_BUTTON")
		if frame!=null:draw_texture_rect(frame,Rect2(16,396,32,36),false)
		var token: String=preload("res://scripts/building_room_art.gd").token(room)
		if not token.is_empty():
			var icon: Texture2D=art.texture(token)
			if icon!=null:draw_texture_rect(icon,Rect2(16,398,32,32),false)
		_body_text(room.name,Vector2(64,420))
	else:
		var baseline:=384
		for notice in room.notices:
			_body_text(notice,Vector2(16,baseline));baseline+=12
