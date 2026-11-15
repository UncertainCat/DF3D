extends "res://scripts/chest_sheet_view.gd"
# Native unfinished-building body. No completed-building rename/remove icons.
var artwork_source
var header_recipe: Dictionary={}
var header_texture: Texture2D
func configure(source,model,help=null,contents_model=null) -> void:
	artwork_source=source
	super.configure(source,model,help,contents_model)
func refresh() -> void:
	super.refresh()
	var recipe: Dictionary=state.snapshot.get("appearance",{})
	if recipe!=header_recipe:
		header_recipe=recipe.duplicate(true)
		header_texture=null if recipe.is_empty() else artwork_source.candidate_icon(recipe)
func header_art() -> Array:
	return []
func _process(_delta: float) -> void:pass
func header_color() -> Color:
	return colors[12] if state.snapshot.get("forbidden",false) and colors.size()==16 else Color.WHITE
func draw_header_warnings() -> void:
	# Native180422..180679 uses building::isForbidden for title and warnings.
	if not state.snapshot.get("forbidden",false) or colors.size()!=16 or theme.default_font==null:return
	for y in [24,48]:theme.default_font.draw_string(get_canvas_item(),Vector2(64,y),"*** Forbidden ***",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[4])
func _gui_input(event: InputEvent) -> void:
	if not allowed() or state.phase!=state.Phase.Ready or state.ticket!=0 or state.snapshot.is_empty():return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if state.snapshot.removing:
			if cancel_rect().has_point(event.position):state.edit(state.Operation.CancelRemoval);accept_event()
			return
		if Rect2(16,132,192,36).has_point(event.position):
			state.edit(state.Operation.Resume if state.snapshot.suspended else state.Operation.Suspend);accept_event()
		elif Rect2(16,168,192,36).has_point(event.position):state.edit(state.Operation.Cancel);accept_event()
func _draw() -> void:
	super._draw()
	if not state.snapshot.is_empty() and header_texture!=null:draw_texture_rect(header_texture,Rect2(10,14,32,32),false)
	if state.snapshot.is_empty() or removing or colors.size()!=16 or theme.default_font==null:return
	var value: Dictionary=state.snapshot
	var font: Font=theme.default_font
	var progress: String=["","Waiting for construction...","Construction initiated.","Partially constructed.","Construction nearly done."][value.progress]
	font.draw_string(get_canvas_item(),Vector2(16,96),progress,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[7])
	if value.suspended:font.draw_string(get_canvas_item(),Vector2(16,120),"Construction suspended.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[12])
	elif not value.has_worker:font.draw_string(get_canvas_item(),Vector2(16,120),"Construction inactive.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[14])
	var texture: Texture2D=art.texture("HORIZONTAL_OPTION_ACTIVE")
	for row in 2:
		if texture!=null:
			for y in 3:
				for x in 24:draw_texture_rect_region(texture,Rect2(16+x*8,132+row*36+y*12,8,12),Rect2(0 if x==0 else 16 if x==23 else 8,y*12,8,12))
		var caption: String=("Resume construction" if value.suspended else "Suspend construction") if row==0 else ("Cancel construction" if value.stage==0 else "Remove building")
		font.draw_string(get_canvas_item(),Vector2(32,156+row*36),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[14 if row==0 else 12])
