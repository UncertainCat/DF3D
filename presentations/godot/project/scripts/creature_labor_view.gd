extends "res://scripts/creature_skills_view.gd"
const Icons=preload("res://scripts/location_staff_indicators.gd").WORK_DETAILS
var state
signal focus_requested(tile: Vector3i)
var workshops:=false
var locations:=false
var animals:=false
var world_source
signal animal_assignment_requested(row:Dictionary)
signal animal_inspect_requested(row:Dictionary)
signal location_requested(row: Dictionary)
signal location_remove_requested(row: Dictionary)
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
func configure(world) -> void:
 super.configure(world);picture.configure(world);world_source=world
func present_labor(model) -> void:
 animals=false;locations=false;workshops=false;state=model;rows=model.rows if model.citizen.get("eligible",false) else [];layout()
func present_workshops(model,values: Array) -> void:
 animals=false;locations=false;workshops=true;state=model;rows=values;layout()
func present_locations(model,values: Array) -> void:
 animals=false;locations=true;workshops=false;state=model;rows=values;layout()
func present_animals(model,values:Array) -> void:
 animals=true;locations=false;workshops=false;state=model;rows=values;layout()
func row_offset() -> int:return 0 if (workshops or locations or animals) and state!=null and not state.citizen.get("eligible",false) else 36
func capacity() -> int:return maxi(0,int((size.y-row_offset()-12)/36))
func layout() -> void:
 super.layout();scrollbar.position.y=row_offset()
func check_rect(index: int) -> Rect2:return Rect2(size.x-(64 if scrollbar.visible else 48),36+(index-display_first())*36,32,36)
func scope_rect() -> Rect2:return Rect2(8,0,32,36)
func _draw() -> void:
 if state==null or theme==null or theme.default_font==null:return
 if state.citizen.is_empty():return
 if animals:
  draw_animals();return
 if locations:
  draw_locations();return
 if workshops:
  draw_workshops();return
 if not state.citizen.get("eligible",false):
  if state.citizen.get("reason","")=="Citizen is not eligible for ordinary labor":draw_text("Cannot assign work details",Vector2(8,24),71)
  return
 var assigned: bool=state.citizen.only_assigned_jobs
 var scope: Texture2D=art.texture("WORKER_ONLY_DO_ASSIGNED_JOBS" if assigned else "WORKER_DO_ANY_AVAILABLE_JOB")
 if scope!=null:draw_texture_rect(scope,scope_rect(),false)
 # Native Labor captions captured in unit_labor_reference (scope toggle).
 draw_text("Will only do assigned tasks" if assigned else "Will do available tasks anywhere",Vector2(64,24),71)
 var columns:=int((size.x-(32 if scrollbar.visible else 16))/8)
 for index in range(display_first(),mini(rows.size(),display_first()+capacity())):
  var row: Dictionary=rows[index];var top:=Vector2(16,36+(index-display_first())*36)
  patch(top,columns-1)
  var box: Texture2D=picture.texture(false)
  if box!=null:
   for y in 3:
    for x in 5:
     draw_texture_rect_region(box,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==4 else 8,y*12,8,12))
  if int(row.icon)>=0 and int(row.icon)<Icons.size():
   var icon: Texture2D=art.texture("WORK_DETAIL_"+Icons[int(row.icon)])
   if icon!=null:draw_texture_rect(icon,Rect2(top,Vector2(32,36)),false)
  draw_text(clipped(row.name,columns-10),top+Vector2(48,24),71)
  var member: bool=row.assigned_units.has(state.unit_id)
  var checkbox: Texture2D=art.texture("LABOR_WORKER_ASSIGNED" if member else "LABOR_WORKER_UNASSIGNED")
  if checkbox!=null:draw_texture_rect(checkbox,check_rect(index),false)
func _gui_input(event: InputEvent) -> void:
 if not allowed() or state==null or not event is InputEventMouseButton or not event.pressed:return
 if animals:
  animal_input(event);return
 if locations:
  location_input(event);return
 if workshops:
  workshop_input(event);return
 if not state.citizen.get("eligible",false):return
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if rows.size()<=capacity() or event.position.y<36 or event.position.y>=36+capacity()*36:return
  scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event();return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 if scope_rect().has_point(event.position):
  accept_event();state.set_scope(not state.citizen.get("only_assigned_jobs",false));return
 var index:=display_first()+floori((event.position.y-36)/36)
 if index<display_first() or index>=mini(rows.size(),display_first()+capacity()):return
 if check_rect(index).has_point(event.position):
  accept_event();state.set_member(int(rows[index].index),not rows[index].assigned_units.has(state.unit_id))

func workshop_button(index: int,button: int) -> Rect2:
 var right:=size.x-(32 if scrollbar.visible else 16)
 return Rect2(right-[88,64,32][button],row_offset()+(index-display_first())*36,32 if button==2 else 24,36)
func draw_workshops() -> void:
 draw_scope()
 draw_workshop_rows()
func draw_scope() -> void:
 if state.citizen.get("eligible",false):
  var assigned: bool=state.citizen.only_assigned_jobs
  var scope: Texture2D=art.texture("WORKER_ONLY_DO_ASSIGNED_JOBS" if assigned else "WORKER_DO_ANY_AVAILABLE_JOB")
  if scope!=null:draw_texture_rect(scope,scope_rect(),false)
  draw_text("Will only do assigned tasks" if assigned else "Will do available tasks anywhere",Vector2(64,24),71)
func draw_workshop_rows() -> void:
 if rows.is_empty():
  draw_text("No dedicated workshop assignments",Vector2(8,row_offset()+24),71);return
 var columns:=int((size.x-(32 if scrollbar.visible else 16))/8)
 for index in range(display_first(),mini(rows.size(),display_first()+capacity())):
  var row: Dictionary=rows[index];var top:=Vector2(16,row_offset()+(index-display_first())*36)
  patch(top,columns-1)
  var box: Texture2D=picture.texture(false)
  if box!=null:
   for y in 3:
    for x in 5:
     draw_texture_rect_region(box,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==4 else 8,y*12,8,12))
  var mapping: Dictionary=preload("res://scripts/location_staff_indicators.gd").WORKSHOPS if row.type==13 else preload("res://scripts/location_staff_indicators.gd").FURNACES
  var token: String=mapping.get(str(row.subtype),"")
  var icon: Texture2D=art.texture("CUSTOM_WORKSHOP_LIST_ICON:"+row.custom_code) if not row.custom_code.is_empty() else null
  if icon==null:icon=art.texture(token)
  if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
  draw_text(clipped(row.caption,columns-21),top+Vector2(56,24),71)
  for button in 3:
   var texture: Texture2D=art.texture(["STOCKS_RECENTER","STOCKS_VIEW_ITEM","BUILDING_SHEET_CLEAR_WORKER"][button])
   if texture!=null:draw_texture_rect(texture,workshop_button(index,button),false)
func workshop_input(event: InputEventMouseButton) -> void:
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if rows.size()>capacity() and event.position.y>=row_offset() and event.position.y<row_offset()+capacity()*36:
   scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event()
  return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 if scope_rect().has_point(event.position) and state.citizen.get("eligible",false):
  accept_event();state.set_scope(not state.citizen.only_assigned_jobs);return
 var index:=display_first()+floori((event.position.y-row_offset())/36)
 if index<display_first() or index>=mini(rows.size(),display_first()+capacity()):return
 var row: Dictionary=rows[index]
 for button in 3:
  if not workshop_button(index,button).has_point(event.position):continue
  accept_event()
  if button==0:focus_requested.emit(row.tile)
  elif button==1:inspect_requested.emit(3,row.id)
  else:state.remove_workshop(row.id,row.revision)
  return

func draw_locations() -> void:
 draw_scope()
 if rows.is_empty():
  draw_text("No location assignments",Vector2(8,row_offset()+24),71);return
 var columns:=int((size.x-(32 if scrollbar.visible else 16))/8)
 for index in range(display_first(),mini(rows.size(),display_first()+capacity())):
  var row:Dictionary=rows[index];var top:=Vector2(8,row_offset()+(index-display_first())*36)
  patch(top,columns)
  var box:Texture2D=picture.texture(false)
  if box!=null:
   for y in 3:
    for x in 5:
     draw_texture_rect_region(box,Rect2(top+Vector2(8+x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==4 else 8,y*12,8,12))
  var token:String={8:"ZONE_TAVERN",9:"ZONE_LIBRARY",13:"ZONE_HOSPITAL"}.get(row.type,"")
  if row.type==2:token="ZONE_TEMPLE" if row.tier==1 else "ZONE_TEMPLE_COMPLEX" if row.tier==2 else "ZONE_SHRINE"
  if row.type==11:token="ZONE_GUILDHALL" if row.tier==1 else "ZONE_GRAND_GUILDHALL" if row.tier==2 else "ZONE_MEETING"
  var icon:Texture2D=art.texture(token) if not token.is_empty() else null
  if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
  draw_text(clipped(row.role,columns-17),top+Vector2(56,24),71)
  draw_text(clipped(row.name,columns-17),top+Vector2(56,36),71)
  for button in [1,2]:
   if (button==1 and row.type<0) or (button==2 and not row.removable):continue
   var texture:Texture2D=art.texture("STOCKS_RECENTER" if button==1 else "BUILDING_SHEET_CLEAR_WORKER")
   if texture!=null:draw_texture_rect(texture,workshop_button(index,button),false)
func location_input(event:InputEventMouseButton) -> void:
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if rows.size()>capacity() and event.position.y>=row_offset() and event.position.y<row_offset()+capacity()*36:
   scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event()
  return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 if scope_rect().has_point(event.position) and state.citizen.get("eligible",false):
  accept_event();state.set_scope(not state.citizen.only_assigned_jobs);return
 var index:=display_first()+floori((event.position.y-row_offset())/36)
 if index<display_first() or index>=mini(rows.size(),display_first()+capacity()):return
 var row:Dictionary=rows[index]
 if row.type>=0 and workshop_button(index,1).has_point(event.position):accept_event();location_requested.emit(row.duplicate(true))
 elif row.removable and workshop_button(index,2).has_point(event.position):accept_event();location_remove_requested.emit(row.duplicate(true))

func draw_animals() -> void:
 draw_scope()
 if not state.citizen.get("eligible",false):
  draw_text("Cannot assign work animals",Vector2(8,24),71);return
 if rows.is_empty():
  draw_text("No assigned or assignable work animals",Vector2(8,row_offset()+24),71);return
 var columns:=int((size.x-(32 if scrollbar.visible else 16))/8)
 for index in range(display_first(),mini(rows.size(),display_first()+capacity())):
  var row:Dictionary=rows[index];var top:=Vector2(16,row_offset()+(index-display_first())*36)
  patch(top,columns-1)
  var box:Texture2D=picture.texture(false)
  if box!=null:
   for y in 3:
    for x in 5:
     draw_texture_rect_region(box,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==4 else 8,y*12,8,12))
  var icon:Texture2D=world_source.selection_icon(1,row.id,true)
  if icon!=null:draw_texture_rect(icon,Rect2(top+Vector2(2,2),Vector2(32,32)),false)
  var caption:String=row.caption
  var limit:=columns-16
  if caption.length()>=limit:caption=caption.left(maxi(0,limit-4))+"..." if limit>4 else caption.left(maxi(0,limit-1))
  # Native button cells replace caption cells even where their artwork is transparent.
  var caption_point:=top+Vector2(56,24)
  theme.default_font.draw_string(get_canvas_item(),caption_point,caption,HORIZONTAL_ALIGNMENT_LEFT,workshop_button(index,0).position.x-caption_point.x,12,NativeText.colors[15])
  for button in 3:
   var token:String=["STOCKS_RECENTER","STOCKS_VIEW_ITEM","BUILDING_SHEET_CLEAR_WORKER" if row.assigned else "ZONE_PICK_ANIMALS"][button]
   var texture:Texture2D=art.texture(token)
   if texture!=null:draw_texture_rect(texture,workshop_button(index,button),false)
func animal_input(event:InputEventMouseButton) -> void:
 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if rows.size()>capacity() and event.position.y>=row_offset() and event.position.y<row_offset()+capacity()*36:
   scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event()
  return
 if event.button_index!=MOUSE_BUTTON_LEFT:return
 if scope_rect().has_point(event.position) and state.citizen.get("eligible",false):
  accept_event();state.set_scope(not state.citizen.only_assigned_jobs);return
 var index:=display_first()+floori((event.position.y-row_offset())/36)
 if index<display_first() or index>=mini(rows.size(),display_first()+capacity()):return
 var row:Dictionary=rows[index]
 if workshop_button(index,0).has_point(event.position) and row.tile.x!=-30000:accept_event();focus_requested.emit(row.tile)
 elif workshop_button(index,1).has_point(event.position) and row.tile.x!=-30000:accept_event();animal_inspect_requested.emit(row.duplicate(true))
 elif workshop_button(index,2).has_point(event.position):accept_event();animal_assignment_requested.emit(row.duplicate(true))
