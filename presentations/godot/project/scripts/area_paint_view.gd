extends Control
signal accept_requested
signal tool_selected(key: String)
signal cancel_requested
signal multi_requested
signal paint_requested
signal undo_requested
var art = preload("res://scripts/original_ui.gd").new()
var accept_button: Button
var tools: HBoxContainer
var buttons: Dictionary = {}
var icons: Dictionary = {}
var menu: Array = []
var prompt: Label
var zone_caption: Label
var zone_icon: TextureRect
var cancel_button: Button
var multi_button: Button
var paint_button: Button
var toolbar_host: Node
var multi_type := false
var multi_active := false
var multi_result: Label
var multi_rejected: Label
var native_styles: Dictionary = {}

func configure(source, rows: Array, tool_host: Node) -> void:
	art.configure(source); theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(312,48)
	toolbar_host = tool_host
	prompt = Label.new(); prompt.position = Vector2(8,0)
	prompt.text = "Click in the play area\nto paint the stockpile."
	prompt.add_theme_font_size_override("font_size",12); add_child(prompt)
	accept_button = Button.new(); accept_button.text = "Accept"
	accept_button.position = Vector2(232,0); accept_button.size = Vector2(80,36)
	accept_button.add_theme_font_size_override("font_size",12)
	for state in ["normal","hover","pressed","disabled"]:
		var token := "HORIZONTAL_OPTION_CONFIRM" if state != "disabled" else "HORIZONTAL_OPTION_INACTIVE"
		var style := art.make_style(token,8)
		style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
		accept_button.add_theme_stylebox_override(state,style)
	accept_button.pressed.connect(func():
		if multi_active: undo_requested.emit()
		else: accept_requested.emit())
	add_child(accept_button)
	tools = HBoxContainer.new(); tools.theme = art.theme
	tools.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tools.add_theme_constant_override("separation",0); tool_host.add_child(tools)
	menu = rows.duplicate(true)
	var tips := {"rectangle":"Left click to choose corners of a rectangle.","brush":"Hold left button to draw.",
		"erase":"Erase a portion of this stockpile.","remove":"Remove the stockpile being painted permanently."}
	for row in rows:
		var button := Button.new(); button.custom_minimum_size = Vector2(32,36)
		button.tooltip_text = tips.get(str(row.key),"")
		for state in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var icon := TextureRect.new(); icon.size = Vector2(32,36)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
		button.pressed.connect(func(): tool_selected.emit(str(row.key)))
		tools.add_child(button); buttons[row.key] = button; icons[row.key] = icon
	tools.hide()
	zone_icon = TextureRect.new(); zone_icon.position = Vector2(0,36); zone_icon.size = Vector2(32,36)
	zone_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; add_child(zone_icon)
	zone_caption = Label.new(); zone_caption.position = Vector2(40,36); zone_caption.size = Vector2(192,36)
	zone_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone_caption.add_theme_font_size_override("font_size",12); add_child(zone_caption)
	cancel_button = Button.new(); cancel_button.text = "Cancel"; cancel_button.position = Vector2(232,0)
	cancel_button.size = Vector2(80,36); add_child(cancel_button)
	cancel_button.pressed.connect(func(): cancel_requested.emit())
	multi_button = Button.new(); multi_button.text = "Multi"; multi_button.position = Vector2(232,84)
	multi_button.size = Vector2(80,36); multi_button.disabled = true
	multi_button.pressed.connect(func(): multi_requested.emit())
	add_child(multi_button)
	paint_button = Button.new(); paint_button.text = "Paint"; paint_button.position = Vector2(232,120)
	paint_button.size = Vector2(80,36)
	paint_button.pressed.connect(func(): paint_requested.emit())
	add_child(paint_button)
	for button in [cancel_button,multi_button,paint_button]:
		button.add_theme_font_size_override("font_size",12)
		for state in ["normal","hover","pressed","disabled"]:
			button.add_theme_stylebox_override(state,accept_button.get_theme_stylebox(state))
	for state in ["normal","hover","pressed"]:
		var style := art.make_style("HORIZONTAL_OPTION_REMOVE",8)
		style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
		cancel_button.add_theme_stylebox_override(state,style)
	accept_button.add_theme_color_override("font_disabled_color",Color.BLACK)
	multi_result = Label.new(); multi_result.position = Vector2(8,48)
	multi_result.add_theme_font_size_override("font_size",12); add_child(multi_result); multi_result.hide()
	# Native Multi uses LGREEN/LRED from the supported data/init/colors.txt;
	# confirmed pixel-for-pixel in multi_unused_bed / multi_rectangle captures.
	multi_result.add_theme_color_override("font_color",Color8(19,253,101))
	multi_result.add_theme_constant_override("line_spacing",0)
	multi_rejected = Label.new(); multi_rejected.position = Vector2(8,84)
	multi_rejected.add_theme_font_size_override("font_size",12)
	multi_rejected.add_theme_color_override("font_color",Color8(255,113,17))
	multi_rejected.add_theme_constant_override("line_spacing",0)
	add_child(multi_rejected); multi_rejected.hide()
	for token in ["HORIZONTAL_OPTION_CONFIRM","HORIZONTAL_OPTION_REMOVE","HORIZONTAL_OPTION_INACTIVE"]:
		var style := art.make_style(token,8)
		style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,0)
		native_styles[token] = style
	set_zone({})

func native_button(button: Button, token: String, disabled_token := "HORIZONTAL_OPTION_INACTIVE") -> void:
	# Native horizontal options place every caption at the same two-glyph inset.
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal","hover","pressed","disabled"]:
		var style: StyleBoxTexture = native_styles[disabled_token if state == "disabled" else token]
		style.set_content_margin(SIDE_LEFT,16)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_disabled_color"]:
		var caption_token: String = disabled_token if state == "font_disabled_color" else token
		button.add_theme_color_override(state,Color8(192,192,192) if caption_token == "HORIZONTAL_OPTION_INACTIVE" else Color.WHITE)

func set_zone(row: Dictionary) -> void:
	prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	var zone := not row.is_empty()
	multi_type = str(row.get("name","")) in ["Bedroom","Office","DiningHall","Tomb"]
	custom_minimum_size = Vector2(312,168 if zone else 48)
	prompt.text = "Click in the play area\nto paint the zone." if zone else "Click in the play area\nto paint the stockpile."
	accept_button.position.y = 36 if zone else 0
	for control in [zone_icon,zone_caption,cancel_button,multi_button,paint_button]: control.visible = zone
	if zone:
		zone_icon.texture = art.texture(str(row.icon))
		# Count data is supplied separately with current draft/session identity.
		zone_caption.text = str(row.label)
	var host: Node = self if zone else toolbar_host
	if tools.get_parent() != host: tools.reparent(host)
	if zone: tools.position = Vector2(0,72); tools.scale = Vector2.ONE
	buttons.erase.tooltip_text = "Erase a portion of this zone." if zone else "Erase a portion of this stockpile."
	buttons.remove.tooltip_text = "Remove the zone being painted permanently." if zone else "Remove the stockpile being painted permanently."

func set_counts(label: String, counts: Dictionary) -> void:
	zone_caption.text = label
	if int(counts.get("painted",-1)) >= 0 and int(counts.get("preview",-1)) >= 0:
		# Native062137 draft-preview-mixed.json, including actual erase input.
		zone_caption.text = "%s: %d + %d" % [label,int(counts.painted),int(counts.preview)]

func display(tool: String, ready: bool, editable: bool, existing: bool, erasing := false, removable := false) -> void:
	multi_active = false; multi_result.hide(); multi_rejected.hide(); accept_button.show(); accept_button.text = "Accept"
	native_button(accept_button,"HORIZONTAL_OPTION_CONFIRM")
	native_button(cancel_button,"HORIZONTAL_OPTION_REMOVE")
	native_button(multi_button,"HORIZONTAL_OPTION_INACTIVE")
	native_button(paint_button,"HORIZONTAL_OPTION_CONFIRM","HORIZONTAL_OPTION_CONFIRM")
	cancel_button.text = "Cancel"; multi_button.disabled = not editable; paint_button.disabled = true
	# Native existing-zone repaint keeps Accept and tools, omitting the new-zone
	# Cancel/Multi/Paint controls (native elevation capture230002).
	cancel_button.visible = zone_icon.visible and not existing
	for control in [multi_button,paint_button]:
		control.visible = zone_icon.visible and multi_type and not existing
	accept_button.disabled = not ready or not editable
	for row in menu:
		var token := str(row.icon)
		if str(row.key) == tool or (str(row.key) == "erase" and erasing): token = token.replace("_INACTIVE","_ACTIVE")
		icons[row.key].texture = art.texture(token)
		buttons[row.key].disabled = not editable or (str(row.key) == "remove" and not existing and not removable)
		icons[row.key].modulate = Color(0.5,0.5,0.5) if buttons[row.key].disabled else Color.WHITE

# Native53.16 text: paint-native-multi-224155, paint-native-rooms-001424,
# paint-native-counts-233937 and multi-undo-native-014920 captures under04-U.
# Lexemes/suffixes also recorded with executable hash in multi-native-copy.json.
# Compound/plural result layouts still require rendered live acceptance.
static func count_line(count: int, singular: String, plural: String, suffix: String) -> String:
	if count <= 0: return ""
	return (singular if count == 1 else "%d %s" % [count,plural]) + suffix

func display_multi(state, editable: bool) -> void:
	multi_active = true; tools.hide(); zone_icon.hide(); zone_caption.hide()
	var prompts := {1:"Select a rectangle\nwhich contains beds\nin order to form\nbedrooms.\n\nRooms with multiple beds\nwill be made into\ndormitories.",
		2:"Select a rectangle\nwhich contains chairs\nin order to form\nthrone rooms/studies.",
		3:"Select a rectangle\nwhich contains tables\nin order to form\ndining halls.",
		4:"Select a rectangle\nwhich contains coffins\nin order to form\ntombs."}
	var result: bool = state.has_result()
	prompt.text = "Select another rectangle\nto continue." if result else str(prompts.get(state.furniture,""))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; prompt.size.x = 216
	prompt.add_theme_constant_override("line_spacing",0)
	prompt.add_theme_color_override("font_color",Color.WHITE)
	native_button(cancel_button,"HORIZONTAL_OPTION_CONFIRM" if result else "HORIZONTAL_OPTION_REMOVE")
	native_button(accept_button,"HORIZONTAL_OPTION_REMOVE")
	native_button(multi_button,"HORIZONTAL_OPTION_CONFIRM","HORIZONTAL_OPTION_CONFIRM")
	native_button(paint_button,"HORIZONTAL_OPTION_INACTIVE")
	cancel_button.show(); cancel_button.text = "Done" if result else "Cancel"
	accept_button.text = "Undo"; accept_button.visible = result; accept_button.position.y = 36
	accept_button.disabled = not editable or not state.ready()
	multi_button.visible = not result; multi_button.disabled = true
	paint_button.visible = not result; paint_button.disabled = not editable
	var rows: Array[String] = []
	var rejections: Array[String] = []
	var names := {1:["Bedroom","bedrooms","Bed","beds"],2:["Office","offices","Chair","chairs"],
		3:["Dining hall","dining halls","Table","tables"],4:["Tomb","tombs","Coffin","coffins"]}
	var words: Array = names.get(state.furniture,[])
	if result and words.size() == 4:
		var observed: Dictionary = state.observed
		var dormitories := int(observed.get("rooms_dormitories",0))
		for line in [count_line(int(observed.get("rooms_created",0))-dormitories,words[0],words[1]," created."),
			count_line(dormitories,"Dormitory","dormitories"," created.")]:
			if not line.is_empty(): rows.append(line)
		for line in [count_line(int(observed.get("rooms_in_use",0)),words[2],words[3]," rejected (already in use.)"),
			count_line(int(observed.get("rooms_unenclosed",0)),words[2],words[3]," rejected (not enclosed.)")]:
			if not line.is_empty(): rejections.append(line)
	multi_result.text = "\n".join(rows); multi_result.visible = result
	multi_rejected.text = "\n".join(rejections); multi_rejected.visible = result
	custom_minimum_size = Vector2(312,168)
