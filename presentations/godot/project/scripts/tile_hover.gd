extends CanvasLayer
# Staged prototype, excluded by ui_availability.TILE_HOVER_AVAILABLE.
# describe() synthesizes copy from enum/token identifiers and is NOT native parity.
# Replace it with evidenced native mappings/semantic descriptions before exposure.
var world
var hud
var camera
var panel: PanelContainer
var description: Label
var timer := 0.0

func _ready():
	layer = 1
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	description = Label.new()
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.clip_text = true
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(description)
	var ui = preload("res://scripts/original_ui.gd").new()
	ui.configure(world)
	ui.apply(self)
	panel.add_theme_stylebox_override("panel", ui.compact_panel())
	panel.hide()

static func readable(value: String) -> String:
	return value.replace(":", " ").to_snake_case().replace("_", " ").capitalize()

static func describe(info: Dictionary) -> String:
	if info.is_empty(): return ""
	var shape := readable(str(info.get("shape", "")))
	if shape == "Empty": return "Open space"
	var token := str(info.get("material", "")).trim_prefix("INORGANIC:").trim_prefix("PLANT:")
	var material := readable(token.trim_suffix(":STRUCTURAL"))
	if material.is_empty(): material = readable(str(info.get("material_kind", "")))
	if material in ["None", "Unknown"]: material = ""
	var finish := "Engraved " if info.get("engraved", false) else ("Smooth " if info.get("smooth", false) else "")
	var text := (finish + material + " " + shape.to_lower()).strip_edges()
	if int(info.get("liquid_level", 0)) > 0:
		text += " · %s %d/7" % [readable(str(info.get("liquid", ""))), int(info.liquid_level)]
	return text

func show_tile(tile: Vector3i):
	description.text = describe(world.tile_hover_info(tile))
	panel.visible = not description.text.is_empty()
	if not panel.visible: return
	var factor: float = hud.ui_scale_value() if hud.has_method("ui_scale_value") else 1.0
	scale = Vector2(factor, factor)
	var view := get_viewport().get_visible_rect().size / factor
	var right := minf(hud.status_panel.get_rect().end.x, hud.level_controls.get_global_rect().position.x - 8)
	var width := minf(520, maxf(160, right - 12))
	panel.position = Vector2(maxf(8, right - width), hud.status_panel.get_rect().end.y + 8)
	panel.size = Vector2(minf(width, view.x - panel.position.x - 8), 36)

func _process(delta: float):
	if hud == null or not hud.visible or not hud.enabled or hud.settings.visible or hud.interaction.construction_active or not world.terrain_loaded():
		panel.hide()
		return
	if get_viewport().gui_get_hovered_control() != null:
		panel.hide()
		return
	timer -= delta
	if timer > 0: return
	timer = 0.08
	var mouse := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse):
		panel.hide()
		return
	var tile: Vector3i = world.pick_tile(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse), world.get_top_z())
	show_tile(tile)
