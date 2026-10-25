extends PanelContainer
# Native e5 Storage and tools popup. Values remain authoritative until a reply.
signal value_requested(key: String, value: int)
signal done
const KEYS = ["barrels","bins","wheelbarrows"]
var art = preload("res://scripts/original_ui.gd").new()
var area: Dictionary = {}
var enabled := false
var labels: Dictionary = {}
var controls: Dictionary = {}
var editing := ""
var entry: LineEdit
var last_entry := ""

func configure(source) -> void:
	art.configure(source); theme = art.theme; texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var body := Control.new(); body.custom_minimum_size = Vector2(312,156); add_child(body)
	caption(body,"Storage and tools",Vector2(8,0),Vector2(200,36))
	var close := Button.new(); close.text = "Done"; close.position = Vector2(216,0); close.size = Vector2(96,36)
	close.add_theme_font_size_override("font_size",12); close.pressed.connect(func(): done.emit()); body.add_child(close)
	var close_style := art.make_style("HORIZONTAL_OPTION_REMOVE",8)
	close_style.set_texture_margin(SIDE_TOP,12); close_style.set_texture_margin(SIDE_BOTTOM,12)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: close_style.set_content_margin(side,0)
	for state in ["normal","hover","pressed"]: close.add_theme_stylebox_override(state,close_style)
	for index in KEYS.size():
		var key: String = KEYS[index]
		var y := 48.0 + index * 36
		caption(body,"Max " + key,Vector2(8,y),Vector2(168,36))
		var number := caption(body,"",Vector2(168,y),Vector2(32,36)); number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		labels[key] = number
		var buttons: Array[Button] = []
		for action in 3:
			var button := Button.new(); button.position = Vector2(216 + action * 32,y); button.size = Vector2(32,36)
			for state in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
			var icon := TextureRect.new(); icon.size = Vector2(32,36)
			icon.texture = art.texture(["ARENA_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"][action])
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
			button.pressed.connect(func(): activate(key,action))
			body.add_child(button); buttons.append(button)
		controls[key] = buttons
	entry = LineEdit.new(); entry.size = Vector2(64,36); entry.max_length = 0 # Normalize accepted digits before applying the native three-digit limit.
	entry.alignment = HORIZONTAL_ALIGNMENT_RIGHT; entry.add_theme_font_size_override("font_size",12)
	entry.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); entry.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	entry.text_changed.connect(edit_entry)
	entry.text_submitted.connect(submit_entry); body.add_child(entry); entry.hide()

func caption(parent: Node, text: String, point: Vector2, dimensions: Vector2) -> Label:
	var label := Label.new(); label.text = text; label.position = point; label.size = dimensions
	label.add_theme_font_size_override("font_size",12); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label); return label

func maximum(_key: String) -> int:
	return int(area.get("storage_limit",-1))

func display(value: Dictionary, can_edit: bool, own_pending := false) -> void:
	if int(value.get("id",-1)) != int(area.get("id",-1)) or int(value.get("revision",0)) != int(area.get("revision",0)) or (not can_edit and not own_pending): cancel_edit()
	entry.editable = can_edit or own_pending
	area = value.duplicate(true); enabled = can_edit
	for key in KEYS:
		var current := int(area.get(key,0)); var cap := maximum(key)
		labels[key].text = str(current)
		labels[key].visible = key != editing
		controls[key][0].disabled = not enabled or cap < 0
		controls[key][1].disabled = not enabled or cap < 0 or current >= cap
		controls[key][2].disabled = not enabled or cap < 0 or current <= 0 or current - 1 > cap

func activate(key: String, action: int) -> void:
	if not enabled or key not in KEYS or action < 0 or action > 2 or controls[key][action].disabled: return
	if action == 0:
		if editing == key:
			cancel_edit(); return
		cancel_edit(); editing = key; labels[key].hide()
		entry.position = Vector2(136,48 + KEYS.find(key) * 36)
		last_entry = ""; entry.text = ""; entry.show(); entry.grab_focus()
	else:
		value_requested.emit(key,int(area[key]) + (1 if action == 1 else -1))

func accept(value: Dictionary) -> void:
	# A confirmed write advances only this entry's receipt. Keep its current text,
	# caret and focus while a newer explicit value waits for that receipt.
	if int(value.get("id",-1)) != int(area.get("id",-1)): cancel_edit()
	area = value.duplicate(true)

func edit_entry(value: String) -> void:
	if editing.is_empty() or not entry.editable or maximum(editing) < 0: return
	var digits := ""
	var caret := 0
	for index in value.length():
		if value[index] >= "0" and value[index] <= "9" and digits.length() < 3:
			digits += value[index]
			if index < entry.caret_column: caret += 1
	if entry.text != digits:
		entry.set_text(digits); entry.caret_column = caret
	if digits == last_entry: return
	last_entry = digits
	value_requested.emit(editing,mini(int(digits),maximum(editing)))

func submit_entry(_value: String) -> void:
	# Native Enter ends entry; values have already been requested while typing.
	finish_edit()

func finish_edit() -> void:
	# LineEdit can defer text_changed until after a same-frame Escape/Done.
	# Collect that final explicit input before hiding the field.
	edit_entry(entry.text)
	cancel_edit()

func cancel_edit() -> bool:
	if editing.is_empty(): return false
	labels[editing].show(); editing = ""; entry.hide(); entry.release_focus()
	return true
