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
	entry = LineEdit.new(); entry.size = Vector2(64,36); entry.max_length = 5
	entry.alignment = HORIZONTAL_ALIGNMENT_RIGHT; entry.add_theme_font_size_override("font_size",12)
	entry.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); entry.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	entry.text_submitted.connect(submit_entry); body.add_child(entry); entry.hide()

func caption(parent: Node, text: String, point: Vector2, dimensions: Vector2) -> Label:
	var label := Label.new(); label.text = text; label.position = point; label.size = dimensions
	label.add_theme_font_size_override("font_size",12); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label); return label

func maximum(key: String) -> int:
	if not area.has("tile_count"): return -1
	return mini(32767,maxi(0,int(area.tile_count) - (1 if key == "wheelbarrows" else 0)))

func display(value: Dictionary, can_edit: bool) -> void:
	if int(value.get("id",-1)) != int(area.get("id",-1)) or int(value.get("revision",0)) != int(area.get("revision",0)) or not can_edit: cancel_edit()
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
		cancel_edit(); editing = key; labels[key].hide()
		entry.position = Vector2(136,48 + KEYS.find(key) * 36)
		entry.text = ""; entry.show(); entry.grab_focus()
	else:
		value_requested.emit(key,int(area[key]) + (1 if action == 1 else -1))

func submit_entry(value: String) -> void:
	if editing.is_empty() or not enabled or not value.is_valid_int(): return
	var amount := int(value)
	if amount < 0 or amount > maximum(editing): return
	var key := editing; cancel_edit()
	if amount != int(area[key]): value_requested.emit(key,amount)

func cancel_edit() -> bool:
	if editing.is_empty(): return false
	labels[editing].show(); editing = ""; entry.hide(); entry.release_focus()
	return true
