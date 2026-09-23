extends Control
# Native scrollbar artwork; the silhouette is sampled from known outdoor ground
# at the camera's map column. Hidden caves never enter this overview.
signal level_requested(level: int)
var world
var hud
var camera_rig
var data: Dictionary = {}
var art: Dictionary = {}
var elapsed := 1.0
var dragging := false

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for key in ["SCROLLBAR", "SCROLLBAR_SKY", "SCROLLBAR_GROUND", "SCROLLBAR_UNDERGROUND", "SCROLLBAR_CENTER_SCROLLER"]:
		if key == "SCROLLBAR":
			art[key] = world.ui_texture(key)
		else:
			art[key] = [world.ui_texture(key, 0), world.ui_texture(key, 1)]

static func level_at(point_y: float, height: float, count: int) -> int:
	if count <= 1: return 0
	return clampi(int((1.0 - clampf((point_y - 12.0) / maxf(1, height - 24.0), 0, 1)) * count), 0, count - 1)

func _process(delta: float):
	var rect: Rect2 = hud.elevation_rect()
	position = rect.position
	size = rect.size
	elapsed += delta
	if elapsed >= 0.25:
		elapsed = 0
		data = world.elevation_overview(floori(camera_rig.position.x), floori(camera_rig.position.z))
		tooltip_text = "Elevation %d · click or drag to change level\nSurface at camera position; unexplored terrain is not shown" % (world.get_top_z() + int(hud.summary.get("elevation_offset", 0)))
	queue_redraw()

func strip(key: String, rect: Rect2):
	var pieces: Array = art.get(key, [])
	for i in pieces.size():
		if pieces[i] != null:
			draw_texture_rect(pieces[i], Rect2(rect.position + Vector2(i * size.x / 2, 0), Vector2(size.x / 2, rect.size.y)), false)

func _draw():
	if size.y <= 24: return
	var height := size.y - 24
	var count := int(data.get("level_count", 0))
	draw_rect(Rect2(Vector2.ZERO, size), Color("302c34"))
	var surface := int(data.get("surface_z", -1))
	if count > 0 and surface >= 0:
		var ground_y := 12.0 + height * (1.0 - float(surface + 1) / count)
		strip("SCROLLBAR_SKY", Rect2(0, 12, size.x, ground_y - 12))
		strip("SCROLLBAR_GROUND", Rect2(0, ground_y, size.x, minf(12, size.y - 12 - ground_y)))
		var y := ground_y + 12
		while y < size.y - 12:
			strip("SCROLLBAR_UNDERGROUND", Rect2(0, y, size.x, minf(12, size.y - 12 - y)))
			y += 12
	var scrollbar: Texture2D = art.get("SCROLLBAR")
	if scrollbar != null:
		draw_texture_rect_region(scrollbar, Rect2(0, 0, size.x, 12), Rect2(0, 0, 16, 12))
		draw_texture_rect_region(scrollbar, Rect2(0, size.y - 12, size.x, 12), Rect2(0, 24, 16, 12))
	if count > 0:
		var selected_y: float = 12 + height * (1.0 - (world.get_top_z() + 0.5) / count)
		strip("SCROLLBAR_CENTER_SCROLLER", Rect2(0, clampf(selected_y - 6, 12, size.y - 24), size.x, 12))

func navigate(point_y: float):
	if not hud.minimap.allowed: return
	var count := int(data.get("level_count", 0))
	if count <= 0: return
	var level := level_at(point_y, size.y, count)
	if point_y < 12: level = mini(count - 1, world.get_top_z() + 1)
	elif point_y >= size.y - 12: level = maxi(0, world.get_top_z() - 1)
	level_requested.emit(level)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed and hud.minimap.allowed
			if dragging: navigate(event.position.y)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			navigate(0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else size.y)
	elif event is InputEventMouseMotion:
		accept_event()
		if dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT: navigate(event.position.y)
