extends Control
# Maintainer-requested indeterminate activity indication (2026-10-03).
# Animation means work is pending, never a percent complete or proof of progress.
var color := Color("ffff00")
var elapsed := 0.0
func _init() -> void:
 custom_minimum_size=Vector2(24,24)
 mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta:float) -> void:
 if not is_visible_in_tree():return
 elapsed=fmod(elapsed+delta,0.8);queue_redraw()
func _draw() -> void:
 var head:=int(elapsed/0.1)%8
 for i in 8:
  var angle:=float(i)*TAU/8.0-PI/2.0
  var shade:=color;shade.a=0.2+0.8*float((i-head+8)%8)/7.0
  draw_rect(Rect2(size/2.0+Vector2(cos(angle),sin(angle))*8.0-Vector2(2,2),Vector2(4,4)),shade)
