extends Control
# Native red-alert-native120347: separate ALERT vector; opening does not clear it.
signal group_requested(group:Dictionary)
signal dismissal_requested(group:Dictionary)
var world
var enabled:=false
var _group:Dictionary={}
var art=preload("res://scripts/original_ui.gd").new()
var border:Texture2D
func _ready() -> void:
 custom_minimum_size=Vector2(56,36);size=custom_minimum_size
 mouse_filter=Control.MOUSE_FILTER_STOP
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 art.configure(world);theme=art.theme;border=art.texture("SIEGE_LIGHT")
 hide()
func update_state(state:Dictionary,allowed:bool) -> void:
 enabled=allowed
 visible=bool(state.get("fortress_valid",false)) and int(state.get("alert_button_report_count",0))>0
 _group={"alert_button":true,"fortress_epoch":int(state.get("fortress_epoch",0))} if visible else {}
 queue_redraw()
func _gui_input(event:InputEvent) -> void:
 if not enabled or not visible or _group.is_empty():return
 if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
  group_requested.emit(_group.duplicate(true));accept_event()
 if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
  dismissal_requested.emit(_group.duplicate(true));accept_event()
func _draw() -> void:
 if border==null or theme.default_font==null or world==null:return
 for y in 3:
  for x in 7:
   draw_texture_rect_region(border,Rect2(x*8,y*12,8,12),Rect2((0 if x==0 else 2 if x==6 else 1)*8,y*12,8,12))
 # Verbatim native label, palette6+bright captured from screen cells.
 theme.default_font.draw_string(get_canvas_item(),Vector2(8,24),"ALERT",HORIZONTAL_ALIGNMENT_LEFT,-1,12,world.ui_palette_color(14))
