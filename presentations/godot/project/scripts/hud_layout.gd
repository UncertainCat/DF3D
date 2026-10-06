extends RefCounted
# All rectangles are logical UI pixels, before the CanvasLayer transform.
const LEFT_RAIL := 48.0
const TOP := 88.0
const BOTTOM := 56.0
const ELEVATION_WIDTH := 16.0

static func minimap_width(view: Vector2) -> float:
	return 192.0 # Native map content is24 UI cells at supported reference widths.

static func has_minimap(view: Vector2) -> bool:
	return view.x >= 900 and view.y >= 600

static func right_reserve(view: Vector2) -> float:
	return minimap_width(view) + 40.0 if has_minimap(view) else 24.0

static func info_rect(view: Vector2) -> Rect2:
	var origin := Vector2(LEFT_RAIL, TOP)
	return Rect2(origin, Vector2(maxf(320, view.x - origin.x - right_reserve(view)), maxf(220, view.y - origin.y - BOTTOM)))

static func notification_rect(view: Vector2) -> Rect2:
	return Rect2(0, TOP + 48, LEFT_RAIL - 8, maxf(0, view.y - TOP - BOTTOM - 48))

static func elevation_rect(view: Vector2, minimap_bottom: float) -> Rect2:
	var top := minimap_bottom + 4.0 if has_minimap(view) else TOP
	return Rect2(view.x - ELEVATION_WIDTH, top, ELEVATION_WIDTH, maxf(0, view.y - top - BOTTOM))
