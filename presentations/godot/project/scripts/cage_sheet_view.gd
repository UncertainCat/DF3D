extends "res://scripts/depot_sheet_view.gd"
signal cage_requested
# Native Cage28 assignment control, protected105758 at1200x800.
func cage_rect() -> Rect2:return Rect2(16,336,32,36)
func _gui_input(event: InputEvent) -> void:
	if not removing and state.snapshot.get("type",-1)==28 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and cage_rect().has_point(event.position):
		cage_requested.emit();accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.get("type",-1)!=28:return
	var texture: Texture2D=art.texture("ZONE_PICK_ANIMALS")
	if texture!=null:draw_texture_rect(texture,cage_rect(),false)
