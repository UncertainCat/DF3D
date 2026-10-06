extends PanelContainer
# Native right frame: clipped top/right borders, 25x18 installed UI cells.
# Contents are composed separately so only the map can overdraw alert popups.
var art
func configure(source) -> void:
 art=source
 var empty:=StyleBoxEmpty.new()
 empty.content_margin_left=8;empty.content_margin_bottom=12
 add_theme_stylebox_override("panel",empty)
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
func _draw() -> void:
 if art==null:return
 var frame:Texture2D=art.texture("HOVER_RECTANGLE")
 if frame==null:return
 for y in 18:
  for x in 25:
   draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 8,24 if y==17 else 12,8,12))
