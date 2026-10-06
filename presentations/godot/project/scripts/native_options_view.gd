extends Control
signal option_requested(token: String)
signal dismissed
# MAIN_DWARF reference: native_options_frame.json, protected070526.
# Unexposed component until native action/lifecycle and input acceptance exist.
# Capture data is an offline oracle only; runtime resolves installed asset tokens.
const OPTIONS := [
	["SAVE_AND_QUIT", "Save and return to title menu", 17],
	["SAVE_AND_CONTINUE", "Save and continue playing", 19],
	["RETIRE_FORTRESS", "Retire the fortress (for the time being)", 11],
	["ABANDON_FORTRESS", "Abandon the fortress to ruin", 17],
	["QUIT_WITHOUT_SAVING", "Quit without saving", 22],
	["SETTINGS", "Settings", 27],
	["RETURN", "Return to game", 24],
]
var art = preload("res://scripts/original_ui.gd").new()
var input_allowed: Callable
var entries: Array = OPTIONS
var header_text := "Dwarf Fortress"

func accepts_input() -> bool:
	return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())

func _input(event: InputEvent) -> void:
	if not accepts_input(): return
	# Top-level Options only. Child prompts have independent native dismissal
	# behavior; their owner must deny this view's input while they are active.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled(); dismissed.emit()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled(); dismissed.emit()

func _gui_input(event: InputEvent) -> void:
	if not accepts_input(): return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for index in entries.size():
			if Rect2(72,48+index*36,360,36).has_point(event.position):
				accept_event(); option_requested.emit(entries[index][0]); return

func configure(source) -> void:
	art.configure(source); theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	if is_inside_tree() and not get_viewport().size_changed.is_connected(layout_reference):
		get_viewport().size_changed.connect(layout_reference)

func layout_reference() -> void:
	if not is_inside_tree(): return
	# Native menu centers on whole8x12 text cells, with a footer below the menu.
	# Verified at960x600,1200x800 and1600x900; automatic scaling remains separate.
	var viewport := get_viewport_rect().size
	var columns := int(viewport.x / 8)
	var rows := int(viewport.y / 12)
	position = Vector2(floori((columns-63)/2.0)*8+floori(fposmod(viewport.x,8)/2),
		floori((rows-5-entries.size()*3)/2.0)*12+floori(fposmod(viewport.y,12)/2))
	size = Vector2(504,(11+entries.size()*3)*12)

func patch(token: String, origin: Vector2i, columns: int, rows: int) -> void:
	var texture: Texture2D = art.texture(token)
	if texture == null: return
	for y in rows:
		for x in columns:
			draw_texture_rect_region(texture,Rect2((origin.x+x)*8,(origin.y+y)*12,8,12),Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else 24 if y==rows-1 else 12,8,12))

func _draw() -> void:
	var main_rows := 7+entries.size()*3
	patch("HOVER_RECTANGLE",Vector2i.ZERO,63,main_rows)
	patch("HOVER_RECTANGLE",Vector2i(0,main_rows),63,4)
	if theme == null or theme.default_font == null: return
	var font: Font = theme.default_font
	font.draw_string(get_canvas_item(),Vector2(24*8,3*12),header_text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	for index in entries.size():
		patch("BUTTON_CATEGORY_RECTANGLE",Vector2i(9,4+index*3),45,3)
		font.draw_string(get_canvas_item(),Vector2(entries[index][2]*8,(6+index*3)*12),entries[index][1],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		if entries[index].size()>4:
			var detail:String=entries[index][3]
			font.draw_string(get_canvas_item(),Vector2(floori((63-detail.length())/2.0)*8,(7+index*3)*12),detail,HORIZONTAL_ALIGNMENT_LEFT,-1,12,entries[index][4])
