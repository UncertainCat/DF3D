extends RefCounted
# Presentation preferences only. Never changes the 3D viewport/render scale.
static var ui_scale := 1.0
static var targeting_grid := true
static var visual_style := "classic"
static var animation_strength := 0.55
static var combat_effects := true
static var truescale := false
static var camera_mode := ""
static var move_speed := 20.0
static var loaded := false

static func storage_path() -> String:
	var override := OS.get_environment("DF3D_UI_SETTINGS_PATH")
	return override if not override.is_empty() else "user://presentation.cfg"

static func load_preferences(path := ""):
	if loaded and path.is_empty(): return
	loaded = true
	var config := ConfigFile.new()
	if config.load(storage_path() if path.is_empty() else path) != OK: return
	ui_scale = clampf(float(config.get_value("interface", "scale", 1.0)), 0.75, 2.0)
	targeting_grid = bool(config.get_value("interface", "targeting_grid", true))
	visual_style = str(config.get_value("graphics", "style", "hd2d" if bool(config.get_value("graphics", "hd2d", false)) else "classic"))
	if visual_style == "hd2d": visual_style = "billboard"
	if visual_style not in ["classic", "billboard"]: visual_style = "classic"
	animation_strength = 0.55 # Fixed Subtle preset while the control is hidden.
	combat_effects = bool(config.get_value("graphics", "combat_effects", true))
	truescale = bool(config.get_value("graphics", "truescale", false))
	camera_mode = str(config.get_value("camera", "mode", ""))
	if camera_mode not in ["", "df", "isometric", "free"]: camera_mode = ""
	move_speed = clampf(float(config.get_value("camera", "move_speed", 20.0)), 5.0, 80.0)

static func save_preferences(path := "") -> Error:
	var config := ConfigFile.new()
	config.set_value("interface", "scale", ui_scale)
	config.set_value("interface", "targeting_grid", targeting_grid)
	config.set_value("graphics", "style", visual_style)
	config.set_value("graphics", "animation_strength", animation_strength)
	config.set_value("graphics", "combat_effects", combat_effects)
	config.set_value("graphics", "truescale", truescale)
	config.set_value("camera", "mode", camera_mode)
	config.set_value("camera", "move_speed", move_speed)
	return config.save(storage_path() if path.is_empty() else path)

static func effective_scale(view: Vector2) -> float:
	# Keep navigation reachable in small windows. The requested setting is
	# retained and automatically restored when the window grows again.
	return minf(ui_scale, minf(view.x / 640.0, view.y / 480.0))
