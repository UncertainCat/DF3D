extends "res://scripts/chest_sheet_view.gd"
# Native coffin/slab body, captured in protected funerary discovery035425.
# Shared header and contents retain their independent action authority.
var owner_recipe: Dictionary={}
var owner_texture: Texture2D

func refresh() -> void:
	super.refresh()
	if contents!=null:contents.building_type=state.snapshot.get("type",-1);contents.queue_redraw()
	var recipe: Dictionary=state.snapshot.get("funerary",{}).get("owner_appearance",{})
	if recipe!=owner_recipe:
		owner_recipe=recipe.duplicate(true)
		owner_texture=null if recipe.is_empty() else native_header_source.candidate_icon(recipe)

func _body_text(value: String,at: Vector2,color: int=15) -> void:
	theme.default_font.draw_string(get_canvas_item(),at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])

func _draw() -> void:
	super._draw()
	if removing or state.snapshot.is_empty() or colors.size()!=16 or theme.default_font==null:return
	var body: Dictionary=state.snapshot.get("funerary",{})
	if body.is_empty():return
	var baseline:=96
	for notice in body.notices:
		_body_text(notice,Vector2(16,baseline));baseline+=12
	if not body.introduction.is_empty():
		# Coffin194ee5 inherits the last header warning tint; Slab resets it to white.
		var introduction_color:=4 if state.snapshot.type==3 and state.snapshot.forbidden else 15
		_body_text(body.introduction,Vector2(16,96),introduction_color)
		# Native draws this punctuation separately from the semantic name formatter.
		_body_text(body.name+".",Vector2(16,108),introduction_color)
	if body.unit_id>=0:
		if owner_texture!=null:draw_texture_rect(owner_texture,Rect2(18,134,32,32),false)
		_body_text(body.name,Vector2(64,156))
		_body_text(body.deceased,Vector2(64,168),13)
	if body.room_id>=0:
		var top:=216 if body.unit_id>=0 else 108
		_body_text(body.room_introduction,Vector2(16,top-12))
		var frame: Texture2D=art.texture("BUILDING_PLACEMENT_INACTIVE_BUTTON")
		if frame!=null:draw_texture_rect(frame,Rect2(16,top,32,36),false)
		var icon: Texture2D=art.texture("ZONE_TOMB")
		if icon!=null:draw_texture_rect(icon,Rect2(16,top+2,32,32),false)
		_body_text(body.room_name,Vector2(64,top+24))
