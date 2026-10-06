extends Control
# Native reference: e7 r01_all_initial / r09_tab_combat,1200x800 viewport.
var art=preload("res://scripts/original_ui.gd").new()
var state
var input_allowed: Callable
var native_art: Dictionary={}
var tab_targets: Array=[]
var unit_targets: Array=[]
var report_targets:Array=[]
var speaker_targets:Array=[]
var scroll_row:=0
var selection_key:=""
var scrollbar
const PAUSE_TARGET=Rect2(896,12,24,36)
# Native074522: LRED, LCYAN, LGREEN, resolved through the installation palette.
const UNIT_COLOR_INDICES=[12,11,10]
func configure(source,model,install_root: String) -> void:
 art.configure(source);theme=art.theme;state=model
 # Reports uses the standalone native sheets, not vanilla INTERFACE_BITS.
 # Source: data/art/{border,tabs}.png; native e7 r01/r09 pixel comparisons.
 for name in ["border","tabs"]:
  var bitmap:=Image.load_from_file(install_root.path_join("data/art/"+name+".png"))
  if bitmap==null:return
  native_art[name]=ImageTexture.create_from_image(bitmap)
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
 position=Vector2(32,52);size=Vector2(944,708)
 scrollbar=preload("res://scripts/reports_scrollbar.gd").new();add_child(scrollbar)
 scrollbar.configure(source);scrollbar.position=Vector2(928,96);scrollbar.size=Vector2(16,564);scrollbar.page=15
 scrollbar.input_allowed=func():return not input_allowed.is_valid() or input_allowed.call()
 scrollbar.row_changed.connect(func(first):state.scroll_to(first))
 state.changed.connect(refresh);refresh()
func refresh() -> void:
 var key:="%s:%s:%s" % [state.opened,state.selected_tab,state.unit_id]
 if key!=selection_key:selection_key=key
 scroll_row=state.log_first if state.unit_id>=0 else state.first_row
 position.y=64 if state.unit_id>=0 else 52
 size.y=696 if state.unit_id>=0 else 708
 visible=state.opened
 if scrollbar!=null:
  var log_view:bool=state.unit_id>=0
  scrollbar.position=Vector2(928,48 if log_view else 96)
  scrollbar.size=Vector2(16,636 if log_view else 564)
  scrollbar.page=17 if log_view else 15
  # Native ordinary report tabs and unit logs ignore wheel even over the bar;
  # only Combat/Sparring/Hunting unit lists handle contextual wheel input.
  scrollbar.wheel_enabled=not log_view and state.selected_tab>=23
  scrollbar.set_rows(state.list_count(),state.log_requested if log_view else state.requested_row)
 queue_redraw()
func _input(event: InputEvent) -> void:
 if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
 if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
  get_viewport().set_input_as_handled();state.close()
func _gui_input(event: InputEvent) -> void:
 if input_allowed.is_valid() and not input_allowed.call():return
 if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if state.unit_id<0 and state.selected_tab>=23:
   # Native protected060838: one row, Shift+wheel one15-row page.
   var step:=15 if event.shift_pressed else 1
   state.scroll_to(state.requested_row+(-step if event.button_index==MOUSE_BUTTON_WHEEL_UP else step))
   queue_redraw();accept_event();return
 if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
  if state.unit_id>=0 and PAUSE_TARGET.has_point(event.position):
   state.toggle_pause_on_new();accept_event();return
  for target in tab_targets:
   if target.rect.has_point(event.position):state.choose_tab(target.tab);accept_event();return
  for target in unit_targets:
   if target.rect.has_point(event.position):state.open_unit(target.id,target.category);accept_event();return
  for target in report_targets:
   if target.rect.has_point(event.position):state.recenter(target.id,target.secondary);accept_event();return
  for target in speaker_targets:
   if target.rect.has_point(event.position):state.inspect_speaker(target.id);accept_event();return
func _get_tooltip(at_position:Vector2) -> String:
 if state.unit_id>=0 and PAUSE_TARGET.has_point(at_position):return "Toggle auto-pause on new report."
 for target in report_targets:
  if target.rect.has_point(at_position):return "Leave this menu and recenter on this creature."
 return ""
func patch(token: String,origin: Vector2,columns: int,rows: int,edge_columns: int=1) -> void:
 var texture: Texture2D=native_art.get("border" if token=="border" else "tabs")
 if texture==null:return
 for y in rows:
  for x in columns:
   var tx:int=x if x<edge_columns else x-columns+edge_columns*2+1 if x>=columns-edge_columns else edge_columns
   var ty:int=y if y==0 else 2 if y==rows-1 else 1
   if rows==2:ty=y
   draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(tx*8+(40 if token=="selected" else 0),ty*12,8,12))
func _draw() -> void:
 if state==null:return
 patch("border",Vector2.ZERO,118,58 if state.unit_id>=0 else 59)
 tab_targets=[];unit_targets=[];report_targets=[];speaker_targets=[]
 if state.unit_id>=0:
  draw_unit_log();return
 var font: Font=theme.default_font
 if font==null:return
 for row_index in state.tab_rows.size():
  var x:=8
  for tab in state.tab_rows[row_index]:
   var label: String=state.LABELS[tab-1]
   var columns:int=label.length()+4
   var origin:=Vector2(x,12+row_index*24)
   var selected: bool=tab==state.selected_tab
   patch("selected" if selected else "tabs",origin,columns,2,2)
   var enabled:bool=state.counts.size()==25 and int(state.counts[tab-1])>0
   var color:=Color8(70,44,0) if selected else Color.WHITE if enabled else Color8(70,44,0)
   font.draw_string(get_canvas_item(),origin+Vector2(16,18),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
   tab_targets.append({"tab":tab,"rect":Rect2(origin,Vector2(columns*8,24))})
   x+=columns*8

 if state.selected_tab>=23:
  var icon: Texture2D=art.texture("STOCKS_VIEW_ITEM")
  for index in mini(15,state.rows.size()-scroll_row):
   var row: Dictionary=state.rows[scroll_row+index]
   var category:=int(row.get("category",-1))
   if category<0 or category>2 or not str(row.get("error","")).is_empty():continue
   # Native e7/e11 unit-row template; names/professions come from semantic data.
   var label:="The %s%s %s" % [row.get("profession",""),(" "+str(row.name)) if not str(row.get("name","")).is_empty() else "",["is fighting!","is sparring.","is hunting."][category]]
   font.draw_string(get_canvas_item(),Vector2(16,108+index*36),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,art.world.ui_palette_color(UNIT_COLOR_INDICES[category]))
   var target:=Rect2(888,96+index*36,24,36)
   if icon!=null:draw_texture_rect(icon,target,false)
   unit_targets.append({"rect":target,"id":int(row.unit_id),"category":category})

 else:
  for index in mini(15,state.rows.size()-scroll_row):
   var row:Dictionary=state.rows[scroll_row+index]
   var icon:Texture2D=art.texture("STOCKS_RECENTER")
   for secondary in [false,true]:
    if not row.get("position2_visible" if secondary else "position_visible",false):continue
    var target:=Rect2(880 if secondary or not row.get("position2_visible",false) else 856,96+index*36,24,36)
    if icon!=null:draw_texture_rect(icon,target,false)
    report_targets.append({"rect":target,"id":int(row.id),"secondary":secondary})

   var palette_index:=int(row.get("color",7))+(8 if row.get("bright",false) else 0)
   var color:Color=art.world.ui_palette_color(palette_index)
   var lines:=wrap_report(str(row.get("text","")),112,visible_text_lines(96+index*36))
   for line in lines.size():
    # Native long text overdraws the border; its background does not erase it.
    var y:=96+index*36+line*12
    var background_height:=clampi(int(size.y)-12-y,0,12)
    if background_height>0:draw_rect(Rect2(16,y,lines[line].length()*8,background_height),Color8(28,28,28))
    font.draw_string(get_canvas_item(),Vector2(16,108+index*36+line*12),lines[line],HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
   var date:=report_date(row)
   # Native's opaque date cells overwrite the beginning of wrapped line two.
   draw_rect(Rect2(16,108+index*36,date.length()*8,12),Color8(28,28,28))
   font.draw_string(get_canvas_item(),Vector2(16,120+index*36),date,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

static func report_date(row:Dictionary) -> String:
 # Native e7 r01 date line, same calendar and ordinals as the native HUD.
 var days:int=int(row.get("year_tick",0))/1200
 var day:=days%28+1
 var suffix:="th"
 if day<11 or day>13:suffix={1:"st",2:"nd",3:"rd"}.get(day%10,"th")
 return "Date: %d%s %s, %d" % [day,suffix,preload("res://scripts/session_controls.gd").MONTHS[clampi(days/28,0,11)],int(row.get("year",0))]

func visible_text_lines(local_y:float) -> int:
 # Overdraw continues outside the panel, but cannot appear below the viewport.
 return maxi(0,ceili((get_viewport_rect().size.y-global_position.y-local_y)/12.0))

static func wrap_report(text:String,columns:int,max_lines:int=-1,work:Dictionary={}) -> PackedStringArray:
 assert(columns>0)
 var lines:PackedStringArray=[]
 if columns<=0 or max_lines==0:return lines
 var measured:=work.has("scanned")
 var offset:=0
 var length:=text.length()
 while length-offset>columns:
  # Search/copy only this line's window, never the ever-shrinking full suffix.
  var split:=text.substr(offset,columns).rfind(" ")
  if split<=0:split=columns
  var copied:=split+1 if split<columns else split
  lines.append(text.substr(offset,copied))
  if measured:
   work.scanned=int(work.scanned)+columns
   work.copied=int(work.get("copied",0))+columns+copied
  if max_lines>=0 and lines.size()>=max_lines:return lines
  offset+=split
  if offset<length and text.unicode_at(offset)==32:offset+=1
 lines.append(text.substr(offset))
 if measured:work.copied=int(work.get("copied",0))+length-offset
 return lines

func draw_unit_log() -> void:
 var font:Font=theme.default_font
 if font==null:return
 var pause_icon:Texture2D=art.texture("ANNOUNCEMENT_PAUSING_ON_NEW_REPORT" if state.pause_on_new else "ANNOUNCEMENT_NOT_PAUSING_ON_NEW_REPORT")
 if pause_icon!=null:draw_texture_rect(pause_icon,PAUSE_TARGET,false)
 var header:="You can recenter on the locations of the announcements. You may also toggle pausing when there is a new announcement."
 var heading:=wrap_report(header,110)
 for i in heading.size():font.draw_string(get_canvas_item(),Vector2(8,24+i*12),heading[i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
 var icon:Texture2D=art.texture("STOCKS_RECENTER")
 for index in mini(17,state.rows.size()-scroll_row):
  var row:Dictionary=state.rows[scroll_row+index]
  # Native072011: secondary-only uses the right slot; two positions use both.
  if int(row.get("speaker_id",-1))>=0:
   var positions:=int(bool(row.get("position_visible",false)))+int(bool(row.get("position2_visible",false)))
   var speaker_rect:=Rect2(880-24*positions,48+index*36,24,36)
   var speaker_icon:Texture2D=art.texture("STOCKS_VIEW_ITEM")
   if speaker_icon!=null:draw_texture_rect(speaker_icon,speaker_rect,false)
   speaker_targets.append({"rect":speaker_rect,"id":int(row.id)})
  for secondary in [false,true]:
   if not row.get("position2_visible" if secondary else "position_visible",false):continue
   var target:=Rect2(880 if secondary or not row.get("position2_visible",false) else 856,48+index*36,24,36)
   if icon!=null:draw_texture_rect(icon,target,false)
   report_targets.append({"rect":target,"id":int(row.id),"secondary":secondary})
  var color:Color=art.world.ui_palette_color(int(row.get("color",7))+(8 if row.get("bright",false) else 0))
  var lines:=wrap_report(str(row.get("text","")),108,visible_text_lines(48+index*36))
  for line in lines.size():
   var y:=48+index*36+line*12
   var background_height:=clampi(int(size.y)-12-y,0,12)
   if background_height>0:draw_rect(Rect2(8,y,lines[line].length()*8,background_height),Color8(28,28,28))
   font.draw_string(get_canvas_item(),Vector2(8,60+index*36+line*12),lines[line],HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
