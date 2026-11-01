extends Control
# Native ordered Skills rows; scroll and drawing state belong to the viewer.
signal inspect_requested(kind: int,id: int)
const NativeText=preload("res://scripts/native_creature_text.gd")
var art=preload("res://scripts/original_ui.gd").new()
var scrollbar=preload("res://scripts/reports_scrollbar.gd").new()
var rows: Array=[]
var kind:=0
var first:=0
var input_allowed: Callable
var text: Dictionary={}
func configure(world) -> void:
 art.configure(world);theme=art.theme;text=NativeText.load_text(world)
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
 scrollbar.configure(world);scrollbar.use_standalone_sheet=false;add_child(scrollbar)
 scrollbar.input_allowed=allowed
 scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
 resized.connect(layout)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func present(page: Dictionary) -> void:
 kind=int(page.get("kind",0));rows=page.get("rows",[]);layout()
func capacity() -> int:return maxi(0,int((size.y-12)/36))
func display_first() -> int:return clampi(first,0,maxi(0,rows.size()-capacity()))
func layout() -> void:
 first=maxi(0,first)
 scrollbar.position=Vector2(size.x-24,0);scrollbar.size=Vector2(16,capacity()*36)
 scrollbar.count=rows.size();scrollbar.page=capacity();scrollbar.first=display_first()
 scrollbar.visible=capacity()>0 and rows.size()>capacity();scrollbar.queue_redraw();queue_redraw()
func inspect_rect(index: int) -> Rect2:return Rect2(size.x-(56 if scrollbar.visible else 40),(index-display_first())*36,24,36)
func patch(origin: Vector2,columns: int) -> void:
 var texture: Texture2D=art.texture("BUTTON_RECTANGLE")
 if texture==null:return
 for y in 3:
  # Native16e21c begins the background one cell after the caption origin.
  for x in range(1,columns):
   draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func clipped(value: String,columns: int) -> String:
 if value.length()<columns-2:return value
 var count:=maxi(0,columns-3)
 return value.left(count-3)+"..." if count>3 else value.left(count)
func draw_text(value: String,point: Vector2,packed: int) -> void:
 var bg:=(packed>>3)&7
 if bg!=0:draw_rect(Rect2(point-Vector2(0,12),Vector2(value.length()*8,12)),NativeText.colors[bg])
 theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[(packed&7)+(8 if packed&64 else 0)])
func _draw() -> void:
 if theme==null or theme.default_font==null:return
 var columns:=int((size.x-(32 if scrollbar.visible else 16))/8)
 for index in range(display_first(),mini(rows.size(),display_first()+capacity())):
  var row: Dictionary=rows[index];var top:=Vector2(8,(index-display_first())*36)
  patch(top,columns)
  var caption:=clipped(str(row.caption),columns)
  draw_text(caption,top+Vector2(0,24),71 if kind==4 else int(row.caption_color))
  if kind==4:
   var category:=int(row.knowledge_type)
   draw_text(clipped(str(row.subtitle),columns),top+Vector2(0,36),69 if category<14 else 67 if category<17 else 70)
   if category>=14:
    var icon: Texture2D=art.texture("STOCKS_VIEW_ITEM")
    if icon!=null:draw_texture_rect(icon,inspect_rect(index),false)
  elif int(row.rating)>0 and int(row.rust_value)<int(row.rating) and caption.length()<columns-8 and text.has("skill_rust_labels"):
   var very:=int(row.rating)>=4 and int(row.rust_value)<=int(int(row.rating)/4)
   if very or int(row.rust_value)<=int(int(row.rating)/2):
    var suffix: String=text.skill_rust_labels.very_rusty.text if very else text.skill_rust_labels.rusty.text
    draw_text(suffix,top+Vector2(caption.length()*8,24),68 if very else 70)
func _gui_input(event: InputEvent) -> void:
 if not allowed() or not event is InputEventMouseButton or not event.pressed:return
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if rows.size()<=capacity() or event.position.y<0 or event.position.y>=capacity()*36:return
  scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event();return
 if kind!=4 or event.button_index!=MOUSE_BUTTON_LEFT:return
 var index:=display_first()+floori(event.position.y/36)
 if index<display_first() or index>=mini(rows.size(),display_first()+capacity()):return
 var row: Dictionary=rows[index]
 if int(row.knowledge_type)>=14 and inspect_rect(index).has_point(event.position):
  accept_event();inspect_requested.emit(int(row.knowledge_type),int(row.id))
