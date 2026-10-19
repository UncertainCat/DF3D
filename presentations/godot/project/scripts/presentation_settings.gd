extends RefCounted
# Presentation preferences only. Never changes the 3D viewport/render scale.
static var ui_scale := 1.0
static var ui_auto_scale := true
static var targeting_grid := true
static var visual_style := "classic"
static var native_world_rendering := false
static var texture_smoothing := false
static var animation_strength := 0.55
static var combat_effects := true
static var truescale := false
static var camera_mode := ""
static var move_speed := 20.0
static var loaded := false
static var display_configured := false
static var window_mode := "windowed"
static var window_size := Vector2i(1600,900)

static func storage_path() -> String:
	var override := OS.get_environment("DF3D_UI_SETTINGS_PATH")
	return override if not override.is_empty() else "user://presentation.cfg"

static func load_preferences(path := ""):
	if loaded and path.is_empty(): return
	loaded = true
	var config := ConfigFile.new()
	if config.load(storage_path() if path.is_empty() else path) != OK: return
	display_configured = bool(config.get_value("display", "configured", false))
	window_mode = str(config.get_value("display", "mode", "windowed"))
	if window_mode not in ["windowed","fullscreen"]: window_mode = "windowed"
	window_size = Vector2i(clampi(int(config.get_value("display","width",1600)),640,7680),clampi(int(config.get_value("display","height",900)),480,4320))
	ui_scale = clampf(float(config.get_value("interface", "scale", 1.0)), 0.75, 4.0)
	# Preserve deliberate legacy custom sizes; the old default gains auto sizing.
	ui_auto_scale = bool(config.get_value("interface", "auto_scale", is_equal_approx(ui_scale,1.0)))
	targeting_grid = bool(config.get_value("interface", "targeting_grid", true))
	visual_style = str(config.get_value("graphics", "style", "hd2d" if bool(config.get_value("graphics", "hd2d", false)) else "classic"))
	if visual_style == "hd2d": visual_style = "billboard"
	if visual_style not in ["classic", "billboard"]: visual_style = "classic"
	animation_strength = 0.55 # Fixed Subtle preset while the control is hidden.
	native_world_rendering = bool(config.get_value("graphics", "native_world_rendering", false))
	texture_smoothing = bool(config.get_value("graphics", "texture_smoothing", false))
	combat_effects = bool(config.get_value("graphics", "combat_effects", true))
	truescale = bool(config.get_value("graphics", "truescale", false))
	camera_mode = str(config.get_value("camera", "mode", ""))
	if camera_mode not in ["", "df", "isometric", "free"]: camera_mode = ""
	move_speed = clampf(float(config.get_value("camera", "move_speed", 20.0)), 5.0, 80.0)

static func save_preferences(path := "") -> Error:
	var config := ConfigFile.new()
	config.set_value("display","configured",display_configured)
	config.set_value("display","mode",window_mode)
	config.set_value("display","width",window_size.x)
	config.set_value("display","height",window_size.y)
	config.set_value("interface", "scale", ui_scale)
	config.set_value("interface", "auto_scale", ui_auto_scale)
	config.set_value("interface", "targeting_grid", targeting_grid)
	config.set_value("graphics", "style", visual_style)
	config.set_value("graphics", "native_world_rendering", native_world_rendering)
	config.set_value("graphics", "texture_smoothing", texture_smoothing)
	config.set_value("graphics", "animation_strength", animation_strength)
	config.set_value("graphics", "combat_effects", combat_effects)
	config.set_value("graphics", "truescale", truescale)
	config.set_value("camera", "mode", camera_mode)
	config.set_value("camera", "move_speed", move_speed)
	return config.save(storage_path() if path.is_empty() else path)

static func effective_scale(view: Vector2) -> float:
	return effective_scale_vector(view).x

static func effective_scale_vector(view: Vector2) -> Vector2:
	if ui_auto_scale:
		# DF53.16's default desired grid is 190x64, based on 8x12 cells.
		# Keep whole-pixel cells; e.g. a 2560x1440 window uses 13x19 cells.
		var width := maxf(8.0, floorf(minf(view.x/190.0, view.y/96.0)))
		var automatic := Vector2(width/8.0, floorf(width*1.5)/12.0)
		return automatic.min(Vector2.ONE * minf(view.x/640.0,view.y/480.0))
	# Keep navigation reachable in small windows. The requested setting is
	# retained and automatically restored when the window grows again.
	return Vector2.ONE * minf(ui_scale, minf(view.x / 640.0, view.y / 480.0))

static func apply_window_preferences(window: Window) -> void:
	if not display_configured or DisplayServer.get_name()=="headless": return
	await apply_window_values(window,window_mode,window_size)

static func apply_window_values(window: Window, mode: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name()=="headless": return
	var drawing := RenderingServer.render_loop_enabled
	RenderingServer.render_loop_enabled = false
	RenderingServer.force_sync()
	if mode=="fullscreen":
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		await window.get_tree().process_frame
		if not is_instance_valid(window):
			RenderingServer.render_loop_enabled = drawing
			return
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		window.size = dimensions.min((usable.size-Vector2i(32,64)).max(Vector2i(640,480)))
		window.position = usable.position+(usable.size-window.size)/2

	await window.get_tree().process_frame
	RenderingServer.force_sync()
	RenderingServer.render_loop_enabled = drawing
