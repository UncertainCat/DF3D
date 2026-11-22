extends "res://scripts/special_building_sheet_view.gd"
# Native19205a..193ced; modes and count eligibility remain bridge-owned.
const SIEGE_ACTIONS=[3,4,2,1,0]
const SIEGE_TOKENS=["FIRE_AT_WILL","PRACTICE_FIRE","PREPARE_TO_FIRE","KEEP_LOADED","NOT_IN_USE"]
const SIEGE_CAPTIONS=["Not in use","Keep loaded but do not stand ready","Stand ready but do not fire","Fire at enemies","Practice fire"]
const RESTING_DIRECTIONS=["N","NE","E","SE","S","SW","W","NW"]
func siege_mode_rect(index: int) -> Rect2:return Rect2(size.x-136+24*index,84,24,36)
func siege_resting_rect(index: int) -> Rect2:return Rect2(16+32*index,156,32,36)
func _gui_input(event: InputEvent) -> void:
	if not removing and state.snapshot.get("type",-1)==22 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for index in 5:
			if siege_mode_rect(index).has_point(event.position):state.set_siege_mode(SIEGE_ACTIONS[index]);accept_event();return
		if state.snapshot.siege.type==2:
			for index in 8:
				if siege_resting_rect(index).has_point(event.position):state.set_siege_resting(index);accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.get("type",-1)!=22 or colors.size()!=16 or theme.default_font==null:return
	var value: Dictionary=state.snapshot.get("siege",{})
	if value.is_empty():return
	var bolt: bool=value.type==2
	_body_text("Practice fire (uses many bolts!)" if bolt and value.action==4 else SIEGE_CAPTIONS[value.action],Vector2(16,96))
	for index in 5:
		var icon: Texture2D=art.texture("BUILDING_INFO_SIEGE_ENGINE_"+SIEGE_TOKENS[index]+("_ACTIVE" if value.action==SIEGE_ACTIONS[index] else ""))
		if icon!=null:draw_texture_rect(icon,siege_mode_rect(index),false)
	if value.action==4:
		_body_text("* Will also target enemies",Vector2(16,120))
		_body_text("* Place archery targets for better training",Vector2(16,132))
	if not bolt:return
	_body_text("Resting orientation",Vector2(16,156))
	for index in 8:
		var rect:=siege_resting_rect(index)
		var background: Texture2D=art.texture("BUILDING_PLACEMENT_ACTIVE_BUTTON" if value.resting==index else "BUILDING_PLACEMENT_INACTIVE_BUTTON")
		var arrow: Texture2D=art.texture("BUILDING_PLACEMENT_"+RESTING_DIRECTIONS[index])
		if background!=null:draw_texture_rect(background,rect,false)
		if arrow!=null:draw_texture_rect(arrow,rect,false)
	for index in 4:
		var captions=["Bolts loaded: ","Bolts nearby and available: ","Bolts nearby but assigned to squads: ","Bolts nearby but assigned to hunters: "]
		var fields=["loaded","available","squads","hunters"]
		_body_text(captions[index]+str(value[fields[index]]),Vector2(16,216+12*index),[14,11,12,10][index])
