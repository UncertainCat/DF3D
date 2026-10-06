extends PanelContainer
# Native header clips the top edge; installed UI cells remain8x12.
var art
func configure(source) -> void:
	art = source
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)
func _draw() -> void:
	if art == null: return
	var frame: Texture2D = art.texture("HOVER_RECTANGLE")
	if frame == null: return
	var columns := int(size.x / 8)
	for y in 4:
		for x in columns:
			var sx := 0 if x == 0 else (16 if x == columns - 1 else 8)
			draw_texture_rect_region(frame, Rect2(x * 8, y * 12, 8, 12), Rect2(sx, 24 if y == 3 else 12, 8, 12))
