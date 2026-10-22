extends "res://scripts/setup_view.gd"

var channel := OS.get_environment("DF3D_SETUP_CHANNEL")
var suggestions: Array = []
var inspections: Dictionary = {}
var integration := "clean"
var save_paths: Array = []
var artwork_path := ""

func start() -> void:
	mock_mode = false
	var result := await request("bootstrap")
	if not result.get("ok", false):
		push_error(result.get("error", "Setup unavailable"))
		quit(1)
		return
	suggestions = result.get("suggestions", [])
	inspections = result.get("inspections", {})
	var remembered: String = result.get("installation", "")
	if not remembered.is_empty() and not suggestions.has(remembered): suggestions.push_front(remembered)
	super.start()
	if not remembered.is_empty():
		await target(remembered)
		if not next_button.disabled and accepted:
			await proceed()

# One outstanding request at a time, published atomically to this launcher's private channel.
func request(action: String) -> Dictionary:
	if operation_pending: return {"ok": false, "error": "Setup is busy."}
	operation_pending = true
	var shield: Control
	if canvas != null:
		shield = Control.new()
		canvas.add_child(shield)
		shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shield.mouse_filter = Control.MOUSE_FILTER_STOP
		shield.focus_mode = Control.FOCUS_ALL
		shield.grab_focus()
		shield.gui_input.connect(func(_event): shield.accept_event())
	var file := FileAccess.open(channel.path_join("request.tmp"), FileAccess.WRITE)
	if file == null:
		operation_pending = false
		if shield != null: shield.queue_free()
		return {"ok": false, "error": "Cannot contact the launcher."}
	file.store_string(JSON.stringify({"action": action, "path": selected}))
	file.close()
	DirAccess.rename_absolute(channel.path_join("request.tmp"), channel.path_join("request.json"))
	# Installation and owned game sessions may be long-lived. Never retry a mutation.
	while not FileAccess.file_exists(channel.path_join("response.json")):
		await create_timer(0.1).timeout
	var result = JSON.parse_string(FileAccess.get_file_as_string(channel.path_join("response.json")))
	DirAccess.remove_absolute(channel.path_join("response.json"))
	operation_pending = false
	if shield != null: shield.queue_free()
	if not result is Dictionary: return {"ok": false, "error": "Invalid launcher response."}
	return result

func choose() -> void:
	screen("choose", "Choose Dwarf Fortress installation", false)
	choices.clear()
	var group := ButtonGroup.new()
	for candidate in suggestions:
		var path: String = candidate
		var status: Dictionary = inspections.get(path, {})
		var label := path
		if status.has("ok"):
			label += "\n" + ("DF 53.16" if status.ok else "Unsupported installation")
		var select := button(body, label, func(): await target(path))
		if status.has("ok") and not status.ok:
			select.add_theme_color_override("font_color", Color("ff6666"))
		select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		select.tooltip_text = path
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.toggle_mode = true
		select.button_group = group
		select.custom_minimum_size.y = 76
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("27577c") if state in ["pressed", "hover_pressed"] else Color("303030") if state == "hover" else Color("242424")
			style.content_margin_left = 12
			style.content_margin_right = 12
			select.add_theme_stylebox_override(state, style)
		select.button_pressed = selected == path
		choices[path] = select
	button(body, "Browse…", browse)
	notice = text("")
	var row := actions()
	button(row, "Restore bridge files", restore)
	next_button = button(row, "Continue", proceed)
	next_button.disabled = true

func target(path: String) -> void:
	if operation_pending: return
	selected = path
	next_button.disabled = true
	notice.text = "" if inspections.has(path) else "Checking installation…"
	notice.remove_theme_color_override("font_color")
	var result := await request("target")
	inspections[path] = result
	for candidate in choices: choices[candidate].set_pressed_no_signal(candidate == path)
	if not result.get("ok", false):
		accepted = false
		installed = false
		notice.text = result.get("error", "Unsupported installation.")
		notice.add_theme_color_override("font_color", Color("ff6666"))
		return
	integration = result.get("state", "clean")
	installed = integration == "current"
	accepted = result.get("accepted", false)
	save_paths = result.get("saves", [selected.path_join("save")])
	if not choices.has(path):
		suggestions.push_front(path)
		choose()
	notice.text = ""
	next_button.disabled = false

func proceed() -> void:
	if operation_pending or next_button.disabled: return
	if artwork_path != selected:
		if not load_art(selected):
			notice.text = "Could not load Dwarf Fortress artwork."
			return
		artwork_path = selected
	if not accepted: acknowledge()
	elif installed: await launch()
	else: ready()

func save_locations() -> Array:
	return save_paths

func accept_notice() -> void:
	if not acknowledgment.button_pressed or operation_pending: return
	var result := await request("accept")
	if not result.get("ok", false): failure(result); return
	accepted = true
	if installed: await launch()
	else: ready()

func ready() -> void:
	scenario = 5 if integration == "update" else 0
	super.ready()

func install() -> void:
	if not accepted or operation_pending: return
	screen("installing", "Setting up DF3D")
	var progress := ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	body.add_child(progress)
	var result := await request("install")
	if not result.get("ok", false): failure(result); return
	installed = true
	screen("done", "DF3D is ready")
	button(actions(), "Launch DF3D", launch)

func launch() -> void:
	if operation_pending: return
	var game_scene := load("res://scenes/main.tscn") as PackedScene
	if game_scene == null:
		failure({"error": "Could not load DF3D."})
		return
	screen("starting", "Starting DF3D")
	var result := await request("play")
	if not result.get("ok", false): failure(result); return
	OS.set_environment("DF3D_DF_PATH", selected)
	OS.set_environment("DF3D_RELEASE", "1")
	OS.unset_environment("DF3D_SETUP_CHANNEL")
	root.min_size = Vector2i.ZERO
	root.max_size = Vector2i.ZERO
	root.unresizable = not ProjectSettings.get_setting("display/window/size/resizable", true)
	var dimensions := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width", 1600), ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	var usable := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.size = dimensions.min((usable.size - Vector2i(32, 64)).max(Vector2i(640, 480)))
	root.position = usable.position + (usable.size - root.size) / 2
	var error := get_tree().change_scene_to_packed(game_scene)
	if error != OK:
		await request("abort-play")
		root.size = Vector2i(900, 620)
		root.min_size = root.size
		root.max_size = root.size
		root.unresizable = true
		failure({"error": "Could not open DF3D."})

func restore() -> void:
	var result := await request("restore")
	choose()
	if not result.get("ok", false): notice.text = result.get("error", "Restore failed.")
	else: notice.text = "Choose an installation to continue."

func failure(result: Dictionary) -> void:
	screen("failed", "Setup couldn't finish", not artwork_path.is_empty())
	text(result.get("error", "Open diagnostics for details."))
	button(actions(), "Choose installation", choose)
