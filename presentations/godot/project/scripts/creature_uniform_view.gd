extends "res://scripts/creature_items_view.gd"
signal focus_requested(tile:Vector3i)
func present(records:Array) -> void:
 super.present(records)
 for i in rows.size():
  var decoder:=JSON.new()
  if decoder.parse(str(fact(rows[i],"appearance","{}")))!=OK:continue
  var appearance=decoder.data
  if appearance is Dictionary and not appearance.is_empty():
   # JSON's numeric values are floats; the icon API validates exact integer fields.
   appearance.stack=int(appearance.get("stack",1));appearance.flags=int(appearance.get("flags",0))
   if appearance.has("instrument"):
    appearance.instrument.family=int(appearance.instrument.family);appearance.instrument.placed=int(appearance.instrument.placed)
   icons[i]=world.item_sheet_icon(int(fact(rows[i],"item_type",-1)),appearance,int(rows[i].id))
func _draw() -> void:
 if world==null or theme.default_font==null:return
 if rows.size()==1 and int(fact(rows[0],"no_squad",0))==1:
  theme.default_font.draw_string(get_canvas_item(),Vector2(8,24),"No squad assigned",HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[15]);return
 var width:=size.x-(32 if scrollbar.visible else 16)
 for index in range(first,mini(rows.size(),first+capacity())):
  var row:Dictionary=rows[index]
  if int(fact(row,"resolved",0))==0:continue
  var top:=Vector2(8,(index-first)*36)
  patch(art.texture("BUTTON_RECTANGLE"),top,int(width/8))
  patch(picture.texture(false),top,5)
  if icons[index]!=null:draw_texture_rect(icons[index],Rect2(top+Vector2(2,2),Vector2(32,32)),false)
  var columns:=maxi(0,int(width/8)-14)
  var caption:=str(row.get("name",""));var role:=str(fact(row,"native_role",""))
  if caption.length()>=columns:caption=caption.left(maxi(0,columns-4))+"..." if columns>4 else caption.left(maxi(0,columns-1))
  if role.length()>=columns:role=role.left(maxi(0,columns-4))+"..." if columns>4 else role.left(maxi(0,columns-1))
  theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[14])
  theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,36),role,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[11])
  if int(fact(row,"carried",0))==0:
   var texture:Texture2D=art.texture("STOCKS_RECENTER")
   if texture!=null:draw_texture_rect(texture,inspect_rect(index),false)
func hover_kind(point:Vector2) -> String:
 if not allowed():return ""
 var index:=first+floori(point.y/36)
 if index<first or index>=mini(rows.size(),first+capacity()):return ""
 if int(fact(rows[index],"resolved",0))!=0 and int(fact(rows[index],"carried",0))==0 and inspect_rect(index).has_point(point):return "uniform_recenter"
 return ""
func _gui_input(event:InputEvent) -> void:
 if not allowed() or not event is InputEventMouseButton or not event.pressed:return
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event();return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 var index:=first+floori(event.position.y/36)
 if index<first or index>=mini(rows.size(),first+capacity()) or not inspect_rect(index).has_point(event.position):return
 var row:Dictionary=rows[index]
 if int(fact(row,"resolved",0))==0 or int(fact(row,"carried",0))!=0:return
 var tile:=Vector3i(int(fact(row,"x",-30000)),int(fact(row,"y",-30000)),int(fact(row,"z",-30000)))
 if tile.x!=-30000:accept_event();focus_requested.emit(tile)
