extends Control
# Native semantic paragraphs, rendered with independently owned layout state.
const NativeText=preload("res://scripts/native_creature_text.gd")
var art=preload("res://scripts/original_ui.gd").new()
var formatter=preload("res://scripts/creature_health_layout.gd").new()
var scrollbar=preload("res://scripts/reports_scrollbar.gd").new()
var rows: Array=[]
var lines: Array=[]
var first:=0
var page_key:=""
var input_allowed: Callable
func configure(world) -> void:
 art.configure(world);theme=art.theme;NativeText.load_text(world)
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;clip_contents=true
 mouse_filter=Control.MOUSE_FILTER_STOP
 scrollbar.use_standalone_sheet=false;scrollbar.configure(world);add_child(scrollbar)
 scrollbar.input_allowed=allowed
 scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
 resized.connect(layout)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func present(source: Array,key: String,saved_first: int) -> void:
 if key!=page_key:
  first=saved_first;scrollbar.dragging=false;scrollbar.hover_cell=-1
 page_key=key;rows=source;layout()
func capacity() -> int:return maxi(0,int((size.y-24)/12))
func layout() -> void:
 lines=[]
 for row in rows:lines.append_array(formatter.build(str(row),maxi(1,int(size.x/8)-6)))
 first=maxi(0,first)
 scrollbar.position=Vector2(size.x-24,12);scrollbar.size=Vector2(16,capacity()*12)
 scrollbar.count=lines.size();scrollbar.page=capacity();scrollbar.first=first
 scrollbar.visible=capacity()>0 and lines.size()>capacity()
 scrollbar.queue_redraw();queue_redraw()
func _draw() -> void:
 if theme==null or theme.default_font==null:return
 for index in range(first,mini(lines.size(),first+capacity())):
  var line: Dictionary=lines[index]
  for column in str(line.text).length():
   var packed:=int(line.colors[column])
   var color: Color=NativeText.colors[(packed&7)+(8 if packed&64 else 0)]
   var point:=Vector2(8+column*8,24+(index-first)*12)
   var background:=(packed>>3)&7
   if background!=0:draw_rect(Rect2(point-Vector2(0,12),Vector2(8,12)),NativeText.colors[background])
   theme.default_font.draw_string(get_canvas_item(),point,str(line.text)[column],HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
func _gui_input(event: InputEvent) -> void:
 if not allowed() or not event is InputEventMouseButton or not event.pressed:return
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1))
  accept_event()
