extends Label
const NativeText = preload("res://scripts/native_creature_text.gd")
var base_color := 15
var flash := 0
func color_at(milliseconds: int) -> int:
 if flash==2: return [1,9,11,9][(milliseconds%500)/125]
 if flash==1: return base_color+(8 if milliseconds%1000>=500 else 0)
 return base_color
func apply_time(milliseconds: int):
 add_theme_color_override("font_color",NativeText.colors[color_at(milliseconds)])
func _process(_delta: float):
 apply_time(Time.get_ticks_msec())
func _notification(what: int):
 if what==NOTIFICATION_VISIBILITY_CHANGED: set_process(is_visible_in_tree())
