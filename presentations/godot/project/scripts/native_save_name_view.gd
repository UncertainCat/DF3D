extends Control
# Unexposed component; full filename and overwrite submission parity remains unfinished.
# Native075152 establishes these lines, field placement and Cancel geometry.
signal cancelled
signal submitted(bytes: PackedByteArray)
const LINES := ["What would you like to name this manual", "save?  It will never be overwritten,", "but you can delete it while loading."]
var prompt_lines: Array = LINES
var excluded_bytes := PackedByteArray([34,42,47,58,60,62,63,92,124])
var art=preload("res://scripts/original_ui.gd").new()
var field_text:=""
var name_bytes:=PackedByteArray()
var cursor_visible:=true
var ticks_override:=-1
var field_color:=Color.TRANSPARENT
var input_allowed:Callable
func configure(source) -> void:
	art.configure(source);theme=art.theme
	var palette:=FileAccess.get_file_as_string(source.assets_root().path_join("data/init/colors.txt"))
	var channels:Array=[]
	for channel in ["R","G","B"]:
		var marker:String="[LCYAN_"+channel+":"
		var start:=palette.find(marker)
		if start<0:return
		channels.append(float(palette.substr(start+marker.length()).get_slice("]",0))/255.0)
	field_color=Color(channels[0],channels[1],channels[2])
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	if is_inside_tree() and not get_viewport().size_changed.is_connected(layout_reference):
		get_viewport().size_changed.connect(layout_reference)
func layout_reference() -> void:
	if not is_inside_tree():return
	# Native whole-cell placement; protected save-name resize capture155715.
	var viewport:=get_viewport_rect().size
	var columns:=int(viewport.x/8)
	var rows:=int(viewport.y/12)
	position=Vector2(floori((columns-63)/2.0)*8+floori(fposmod(viewport.x,8)/2),
		floori((rows-10)/2.0)*12+floori(fposmod(viewport.y,12)/2))
	size=Vector2(504,144)
func begin_entry() -> void:
	name_bytes=PackedByteArray();_refresh_field();show();_process(0)
func _process(_delta:float) -> void:
	if not is_visible_in_tree():return
	# Native080355: all150 timestamped samples agree with this half-second phase.
	var ticks:=ticks_override if ticks_override>=0 else Time.get_ticks_msec()
	var phase:=ticks%1000<500
	if phase!=cursor_visible:cursor_visible=phase;queue_redraw()
func _refresh_field() -> void:
	# Native SDL text arrives as UTF-8 bytes, but the field draws CP437 cells.
	# Preserve that observed behavior, including byte-wise Backspace.
	field_text=""
	for value in name_bytes:field_text+=String.chr(value if value<128 else art.CP437_HIGH[value-128])
	queue_redraw()
func accepts_input() -> bool:
	return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func _input(event:InputEvent) -> void:
	if not accepts_input():return
	# Physical074713/074822: these inputs do not dismiss the naming prompt.
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled();return
	if not event is InputEventKey or not event.pressed:return
	get_viewport().set_input_as_handled()
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		# Preserve native field bytes, including a truncated UTF-8 sequence.
		# The session owner decides destination conflicts and command eligibility.
		submitted.emit(name_bytes.duplicate())
		return
	if event.keycode==KEY_BACKSPACE:
		if not name_bytes.is_empty():name_bytes.resize(name_bytes.size()-1)
	elif event.unicode>=32 and event.keycode not in [KEY_ESCAPE,KEY_ENTER,KEY_KP_ENTER]:
		for value in String.chr(event.unicode).to_utf8_buffer():
			if name_bytes.size()>=40:break
			if value in excluded_bytes:continue
			name_bytes.append(value)
	_refresh_field()
func _gui_input(event:InputEvent) -> void:
	if accepts_input() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and Rect2(408,72,80,36).has_point(event.position):
		accept_event();cancelled.emit()
func patch(name:String,origin:Vector2i,columns:int,rows:int) -> void:
	var texture:Texture2D=art.texture(name)
	if texture==null:return
	for y in rows:
		for x in columns:
			draw_texture_rect_region(texture,Rect2((origin.x+x)*8,(origin.y+y)*12,8,12),Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else 24 if y==rows-1 else 12,8,12))
func _draw() -> void:
	patch("HOVER_RECTANGLE",Vector2i.ZERO,63,12)
	patch("HORIZONTAL_OPTION_REMOVE",Vector2i(51,6),10,3)
	if theme.default_font==null:return
	var font:Font=theme.default_font
	for line in prompt_lines.size():font.draw_string(get_canvas_item(),Vector2(16,(3+line)*12),prompt_lines[line],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	font.draw_string(get_canvas_item(),Vector2(16,84),field_text+("_" if cursor_visible else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,12,field_color)
	font.draw_string(get_canvas_item(),Vector2(424,96),"Cancel",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
