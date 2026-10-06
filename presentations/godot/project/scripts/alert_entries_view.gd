extends Control
# Initial native popup geometry: alert_entries.json.long_text_capture (1200x800).
# Staged renderer: main-scene lifecycle, narrow HUD overlap and remaining
# acceptance gaps are tracked in fixtures/reports/alert_entries.json.
signal history_requested
signal recenter_requested(tile:Vector3i)
signal unit_requested(unit_id:int,category:int)
const Reports=preload("res://scripts/reports_view.gd")
const HEADER="You can recenter on certain announcements.  Right click to close."
const UNIT_HEADER="Select a report to view the full text.  Right click to close."
const PAGE_LINES=29
var art=preload("res://scripts/original_ui.gd").new()
var state
var input_allowed:Callable
var minimap_input:Callable
var border:Texture2D
var scrollbar
var lines=preload("res://scripts/alert_text_layout.gd").new()
var targets:Array=[]
var first_line:=0
var _loaded_generation:=-1
var has_units:=false
var _rendered_unit:=-1
var _group_first:=0
var _loading_unit:=-1

func configure(source,model,_install_root:String) -> void:
 art.configure(source);theme=art.theme;state=model
 border=art.texture("HOVER_RECTANGLE")
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
 size=Vector2(752,420)
 get_viewport().size_changed.connect(_viewport_resized)
 _viewport_resized()
 scrollbar=preload("res://scripts/reports_scrollbar.gd").new();add_child(scrollbar)
 scrollbar.use_standalone_sheet=false
 scrollbar.configure(source);scrollbar.position=Vector2(720,48);scrollbar.size=Vector2(16,348);scrollbar.page=PAGE_LINES
 # Popup-wide wheel handling below owns native one-line/page scrolling.
 scrollbar.wheel_enabled=false
 scrollbar.input_allowed=func():return not input_allowed.is_valid() or input_allowed.call()
 scrollbar.row_changed.connect(scroll_to)
 state.changed.connect(refresh);refresh()

func _viewport_resized() -> void:
 # Native113913/114105 centers the8x12 UI grid inside remainder pixels.
 var extent:Vector2i=Vector2i(get_viewport_rect().size)
 position=Vector2(32+int((extent.x%8)/2),48+int((extent.y%12)/2))

func refresh() -> void:
 visible=state.opened and state.complete
 if not state.opened:first_line=0;_loaded_generation=-1;_rendered_unit=-1;_loading_unit=-1;_group_first=0;lines.clear()
 # Save parent position when navigation starts, including Back before receipt.
 if state.opened and state.unit_id>=0 and _rendered_unit<0 and _loading_unit<0:
  _group_first=first_line;_loading_unit=state.unit_id
 if state.complete and _loaded_generation!=state.generation:
  first_line=_group_first if (_rendered_unit>=0 or _loading_unit>=0) and state.unit_id<0 else 0
  _loading_unit=-1
  _rendered_unit=state.unit_id
  _loaded_generation=state.generation
  lines.build(state.rows);has_units=lines.has_units
 if scrollbar!=null:scrollbar.set_rows(lines.size(),first_line)
 queue_redraw()

func scroll_to(value:int) -> void:
 first_line=clampi(value,0,maxi(0,lines.size()-PAGE_LINES))
 if scrollbar!=null:scrollbar.set_rows(lines.size(),first_line)
 queue_redraw()

func _input(event:InputEvent) -> void:
 if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
 # Native124838/130543: map clicks pan without closing either popup view;
 # map wheel input does not scroll the popup. Right-click still performs Back.
 if event is InputEventMouseButton and event.pressed and minimap_input.is_valid() and minimap_input.call(event.position):
  if event.button_index==MOUSE_BUTTON_LEFT:return
  if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   get_viewport().set_input_as_handled();return
 # Native112636: wheel in popup scrolls one line; Shift uses29 lines.
 # A left click outside dismisses the popup and must not reach world actions.
 if event is InputEventMouseButton and event.pressed:
  var inside:bool=get_global_rect().has_point(event.position)
  if event.button_index==MOUSE_BUTTON_LEFT and not inside:
   state.close();get_viewport().set_input_as_handled();return
  if inside and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   var step:int=PAGE_LINES if event.shift_pressed else 1
   scroll_to(first_line+(-step if event.button_index==MOUSE_BUTTON_WHEEL_UP else step))
   get_viewport().set_input_as_handled();return
 if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
  state.back();get_viewport().set_input_as_handled()

func _gui_input(event:InputEvent) -> void:
 if input_allowed.is_valid() and not input_allowed.call():return
 if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
 if Rect2(704,12,24,36).has_point(event.position):history_requested.emit();accept_event();return
 for target in targets:
  if not target.rect.has_point(event.position):continue
  if target.kind=="unit":unit_requested.emit(int(target.row.unit_id),int(target.row.category))
  else:
   var key:String=target.key
   if target.row.get(key) is Vector3i:
    var tile:Vector3i=target.row[key];state.close();recenter_requested.emit(tile)
  accept_event();return

func _draw() -> void:
 if state==null or not state.complete:return
 if border!=null:
  for y in 35:
   for x in 94:
    draw_texture_rect_region(border,Rect2(x*8,y*12,8,12),Rect2((0 if x==0 else 2 if x==93 else 1)*8,(0 if y==0 else 2 if y==34 else 1)*12,8,12))
 targets=[]
 var font:Font=theme.default_font
 if font==null:return
 font.draw_string(get_canvas_item(),Vector2(16,36),UNIT_HEADER if has_units else HEADER,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
 var history:Texture2D=art.texture("ANNOUNCEMENT_OPEN_ALL_ANNOUNCEMENTS")
 if history!=null:draw_texture_rect(history,Rect2(704,12,24,36),false)
 var button_x:=688 if lines.size()>PAGE_LINES else 704
 for i in mini(PAGE_LINES,lines.size()-first_line):
  var line:Dictionary=lines.at(first_line+i);var row:Dictionary=line.row
  var index:int=Reports.UNIT_COLOR_INDICES[int(row.category)] if line.kind=="unit" else int(row.get("color",7))+(8 if row.get("bright",false) else 0)
  font.draw_string(get_canvas_item(),Vector2(16,60+i*12),line.text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,art.world.ui_palette_color(index))
  # Native084855 omits the control on a partially visible final entry, while
  # retaining its visible prose. A 36px control needs three complete lines.
  if not line.start or i+3>PAGE_LINES:continue
  if line.kind=="unit":
   var rect:=Rect2(button_x,48+i*12,24,36)
   var icon:Texture2D=art.texture("STOCKS_VIEW_ITEM")
   if icon!=null:draw_texture_rect(icon,rect,false)
   targets.append({"rect":rect,"kind":"unit","row":row})
  else:
   for secondary in [false,true]:
    var key:="position2" if secondary else "position"
    if not row.get(key+"_visible",false):continue
    var rect:=Rect2(button_x if secondary or not row.get("position2_visible",false) else button_x-24,48+i*12,24,36)
    var icon:Texture2D=art.texture("STOCKS_RECENTER")
    if icon!=null:draw_texture_rect(icon,rect,false)
    targets.append({"rect":rect,"kind":"report","row":row,"key":key})
