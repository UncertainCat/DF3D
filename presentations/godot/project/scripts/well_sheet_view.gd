extends "res://scripts/barrier_sheet_view.gd"
# Native53.16 renderer189f21..18a081, native status560b60 through the header.
const WELL_TEXT=["The well is operational.","There is no bucket.","The bucket is full.","The well is dry."]
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.is_empty() or colors.size()!=16 or theme.default_font==null:return
	var body: Dictionary=state.snapshot.get("well",{})
	if not body.is_empty():_body_text(WELL_TEXT[int(body.status)],Vector2(16,96),15 if body.status==0 else 14)
