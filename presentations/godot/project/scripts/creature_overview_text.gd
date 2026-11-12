extends Control
# Overview168cb0/168ebd uses the same native word/color layout as Health,
# with six reserved columns inside the body and whole-paragraph fitting169160.
const Native=preload("res://scripts/native_creature_text.gd")
const Layout=preload("res://scripts/creature_health_layout.gd")
var viewport_control: Control
var font: Font
var quote:=""
var paragraphs: Array=[]
var lines: Array=[]
var columns:=0
var visible_paragraphs:=0
func configure(viewport: Control,source_font: Font,opening: String,source: Array) -> void:
 viewport_control=viewport;font=source_font;quote=opening;paragraphs=source
 mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 set_notify_transform(true)
 resized.connect(layout);viewport_control.resized.connect(layout)
 layout.call_deferred()
func _notification(what: int) -> void:
 if what==NOTIFICATION_TRANSFORM_CHANGED and is_instance_valid(viewport_control):layout.call_deferred()
func layout() -> void:
 if not is_instance_valid(viewport_control):return
 var origin: Vector2=viewport_control.get_global_transform().affine_inverse()*global_position
 var height:=maxf(0,viewport_control.size.y-origin.y)
 custom_minimum_size.y=height
 columns=maxi(1,int(size.x/8)-6)
 lines=[];visible_paragraphs=0
 var first:=6.0
 # Plain quote wrapping retains spaces within lines, unlike color-text words.
 # Native8e7310/8e7440 breaks at the preceding space and skips leading spaces.
 var remaining:=quote
 while not remaining.is_empty():
  var length:=remaining.length()
  if length>columns:
   length=remaining.left(columns).rfind(" ")
   if length<=0:length=columns
  if first+12>height:break
  var text:=remaining.left(length)
  lines.append({"text":text,"colors":[],"y":first,"quote":true})
  first+=12;remaining=remaining.substr(length)
  while remaining.begins_with(" "):remaining=remaining.substr(1)
 first+=12
 var formatter:=Layout.new()
 for paragraph in paragraphs:
  var wrapped:=formatter.build(str(paragraph),columns)
  if first+wrapped.size()*12>height:break
  for line in wrapped:
   lines.append({"text":line.text,"colors":line.colors,"y":first,"quote":false});first+=12
  visible_paragraphs+=1
 queue_redraw()
func _draw() -> void:
 if font==null:return
 for line in lines:
  for column in str(line.text).length():
   var packed:=71 if line.quote else int(line.colors[column])
   var color: Color=Native.colors[(packed&7)+(8 if packed&64 else 0)]
   var point:=Vector2(column*8,float(line.y)+12)
   var background:=(packed>>3)&7
   if background!=0:draw_rect(Rect2(point-Vector2(0,12),Vector2(8,12)),Native.colors[background])
   font.draw_string(get_canvas_item(),point,str(line.text)[column],HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
