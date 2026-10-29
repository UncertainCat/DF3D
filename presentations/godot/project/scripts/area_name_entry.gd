extends Label
# Native stockpile/zone name entry appends bytes and Backspace removes the last byte.
# It has no selection/caret navigation. The controller owns Escape/right-click.
signal edited(value: String)
signal submitted
const Art = preload("res://scripts/original_ui.gd")
var value := ""
var editing := false
var cursor_visible := true
var byte_limit := 20

func begin(custom_name: String) -> void:
	if editing: return
	value = custom_name; editing = true; show(); _refresh()

func finish() -> void:
	editing = false; hide()

func feed_key(event: InputEventKey) -> void:
	if not editing or not event.pressed: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]: submitted.emit(); return
	var before := value
	if event.keycode == KEY_BACKSPACE:
		value = value.left(maxi(0,value.length()-1))
	elif event.unicode >= 32:
		# DF's helper flags0x17 accepts text bytes verbatim. SDL supplies UTF-8;
		# the resulting native string is displayed with DF2UTF's CP437 mapping.
		for byte in String.chr(event.unicode).to_utf8_buffer():
			if value.length() >= byte_limit: break
			value += String.chr(byte if byte < 128 else Art.CP437_HIGH[byte-128])
	_refresh()
	if value != before: edited.emit(value)

func _process(_delta: float) -> void:
	if not editing: return
	var phase := Time.get_ticks_msec() % 1000 < 500
	if phase != cursor_visible: cursor_visible = phase; _refresh()

func _refresh() -> void:
	text = value + ("_" if cursor_visible else "")
