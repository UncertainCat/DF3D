extends CanvasLayer
# Runtime-only installed artwork; all save semantics come from Df3dWorld.
var world
var audio: Node
var saves: Array = []
var selected_id := ""
var pending_seq := 0
var can_attach := false
var entered := false
var phase := 4
var _signature := ""
var _result_message := ""
var _selected_save_result := ""
var list: ItemList
var load_button: Button
var heading: Label
var message: Label
var detail: Label
var background: TextureRect
var logo: TextureRect

func _ready() -> void:
	layer = 4
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background = TextureRect.new()
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wash := ColorRect.new()
	wash.color = Color(0.025, 0.035, 0.055, 0.22)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	var outer := HBoxContainer.new()
	margin.add_child(outer)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.44
	outer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.048, 0.064, 0.94)
	style.border_color = Color(0.58, 0.45, 0.25, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.size_flags_stretch_ratio = 0.56
	outer.add_child(space)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	logo = TextureRect.new()
	logo.custom_minimum_size.y = 120
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(logo)
	var brand := Label.new()
	brand.text = "D F 3 D   /   A NEW VIEW OF YOUR FORTRESS"
	brand.add_theme_font_size_override("font_size", 13)
	brand.add_theme_color_override("font_color", Color("c7ab77"))
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(brand)
	heading = Label.new()
	heading.text = "Continue a fortress"
	heading.add_theme_font_size_override("font_size", 28)
	box.add_child(heading)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 50
	message.text = "Connecting to Dwarf Fortress..."
	box.add_child(message)
	list = ItemList.new()
	list.name = "FortressList"
	list.max_text_lines = 2
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(200, 90)
	list.add_theme_font_size_override("font_size", 18)
	list.add_theme_constant_override("line_separation", 8)
	list.add_theme_constant_override("v_separation", 12)
	list.item_selected.connect(_select)
	list.item_activated.connect(func(_index): request_load())
	box.add_child(list)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color("b5beca"))
	detail.custom_minimum_size.y = 38
	box.add_child(detail)
	load_button = Button.new()
	load_button.text = "Load Fortress"
	load_button.custom_minimum_size.y = 48
	load_button.disabled = true
	load_button.pressed.connect(request_load)
	box.add_child(load_button)
	var quit := Button.new()
	quit.text = "Quit DF3D"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	var credit := Label.new()
	credit.text = "Dwarf Fortress by Bay 12 Games · Published by Kitfox Games\nArtwork loaded from your installed copy."
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size.y = 30
	credit.add_theme_font_size_override("font_size", 11)
	credit.modulate = Color("939cac")
	box.add_child(credit)
	var resize_ui := func():
		space.visible = root.size.x >= 1050
		var compact := root.size.y < 760
		logo.custom_minimum_size.y = 50 if compact else 120
		box.add_theme_constant_override("separation", 5 if compact else 12)
		heading.add_theme_font_size_override("font_size", 24 if compact else 28)
		message.custom_minimum_size.y = 32 if compact else 50
		detail.custom_minimum_size.y = 26 if compact else 38
		load_button.custom_minimum_size.y = 36 if compact else 48
	root.resized.connect(resize_ui)
	resize_ui.call_deferred()

func load_art(install_root: String) -> void:
	for pair in [[background, "title_background.png"], [logo, "df_logo.png"]]:
		var path := install_root.path_join("data/art").path_join(pair[1])
		if not FileAccess.file_exists(path): continue
		var image := Image.load_from_file(path)
		if image != null: pair[0].texture = ImageTexture.create_from_image(image)

func _select(index: int) -> void:
	if index < 0 or index >= saves.size(): return
	selected_id = saves[index].id
	detail.text = "%s · Year %s\nSave: %s" % [saves[index].get("world", ""), saves[index].get("year", "?"), selected_id]
	load_button.disabled = phase != 1 or pending_seq != 0
	if audio != null: audio.cue("select")

func request_load() -> void:
	if load_button.disabled or selected_id == "" or pending_seq != 0: return
	pending_seq = world.load_fortress(selected_id)
	if pending_seq == 0:
		_result_message = "The load request could not be sent. Please try again."
		message.text = _result_message
		if audio != null: audio.cue("rejected")
		return
	_result_message = ""
	message.text = "Opening your fortress in Dwarf Fortress..."
	load_button.disabled = true
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.focus_mode = Control.FOCUS_NONE
	if audio != null: audio.cue("click")

func update_session(state: Dictionary, terrain_ready: bool, preparation_error := "") -> void:
	var previous_phase := phase
	phase = state.get("phase", 4)
	if state.get("error", "") != "" and phase == 3: phase = 5
	if previous_phase == 4 and phase == 1:
		_result_message = ""
		_selected_save_result = ""
	var request_status: int = state.get("request_status", 0)
	var matched: bool = pending_seq != 0 and pending_seq == state.get("request_seq", 0)
	if matched and request_status in [2, 3]:
		pending_seq = 0
		if audio != null: audio.cue("accepted" if request_status == 2 else "rejected")
		if request_status == 3: _result_message = state.get("message", "Could not load this fortress.")
	if phase == 4:
		if pending_seq != 0: _result_message = "Connection lost during loading. Waiting for Dwarf Fortress to reconnect."
		pending_seq = 0
	# A receipt describes its own world, not every world subsequently loaded
	# through the native menu. Still expose a rejection for that same world.
	var receipt_epoch := int(state.get("request_fortress_epoch", 0))
	var current_epoch := int(state.get("fortress_epoch", 0))
	var newer_world: bool = state.get("fortress_valid", false) and current_epoch != 0 and current_epoch != receipt_epoch
	var load_rejected: bool = request_status == 3 and state.get("request_action", 0) == 0 and not newer_world
	can_attach = phase in [3, 6] and not load_rejected and pending_seq == 0
	entered = can_attach and (entered or terrain_ready)
	visible = not entered
	if entered: return
	var incoming: Array = state.get("saves", [])
	var signature := JSON.stringify(incoming)
	if signature != _signature:
		_signature = signature
		saves = incoming
		list.clear()
		for save in saves:
			var fort: String = save.get("fort", "")
			if fort.is_empty(): fort = "Unnamed fortress"
			list.add_item("%s  ·  Year %s" % [fort, save.get("year", "?")])
			list.set_item_tooltip(list.item_count - 1, save.id)
			if save.id == selected_id: list.select(list.item_count - 1)
		if not saves.any(func(save): return save.id == selected_id):
			selected_id = ""
			detail.text = ""
		if selected_id == "" and not saves.is_empty():
			list.select(0)
			_select(0)
			list.grab_focus()
	var saved_id: String = state.get("saved_save_id", "")
	var save_result := "%s:%s" % [state.get("request_seq", 0), saved_id]
	if phase == 1 and request_status == 2 and state.get("request_action", 0) == 2 and saved_id != "" and save_result != _selected_save_result:
		for i in range(saves.size()):
			if saves[i].id == saved_id:
				_selected_save_result = save_result
				list.select(i)
				_select(i)
				list.ensure_current_is_visible()
				_result_message = state.get("message", "Fortress saved.")
				break
	var busy := pending_seq != 0 or request_status == 1 or phase == 2
	load_button.disabled = phase != 1 or busy or selected_id == ""
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
	list.focus_mode = Control.FOCUS_NONE if busy else Control.FOCUS_ALL
	heading.text = "Loading your fortress" if busy or can_attach else "Continue a fortress"
	if busy:
		message.text = "Opening your fortress in Dwarf Fortress...\nLarge saves may take a little while."
	elif request_status == 3 and not newer_world:
		message.text = state.get("message", "Could not load this fortress. Select a save to retry.")
	elif can_attach:
		message.text = "Your fortress is loaded. Assembling the 3D view..." if preparation_error.is_empty() else "Dwarf Fortress loaded, but DF3D could not prepare the view:\n" + preparation_error
	elif _result_message != "":
		message.text = _result_message
	elif phase == 1:
		message.text = "Choose a fortress to continue. It will open paused." if not saves.is_empty() else "No active fortress saves found. Create a fortress in Dwarf Fortress first."
	else:
		message.text = state.get("message", "")
		if state.get("error", "") != "": message.text = state.error
		if message.text == "": message.text = "Connecting to Dwarf Fortress..."
		if phase == 4: message.text += "\nStart the game through the DF3D launcher, or run `enable df3d` in the DFHack console."
