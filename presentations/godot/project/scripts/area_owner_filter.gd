extends Panel
# The native textbox stores SDL UTF-8 bytes but renders them as DF byte glyphs.
signal edited(value: PackedByteArray)
const Art = preload("res://scripts/original_ui.gd")
var value := PackedByteArray()
var editable := true
var byte_limit := 33
var ticks_override := -1
var last_phase := -1
var ink := Color.WHITE

func configure(style: StyleBox, colors: Array[Color]) -> void:
	add_theme_stylebox_override("panel",style)
	focus_mode = Control.FOCUS_CLICK
	if colors.size() == 16: ink = colors[15]
	focus_entered.connect(queue_redraw); focus_exited.connect(queue_redraw)

func set_bytes(bytes: PackedByteArray) -> void:
	if value == bytes: return
	value = bytes.duplicate(); queue_redraw()

func feed_key(event: InputEventKey) -> void:
	if not editable or not has_focus() or not event.pressed: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		if event.shift_pressed: return
		if not event.echo: release_focus()
		return
	var before := value.duplicate()
	if event.keycode == KEY_BACKSPACE:
		if not value.is_empty(): value.resize(value.size()-1)
	elif event.unicode >= 32:
		for byte in String.chr(event.unicode).to_utf8_buffer():
			if value.size() >= byte_limit: break
			value.append(byte)
	if before != value: edited.emit(value.duplicate()); queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if editable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus(); accept_event()

func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	var ticks := ticks_override if ticks_override >= 0 else Time.get_ticks_msec()
	var phase := int(ticks % 1000 < 500)
	if phase != last_phase: last_phase = phase; queue_redraw()

func _draw() -> void:
	if theme == null or theme.default_font == null: return
	var display := ""
	for byte in value: display += String.chr(byte if byte < 128 else Art.CP437_HIGH[byte-128])
	var ticks := ticks_override if ticks_override >= 0 else Time.get_ticks_msec()
	if has_focus() and ticks % 1000 < 500: display += "_"
	theme.default_font.draw_string(get_canvas_item(),Vector2(16,24),display,HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
