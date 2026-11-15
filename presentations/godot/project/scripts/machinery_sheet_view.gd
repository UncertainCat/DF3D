extends "res://scripts/linked_building_sheet_view.gd"
# DF53.16 renderer18a096/19ad00; semantic facts come from the owned native provider.
const STATUS_TEXT=["","Active","Inactive","Frozen Here","Frozen Elsewhere"]
const STATUS_COLOR=[15,10,12,11,11]
const DIRECTIONS=["Pumps from the north","Pumps from the east","Pumps from the south","Pumps from the west"]

func pump_rect() -> Rect2:
	var body: Dictionary=state.snapshot.get("machinery",{})
	return Rect2(16,96+(36 if body.get("status",0)!=0 else 0),24,36)

func _gui_input(event: InputEvent) -> void:
	if not removing and state.snapshot.get("type",-1)==33 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and pump_rect().has_point(event.position):
		state.set_pump_manual(state.snapshot.machinery.pump_manual==0)
		accept_event();return
	super._gui_input(event)

func _draw() -> void:
	super._draw()
	if removing or state.snapshot.is_empty() or colors.size()!=16 or theme.default_font==null:return
	var body: Dictionary=state.snapshot.get("machinery",{})
	if body.is_empty():return
	var baseline:=96
	var status: int=body.status
	if status!=0:
		_body_text(STATUS_TEXT[status],Vector2(16,baseline),STATUS_COLOR[status])
		_body_text("Total Power: "+str(body.produced),Vector2(16,baseline+12))
		_body_text("Total Power Needed: "+str(body.required),Vector2(16,baseline+24))
		baseline+=36
	_body_text("Stable Foundation" if body.stable_foundation else "Hanging",Vector2(16,baseline))
	if body.disengaged:_body_text("Disengaged",Vector2(16,baseline+12))
	if state.snapshot.type==33:
		var manual: bool=body.pump_manual==1
		var texture: Texture2D=art.texture("BUILDING_INFO_ACTIVE" if manual else "BUILDING_INFO_INACTIVE")
		if texture!=null:draw_texture_rect(texture,pump_rect(),false)
		_body_text("Stop Pumping Manually" if manual else "Start Pump Manually",Vector2(48,baseline+24))
		_body_text(DIRECTIONS[body.pump_direction],Vector2(16,baseline+48))
