extends "res://scripts/location_staff_candidates_view.gd"
# Native unit-list SPECIALIZED option: constructor14290b0, render1431b20,
# click1431c60, tooltip1433d40. The widget callbacks are never runtime inputs.
const Indicators=preload("res://scripts/location_staff_indicators.gd")
var indicator_columns:=1
var modes
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO
func configure_modes(reader,help=null) -> void:
 modes=reader;hover_help=help;modes.changed.connect(queue_redraw)
 mouse_exited.connect(_leave_hover)
 visibility_changed.connect(func():
  if not is_visible_in_tree():_leave_hover())
func _leave_hover() -> void:
 pointer_known=false
 if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
func _exit_tree() -> void:_leave_hover()
func _process(delta: float) -> void:
 super._process(delta)
 if not is_instance_valid(hover_help):return
 if pointer_known and is_visible_in_tree() and modes!=null and (not input_allowed.is_valid() or input_allowed.call()):
  for index in range(first,mini(first+page_rows,rows.size())):
   if mode_rect(index).has_point(pointer_position):
    var receipt: Dictionary=modes.receipts.get(int(rows[index].unit_id),{})
    if not receipt.is_empty():
     hover_help.enter_specialization(get_instance_id(),receipt.only_assigned_jobs);return
   var slots:=indicator_slots(rows[index])
   for slot in slots.size():
    if indicator_rect(index,slot).has_point(pointer_position) and not slots[slot].help.is_empty():
     hover_help.enter_staff_indicator(get_instance_id(),slots[slot].help);return
 hover_help.leave(get_instance_id())
func update_icons() -> void:
 super.update_icons()
 if modes!=null and visible:modes.display(rows.slice(first,mini(first+page_rows,rows.size())))
func indicator_slots(row: Dictionary) -> Array:
 var slots: Array=[]
 for entry in row.get("assignments",[]):
  for slot in Indicators.slots([entry],20):
   if not slot.token.is_empty():slots.append(slot)
 return slots
func _rebuild_filtered_rows() -> void:
 super._rebuild_filtered_rows()
 indicator_columns=1
 for row in rows:indicator_columns=maxi(indicator_columns,indicator_slots(row).size())
func indicator_rect(index: int,slot: int) -> Rect2:return Rect2(464+slot*32,36+(index-first)*36,32,36)
func mode_rect(index: int) -> Rect2:return Rect2(472+indicator_columns*32,36+(index-first)*36,32,36)
func _gui_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion:pointer_position=event.position;pointer_known=true
 if input_allowed.is_valid() and not input_allowed.call():return
 if modes!=null and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
  for index in range(first,mini(first+page_rows,rows.size())):
   if mode_rect(index).has_point(event.position):
    modes.toggle(int(rows[index].unit_id));accept_event();return
 super._gui_input(event)
func clear_icon_region(index: int,region: Rect2) -> void:
 var background: Texture2D=art.texture("BUTTON_RECTANGLE_SELECTED" if index==selected else row_background_token)
 if background==null:return
 for y in 3:
  for x in 4:draw_texture_rect_region(background,Rect2(region.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(8,y*12,8,12))
func _draw() -> void:
 super._draw()
 if modes==null:return
 for index in range(first,mini(first+page_rows,rows.size())):
  var slots:=indicator_slots(rows[index])
  for slot in slots.size():
   var entry: Dictionary=slots[slot]
   var icon: Texture2D=art.texture(entry.token)
   if icon==null and not entry.fallback.is_empty():icon=art.texture(entry.fallback)
   if icon==null:continue
   var region:=indicator_rect(index,slot)
   clear_icon_region(index,region)
   if entry.building:region=Rect2(region.position+Vector2(0,2),Vector2(32,32))
   draw_texture_rect(icon,region,false)
  var receipt: Dictionary=modes.receipts.get(int(rows[index].unit_id),{})
  if receipt.is_empty():continue
  var token: String="WORKER_ONLY_DO_ASSIGNED_JOBS" if receipt.only_assigned_jobs else "WORKER_DO_ANY_AVAILABLE_JOB"
  var texture: Texture2D=art.texture(token)
  if texture!=null:
   clear_icon_region(index,mode_rect(index));draw_texture_rect(texture,mode_rect(index),false)
