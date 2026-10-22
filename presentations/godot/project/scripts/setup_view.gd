extends Node
var root: Window

func create_timer(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(seconds)

func quit(code := 0) -> void:
	get_tree().quit(code)
# Shared setup presentation. The mock overrides no installation or launch backend.
var mock_mode := true
var operation_pending := false
const SAMPLES := ["C:/Steam/steamapps/common/Dwarf Fortress", "D:/Games/Dwarf Fortress"]
const SCENARIOS := ["First setup", "No suggestions", "Unsupported version", "Install fails", "Returning player", "Update required", "Other DFHack"]
var art = preload("res://scripts/original_ui.gd").new()
var world: Df3dWorld
var canvas: Control
var card: PanelContainer
var body: VBoxContainer
var scenario := 0
var selected := ""
var accepted := false
var installed := false
var generation := 0
var page := ""
var next_button: Button
var acknowledgment: Button
var notice: Label
var choices: Dictionary = {}
var test_mode := false
var godot_icon: TextureRect
var bounce_time := 0.0
var walkers = preload("res://scripts/setup_walkers.gd").new()

func _ready() -> void:
	root = get_tree().root
	call_deferred("start")

func _on_setup_close_requested() -> void:
	if page == "starting" or (not operation_pending and page != "installing"): quit()

func _exit_tree() -> void:
	if root != null and root.close_requested.is_connected(_on_setup_close_requested):
		root.close_requested.disconnect(_on_setup_close_requested)

func start() -> void:
	test_mode = "--self-test" in OS.get_cmdline_user_args()
	root.title = "DF3D setup mock" if mock_mode else "DF3D"
	get_tree().auto_accept_quit = false
	root.close_requested.connect(_on_setup_close_requested)
	root.size = Vector2i(900, 620)
	root.min_size = root.size
	root.max_size = root.size
	root.unresizable = true
	if mock_mode: load_art(OS.get_environment("DF3D_DF_PATH"))
	canvas = Control.new()
	add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("181818")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(walkers)
	var icon_path := OS.get_environment("DF3D_MOCK_GODOT_ICON") if mock_mode else OS.get_environment("DF3D_SETUP_ICON")
	if FileAccess.file_exists(icon_path):
		godot_icon = TextureRect.new()
		var icon_image := Image.load_from_file(icon_path)
		icon_image.generate_mipmaps()
		godot_icon.texture = ImageTexture.create_from_image(icon_image)
		godot_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		godot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		godot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		godot_icon.size = Vector2(48, 48)
		godot_icon.pivot_offset = godot_icon.size / 2
		godot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(godot_icon)
	if mock_mode:
		var harness := HBoxContainer.new()
		canvas.add_child(harness)
		harness.position = Vector2(16, 12)
		harness.add_theme_constant_override("separation", 12)
		var caption := Label.new()
		caption.text = "MOCK (no file changes)"
		harness.add_child(caption)
		var scenarios := OptionButton.new()
		for title in SCENARIOS: scenarios.add_item(title)
		harness.add_child(scenarios)
		scenarios.item_selected.connect(reset)
		button(harness, "Restart", func(): reset(scenario))
		button(harness, "Reopen", reopen)
	card = PanelContainer.new()
	canvas.add_child(card)
	# Defer minimum-size updates; never change size inside a resized callback.
	card.minimum_size_changed.connect(func(): call_deferred("layout"))
	if mock_mode: reset(0)
	else: choose()
	if test_mode: await exercise()

func _process(delta: float) -> void:
	if godot_icon == null or not godot_icon.visible: return
	bounce_time += delta
	var phase := fposmod(bounce_time * 1.25, 1.0)
	var hop := 4.0 * phase * (1.0 - phase)
	godot_icon.position = Vector2(24 + pingpong(bounce_time * 65, root.size.x - 96), root.size.y - 64 - hop * 26)
	godot_icon.rotation = sin(bounce_time * TAU * 1.25) * 0.10

func button(parent: Node, title: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = title
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func text(value: String) -> Label:
	var result := Label.new()
	result.text = value
	result.custom_minimum_size.x = 680
	result.size.x = 680
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(result)
	return result

func layout() -> void:
	if card == null: return
	card.size.x = 720
	card.size.y = card.get_combined_minimum_size().y
	card.position = ((Vector2(root.size) - card.size) / 2).round()

func screen(id: String, title: String, styled := true) -> void:
	page = id
	walkers.visible = styled
	if godot_icon != null: godot_icon.visible = id == "choose"
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	card.theme = art.theme if styled else Theme.new()
	if not styled: card.theme.default_font_size = 20
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if styled else CanvasItem.TEXTURE_FILTER_LINEAR
	if styled:
		card.add_theme_stylebox_override("panel", art.native_message_panel())
	else:
		card.remove_theme_stylebox_override("panel")
	body = VBoxContainer.new()
	body.custom_minimum_size.x = 680
	body.add_theme_constant_override("separation", 16)
	card.add_child(body)
	if styled:
		art.install_hud_filter(body)
		card.material = body.material
	else:
		card.material = null
	var heading := text(title)
	heading.add_theme_font_size_override("font_size", 24)
	call_deferred("layout")

func actions() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	return row

func reset(index: int) -> void:
	generation += 1
	scenario = index
	selected = ""
	accepted = false
	installed = false
	if index in [4, 5]:
		selected = SAMPLES[0]
		accepted = true
		installed = index == 4
	reopen()

func reopen() -> void:
	generation += 1
	if selected.is_empty(): choose()
	elif installed: launch()
	elif accepted: ready()
	else: acknowledge()

func choose() -> void:
	screen("choose", "Choose Dwarf Fortress installation", false)
	choices.clear()
	var group := ButtonGroup.new()
	if scenario != 1:
		for path in SAMPLES:
			var select := Button.new()
			select.toggle_mode = true
			select.button_group = group
			select.button_pressed = selected == path
			select.custom_minimum_size.y = 76
			for state in ["normal", "hover", "pressed", "hover_pressed"]:
				var style := StyleBoxFlat.new()
				style.bg_color = Color("27577c") if state in ["pressed", "hover_pressed"] else Color("303030") if state == "hover" else Color("242424")
				select.add_theme_stylebox_override(state, style)
			body.add_child(select)
			select.pressed.connect(func(): target(path))
			choices[path] = select
			var info := VBoxContainer.new()
			info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			select.add_child(info)
			info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			info.offset_left = 12
			info.offset_top = 8
			info.offset_right = -12
			info.offset_bottom = -8
			var location := Label.new()
			location.mouse_filter = Control.MOUSE_FILTER_IGNORE
			location.text = path
			info.add_child(location)
			var version := Label.new()
			version.mouse_filter = Control.MOUSE_FILTER_IGNORE
			version.text = "DF 53.15" if scenario == 2 else "DF 53.16"
			if scenario == 2: version.add_theme_color_override("font_color", Color("ff6666"))
			info.add_child(version)
			if scenario == 6:
				version.text = "DF 53.16 / Unsupported DFHack installation"
				version.add_theme_color_override("font_color", Color("ff6666"))
	button(body, "Browse…", browse)
	notice = text("Requires DF 53.16 (Steam build 24557528)." if scenario == 2 else "")
	if scenario == 1: notice.text = "Choose Dwarf Fortress.exe."
	if scenario == 6: notice.text = "Uninstall DFHack, then try again."
	var row := actions()
	next_button = button(row, "Continue", func():
		if not selected.is_empty() and scenario not in [2, 6]:
			if accepted: ready()
			else: acknowledge())
	next_button.disabled = selected.is_empty() or scenario in [2, 6]

func target(path: String) -> void:
	if path != selected: installed = false
	selected = path
	for candidate in choices:
		choices[candidate].set_pressed_no_signal(candidate == path)
	notice.text = "Requires DF 53.16 (Steam build 24557528)." if scenario == 2 else ("" if choices.has(path) else path)
	if scenario == 6: notice.text = "Uninstall DFHack, then try again."
	next_button.disabled = scenario in [2, 6]

func browse() -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.use_native_dialog = true
	picker.title = "Choose Dwarf Fortress.exe"
	picker.filters = PackedStringArray(["*.exe ; Dwarf Fortress.exe"])
	root.add_child(picker)
	picker.file_selected.connect(func(path):
		if path.get_file().to_lower() == "dwarf fortress.exe": target(path.get_base_dir())
		else:
			selected = ""
			notice.text = "Choose Dwarf Fortress.exe."
			next_button.disabled = true
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered(Vector2i(720, 480))

func acknowledge() -> void:
	screen("acknowledge", "Before you begin")
	text("DF3D is unstable and may corrupt saves.\nWe recommend backing up saves.")
	for saves in save_locations():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var path := Label.new()
		path.text = saves
		path.tooltip_text = saves
		path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(path)
		path.resized.connect(func(): path.text = compact_path(saves, path))
		var copy := button(row, "Copy path", func(): DisplayServer.clipboard_set(saves))
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		copy.pressed.connect(func(): copy.text = "Copied")
	acknowledgment = Button.new()
	acknowledgment.toggle_mode = true
	acknowledgment.text = "[X]" if accepted else "[ ]"
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		acknowledgment.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	acknowledgment.button_pressed = accepted
	var agreement := HBoxContainer.new()
	agreement.add_theme_constant_override("separation", 12)
	body.add_child(agreement)
	agreement.add_child(acknowledgment)
	var agreement_text := Label.new()
	agreement_text.text = "I understand DF3D is unstable."
	agreement_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	agreement.add_child(agreement_text)
	var navigation := actions()
	button(navigation, "Back", choose)
	next_button = button(navigation, "Continue", accept_notice)
	next_button.disabled = not accepted
	acknowledgment.toggled.connect(func(value):
		acknowledgment.text = "[X]" if value else "[ ]"
		next_button.disabled = not value)

func compact_path(full_path: String, label: Label) -> String:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var separator := "\\" if full_path.contains("\\") else "/"
	var parts := full_path.replace("\\", "/").split("/")
	if font.get_string_size(full_path, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x: return full_path
	# Keep the location's leading folders, so installation and roaming saves
	# remain distinguishable even when both end in Dwarf Fortress/save.
	for count in range(parts.size() - 2, 0, -1):
		var abbreviated := separator.join(parts.slice(0, count)) + separator + "..." + separator + parts[-1]
		if font.get_string_size(abbreviated, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x: return abbreviated
	var remaining := full_path.length()
	var display := full_path
	while remaining > 8 and font.get_string_size(display, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		remaining -= 1
		var prefix := remaining / 2
		display = full_path.left(prefix) + "..." + full_path.right(remaining - prefix)
	return display

func accept_notice() -> void:
	if not acknowledgment.button_pressed: return
	accepted = true
	ready()

func ready() -> void:
	screen("ready", "Update DF3D" if scenario == 5 else "Set up DF3D")
	text(selected)
	if scenario == 5: text("The installed DF3D version differs.")
	text("Installs DFHack + DF3D. Backs up replaced files.")
	var row := actions()
	button(row, "Back", choose)
	button(row, "Update" if scenario == 5 else "Install", install)

func install() -> void:
	if selected.is_empty() or not accepted: return
	generation += 1
	var ticket := generation
	screen("installing", "Setting up DF3D")
	var progress := ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	body.add_child(progress)
	await create_timer(0.01 if test_mode else 1.5).timeout
	if ticket != generation: return
	if scenario == 3:
		screen("failed", "Setup couldn't finish")
		text("The installation folder isn't writable.")
		var row := actions()
		button(row, "Change installation", choose)
		button(row, "Retry", install)
		return
	installed = true
	screen("done", "DF3D is ready")
	button(actions(), "Launch DF3D", launch)

func launch() -> void:
	screen("launched", "Launch simulated")
	button(actions(), "Change installation", choose)

func exercise() -> void:
	assert(root.unresizable and root.min_size == root.max_size)
	assert(next_button.disabled)
	target(SAMPLES[1])
	assert(not next_button.disabled)
	acknowledge()
	assert(next_button.disabled)
	accept_notice()
	assert(page == "acknowledge" and not accepted)
	acknowledgment.button_pressed = true
	accept_notice()
	assert(page == "ready" and accepted)
	await install()
	assert(installed and page == "done")
	reopen()
	assert(page == "launched")
	reset(2)
	target(SAMPLES[0])
	assert(next_button.disabled)
	reset(3)
	target(SAMPLES[0])
	accepted = true
	await install()
	assert(page == "failed" and not installed)
	reset(6)
	target(SAMPLES[0])
	assert(next_button.disabled and not accepted and not installed)
	next_button.pressed.emit()
	assert(page == "choose")
	reset(5)
	assert(page == "ready" and accepted and not installed)
	install()
	reset(1)
	await create_timer(0.03).timeout
	assert(page == "choose" and not installed and selected.is_empty())
	target(SAMPLES[0])
	acknowledge()
	assert(walkers.textures.size() == walkers.VARIANT_COUNT)
	walkers._process(1.0)
	assert(walkers.walkers.size() == 1)
	var first_x: float = walkers.walkers[0].x
	walkers._process(0.1)
	assert(walkers.walkers[0].x != first_x)
	for speed in [-40.0, 40.0]:
		walkers.walkers[0].speed = speed
		walkers._process(0.1)
		assert(walkers.walkers[0].sprite.flip_h == (speed > 0))
	walkers.walkers[0].x = 180.0
	for i in 4: await get_tree().process_frame
	assert(card.size.y < 480 and card.position.y >= 50)
	if DisplayServer.get_name() != "headless":
		var lineup := Image.create_empty(16 * 40, 6 * 40, false, Image.FORMAT_RGBA8)
		lineup.fill(Color("181818"))
		for index in walkers.textures.size():
			lineup.blend_rect(walkers.textures[index].get_image(), Rect2i(0, 0, 32, 32), Vector2i(((index % 8) + (index / 48) * 8) * 40 + 4, ((index % 48) / 8) * 40 + 4))
		lineup.resize(1280, 480, Image.INTERPOLATE_NEAREST)
		lineup.save_png(OS.get_environment("DF3D_MOCK_CAPTURE").get_base_dir().path_join("dwarf-lineup.png"))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DF3D_MOCK_CAPTURE"))
		reset(2)
		for i in 4: await get_tree().process_frame
		assert(card.size.x <= root.size.x and card.position.y >= 50)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DF3D_MOCK_CAPTURE").get_base_dir().path_join("unsupported.png"))
		reset(6)
		target(SAMPLES[0])
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DF3D_MOCK_CAPTURE").get_base_dir().path_join("foreign-dfhack.png"))
	print("SETUP_MOCK_PASS")
	quit()

func load_art(installation: String) -> bool:
	if world != null: world.queue_free()
	world = Df3dWorld.new()
	add_child(world)
	if not world.load_assets(installation):
		push_error("Mock requires the supported DF installation for read-only UI artwork.")
		return false
	art.configure(world)
	walkers.load_art(installation)
	# The installed font is 12px: 2x keeps every bitmap stroke uniform.
	art.theme.default_font_size = 24
	# The native button is a 3x3 grid of 8x12 cells.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := art.theme.get_stylebox(state, "Button") as StyleBoxTexture
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			style.set_texture_margin(side, 8)
			style.set_content_margin(side, 16)
		for side in [SIDE_TOP, SIDE_BOTTOM]: style.set_texture_margin(side, 12)
	return true


func save_locations() -> Array:
	return [selected.path_join("save"), "C:/Users/Player/AppData/Roaming/Bay 12 Games/Dwarf Fortress/save"]
