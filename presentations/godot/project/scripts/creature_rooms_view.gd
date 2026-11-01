extends "res://scripts/creature_skills_view.gd"
signal focus_requested(tile:Vector3i)
func _draw() -> void:
 if theme==null or theme.default_font==null:return
 var columns:=int((size.x-(32 if scrollbar.visible else 16))/8)
 for index in range(display_first(),mini(rows.size(),display_first()+capacity())):
  var row:Dictionary=rows[index];var top:=Vector2(8,(index-display_first())*36)
  patch(top,columns)
  var prefix:String=["NOBLES_OFFICE_","NOBLES_BEDROOM_","NOBLES_DINING_","NOBLES_TOMB_"][row.kind]
  var suffix:String={-1:"NA",0:"GOOD",1:"PARTIAL",2:"MISSING"}.get(row.status,"NA")
  var icon:Texture2D=art.texture(prefix+suffix)
  if icon!=null:draw_texture_rect(icon,Rect2(top,Vector2(32,36)),false)
  draw_text(row.custom_name,top+Vector2(64,12),71)
  draw_text(row.caption,top+Vector2(64,24),71)
  if not row.requirement.is_empty():draw_text(row.requirement,top+Vector2(64,36),{0:66,1:70,2:68}.get(row.status,71))
  if row.id>=0:
   var focus:Texture2D=art.texture("STOCKS_RECENTER")
   if focus!=null:draw_texture_rect(focus,inspect_rect(index),false)
func _gui_input(event:InputEvent) -> void:
 if not allowed() or not event is InputEventMouseButton or not event.pressed:return
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if rows.size()<=capacity() or event.position.y<0 or event.position.y>=capacity()*36:return
  scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event();return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 var index:=display_first()+floori(event.position.y/36)
 if index<display_first() or index>=mini(rows.size(),display_first()+capacity()):return
 var row:Dictionary=rows[index]
 if row.id>=0 and inspect_rect(index).has_point(event.position):
  accept_event();focus_requested.emit(row.tile)
