extends Control
# Native stockpile instruction boxes. Copy/wrapping and anchors are recorded in
# area_menus.json; hover identity and timing are owned by this presentation.
var art = preload("res://scripts/original_ui.gd").new()
var state = preload("res://scripts/native_hover_state.gd").new()
var controller
var entries: Dictionary = {}
var displayed := ""
var lines: Array = []

func configure(source, owner_controller) -> void:
	controller = owner_controller
	art.configure(source); theme = art.theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 10; hide()
	for row in controller.menu_data.stockpile_controls:
		bind_button(controller.stockpile_view.controls[row.key],"palette/"+str(row.key),row,false)
	for row in controller.menu_data.paint_tools:
		bind_button(controller.paint_view.buttons[row.key],"paint/"+str(row.key),row,true)

func bind_button(button: Button, key: String, row: Dictionary, paint: bool) -> void:
	entries[key] = {"button":button,"row":row,"paint":paint}
	button.mouse_entered.connect(func():
		if controller.kind_picker.selected == 0:
			state.enter(button.get_instance_id(),key,Time.get_ticks_msec()))
	button.mouse_exited.connect(func(): state.leave(button.get_instance_id(),Time.get_ticks_msec()))

func reset() -> void:
	state.reset(); displayed = ""; lines.clear(); hide(); queue_redraw()

func _process(_delta: float) -> void:
	if not controller.panel.visible or controller.kind_picker.selected != 0 or not controller.play_enabled:
		reset(); return
	var next: String = state.advance(Time.get_ticks_msec())
	if not state.key.is_empty():
		var button: Button = entries[state.key].button
		if not button.is_visible_in_tree() or button.disabled:
			reset(); return
	if next != displayed:
		displayed = next
		lines = [] if next.is_empty() else entries[next].row.hover_lines
		visible = not next.is_empty(); queue_redraw()
	if not visible: return
	var entry: Dictionary = entries[displayed]
	size = Vector2(224,(lines.size()+2)*12)
	if entry.paint:
		var rect: Rect2 = get_canvas_transform().affine_inverse() * (entry.button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO,entry.button.size))
		position = Vector2(rect.position.x+int(entry.row.hover_x_offset),rect.position.y-12-size.y)
	else:
		position = controller.panel.position+Vector2(controller.panel.size.x+8,int(entry.row.hover_bottom)-size.y)

func _draw() -> void:
	if displayed.is_empty(): return
	var frame: Texture2D = art.texture("HOVER_RECTANGLE")
	if frame == null or theme.default_font == null: return
	var rows := lines.size()+2
	for y in rows:
		for x in 28:
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else (16 if x==27 else 8),0 if y==0 else (24 if y==rows-1 else 12),8,12))
	for row in lines.size():
		theme.default_font.draw_string(get_canvas_item(),Vector2(16,(row+2)*12),str(lines[row]),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
