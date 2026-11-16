extends "res://scripts/depot_sheet_view.gd"
signal cage_requested
# Native Cage28 assignment control, protected105758 at1200x800.
func cage_rect() -> Rect2:return Rect2(16,336,32,36)
func aquarium_rect(aquarium: bool) -> Rect2:return Rect2(392 if aquarium else 304,336,80 if aquarium else 88,36)
func _gui_input(event: InputEvent) -> void:
	if not removing and state.snapshot.get("type",-1)==28 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var body: Dictionary=state.snapshot.get("cage",{})
		if body.get("glass",false) and not body.get("justice_restraint",true):
			for aquarium in [false,true]:
				if aquarium_rect(aquarium).has_point(event.position):state.set_cage_aquarium(aquarium);accept_event();return
	if not removing and state.snapshot.get("type",-1)==28 and not state.snapshot.get("cage",{}).get("justice_restraint",true) and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and cage_rect().has_point(event.position):
		cage_requested.emit();accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.get("type",-1)!=28 or state.snapshot.get("cage",{}).get("justice_restraint",true):return
	var texture: Texture2D=art.texture("ZONE_PICK_ANIMALS")
	if texture!=null:draw_texture_rect(texture,cage_rect(),false)
	var body: Dictionary=state.snapshot.get("cage",{})
	if body.get("glass",false):
		for aquarium in [false,true]:
			var rect:=aquarium_rect(aquarium)
			_patch(art.texture("HORIZONTAL_OPTION_CONFIRM" if body.aquarium==aquarium else "HORIZONTAL_OPTION_ACTIVE"),rect)
			_body_text("Aquarium" if aquarium else "Terrarium",rect.position+Vector2(8,24),15)
