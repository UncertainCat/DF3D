extends Control
var frame_diagnostics # Optional recorder, injected only for explicit boundary probes.
# Revealed terrain at the selected elevation, never a debug-reveal overview.
var world
var camera_rig
var interaction
var allowed := false
var data: Dictionary = {}
var dragging := false
var elapsed := 0.25
var footprint := PackedVector2Array()

func _ready():
 mouse_filter = Control.MOUSE_FILTER_STOP
 clip_contents = true
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 tooltip_text = "Revealed terrain at selected elevation · click or drag to pan"

static func fitted_rect(bounds: Vector2, map_size: Vector2) -> Rect2:
 if map_size.x <= 0 or map_size.y <= 0: return Rect2()
 var scale := minf(bounds.x / map_size.x, bounds.y / map_size.y)
 var extent := map_size * scale
 return Rect2((bounds - extent) * 0.5, extent)

static func point_to_tile(point: Vector2, bounds: Vector2, map_size: Vector2) -> Vector2:
 var rect := fitted_rect(bounds, map_size)
 if rect.size.x <= 0 or rect.size.y <= 0: return Vector2(-1, -1)
 var fraction := (point - rect.position) / rect.size
 return Vector2(clampf(fraction.x * map_size.x, 0, maxf(0, map_size.x - 0.001)), clampf(fraction.y * map_size.y, 0, maxf(0, map_size.y - 0.001)))

static func clipped_segment(start: Vector2, finish: Vector2, rect: Rect2) -> PackedVector2Array:
 var delta := finish - start
 var low := 0.0
 var high := 1.0
 for pair in [Vector2(-delta.x, start.x-rect.position.x), Vector2(delta.x, rect.end.x-start.x), Vector2(-delta.y, start.y-rect.position.y), Vector2(delta.y, rect.end.y-start.y)]:
  if absf(pair.x) < 0.000001:
   if pair.y < 0: return PackedVector2Array()
  elif pair.x < 0: low = maxf(low, pair.y / pair.x)
  else: high = minf(high, pair.y / pair.x)
  if low > high: return PackedVector2Array()
 return PackedVector2Array([start + delta * low, start + delta * high])

func map_rect() -> Rect2:
 return fitted_rect(size, Vector2(data.get("map_size", Vector2i.ZERO)))

func set_allowed(value: bool):
 allowed = value
 if not value: dragging = false

func refresh():
 if world == null or not world.has_method("minimap_data"):
  data = {}
 else:
  data = world.minimap_data(world.get_top_z(), 256)
 queue_redraw()

func _process(delta: float):
 var started: int = frame_diagnostics.detail_start() if frame_diagnostics != null else 0
 _process_view(delta)
 if frame_diagnostics != null: frame_diagnostics.detail_mark("ui.minimap", started)

func _process_view(delta: float):
 if not is_visible_in_tree(): return
 elapsed += delta
 if elapsed >= 0.25:
  elapsed = 0
  refresh()
 update_footprint()
 queue_redraw()

func update_footprint():
 footprint.clear()
 if not data.get("available", false) or camera_rig == null: return
 var camera: Camera3D = camera_rig.get_node("Camera3D")
 var viewport_size := get_viewport().get_visible_rect().size
 var plane := Plane(Vector3.UP, float(data.z) + 1.0)
 var rect := map_rect()
 var dimensions := Vector2(data.map_size)
 for corner in [Vector2.ZERO, Vector2(viewport_size.x, 0), viewport_size, Vector2(0, viewport_size.y)]:
  var hit = plane.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
  # Looking above the horizon can make the footprint unbounded in free mode.
  if hit == null:
   footprint.clear()
   return
  footprint.append(rect.position + Vector2(hit.x, hit.z) / dimensions * rect.size)
 if footprint.size() == 4: footprint.append(footprint[0])

func _draw():
 var rect := map_rect()
 draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.035, 0.035))
 if not data.get("available", false): return
 draw_texture_rect(data.texture, rect, false)
 if footprint.size() == 5:
  for index in 4:
   var segment := clipped_segment(footprint[index], footprint[index+1], rect)
   if segment.size() == 2: draw_line(segment[0], segment[1], Color.WHITE, 1.0)
 var position3: Vector3 = camera_rig.position
 var center := rect.position + Vector2(position3.x, position3.z) / Vector2(data.map_size) * rect.size
 if rect.has_point(center):
  draw_line(center - Vector2(3,0), center + Vector2(3,0), Color.WHITE)
  draw_line(center - Vector2(0,3), center + Vector2(0,3), Color.WHITE)

func navigate(point: Vector2):
 if not allowed or not data.get("available", false): return
 var tile := point_to_tile(point, size, Vector2(data.map_size))
 interaction.cancel_selection()
 var destination: Vector3 = camera_rig.position
 destination.x = tile.x
 destination.z = tile.y
 camera_rig.focus_on(destination, camera_rig.current_distance())
 update_footprint()
 queue_redraw()

func _gui_input(event: InputEvent):
 # Consume even blocked/wheel events: never turn a minimap click into a dig
 # designation or camera zoom underneath the widget.
 if event is InputEventMouseButton:
  accept_event()
  if event.button_index == MOUSE_BUTTON_LEFT:
   if event.pressed:
    dragging = allowed and data.get("available", false) and map_rect().has_point(event.position)
    if dragging: navigate(event.position)
   else: dragging = false
 elif event is InputEventMouseMotion:
  accept_event()
  if dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT: navigate(event.position)
