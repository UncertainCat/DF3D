extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.size=Vector2i(1200,800)
 var assets:=Df3dWorld.new();root.add_child(assets)
 if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
 var state=preload("res://scripts/reports_state.gd").new();state.open()
 state.counts=[];state.counts.resize(25);state.counts.fill(0)
 for tab in [1,5,8,10,11,14,16,23,24]:state.counts[tab-1]=1
 var list_fixture=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DF3D_REPORTS_LIST")))
 for row in list_fixture.rows:
  for key in ["position","position2"]:row[key]=Vector3i(int(row[key][0]),int(row[key][1]),int(row[key][2]))
 state.rows=list_fixture.rows.duplicate(true)
 var view=preload("res://scripts/reports_view.gd").new();root.add_child(view);view.configure(assets,state,OS.get_environment("DF3D_DF_PATH"))
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/all.png")
 # Native073631 All: wheel/Shift-wheel over text AND scrollbar, arrows and
 # Page Up/Down leave the current row unchanged. Unit lists differ below.
 state.scroll_to(2)
 for x in [500,968]:
  for shift in [false,true]:
   for direction in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
    var wheel:=InputEventMouseButton.new();wheel.position=Vector2(x,300);wheel.global_position=wheel.position
    wheel.button_index=direction;wheel.pressed=true;wheel.shift_pressed=shift;root.push_input(wheel)
    assert(state.first_row==2)
    wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel)
 for code in [KEY_UP,KEY_DOWN,KEY_PAGEUP,KEY_PAGEDOWN]:
  var key:=InputEventKey.new();key.keycode=code;key.pressed=true;root.push_input(key)
  assert(state.first_row==2)
  key=key.duplicate();key.pressed=false;root.push_input(key)
 state.scroll_to(0)
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 assert(view.tab_targets.size()==25)
 var centered:Array=[];state.recenter_requested.connect(func(tile):centered.append(tile))
 var recenter:=InputEventMouseButton.new();recenter.position=view.position+view.report_targets[1].rect.get_center()
 recenter.global_position=recenter.position;recenter.button_index=MOUSE_BUTTON_LEFT;recenter.pressed=true
 var move:=InputEventMouseMotion.new();move.position=recenter.position;move.global_position=move.position;root.push_input(move)
 root.push_input(recenter);assert(not state.opened and centered==[list_fixture.rows[0].position2])
 recenter=recenter.duplicate();recenter.pressed=false;root.push_input(recenter)
 state.open();state.rows=list_fixture.rows.duplicate(true);state.changed.emit()
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 # Exercise viewport hit testing, including a disabled native tab.
 for tab in [2,23]:
  var target: Rect2
  for candidate in view.tab_targets:
   if candidate.tab==tab:target=candidate.rect
  var pointer:=InputEventMouseButton.new()
  pointer.position=view.position+target.get_center();pointer.global_position=pointer.position
  pointer.button_index=MOUSE_BUTTON_LEFT;pointer.pressed=true
  root.push_input(pointer)
  pointer=pointer.duplicate();pointer.pressed=false;root.push_input(pointer)
  assert(state.selected_tab==(1 if tab==2 else 23))
 var fixture=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DF3D_REPORTS_UNITS")))
 state.rows=[]
 for row in fixture.rows:
  if int(row.category)==0:state.rows.append(row)
 state.changed.emit()
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/combat.png")
 assert(view.unit_targets.size()==15)
 for probe in [[706,1],[400,15]]:
  state.scroll_to(0)
  var click:=InputEventMouseButton.new();click.position=Vector2(968,probe[0]);click.global_position=click.position
  click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;root.push_input(click)
  assert(state.first_row==probe[1])
  click=click.duplicate();click.pressed=false;root.push_input(click)
 state.scroll_to(0)
 var grip:=InputEventMouseButton.new();grip.position=Vector2(968,166);grip.global_position=grip.position
 grip.button_index=MOUSE_BUTTON_LEFT;grip.pressed=true;root.push_input(grip)
 var motion:=InputEventMouseMotion.new();motion.position=Vector2(968,400);motion.global_position=motion.position;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
 root.push_input(motion);assert(state.first_row==36)
 grip=grip.duplicate();grip.position=motion.position;grip.pressed=false;root.push_input(grip)
 assert(not view.scrollbar.dragging)
 state.scroll_to(0)
 for step in [[MOUSE_BUTTON_WHEEL_DOWN,false,1],[MOUSE_BUTTON_WHEEL_UP,false,0],[MOUSE_BUTTON_WHEEL_DOWN,true,15],[MOUSE_BUTTON_WHEEL_UP,true,0]]:
  var wheel:=InputEventMouseButton.new();wheel.position=view.position+Vector2(400,250)
  wheel.global_position=wheel.position;wheel.button_index=step[0];wheel.shift_pressed=step[1];wheel.pressed=true
  root.push_input(wheel);assert(view.scroll_row==step[2])
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 var button:=InputEventMouseButton.new();button.position=view.position+view.unit_targets[0].rect.get_center()
 button.global_position=button.position;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true
 root.push_input(button)
 assert(state.unit_id==int(fixture.rows[0].unit_id))
 assert(state.pending.request.view==3 and state.pending.request.from_end)
 view.input_allowed=func():return false
 var back:=InputEventMouseButton.new();back.position=Vector2(400,300);back.global_position=back.position
 back.button_index=MOUSE_BUTTON_RIGHT;back.pressed=true
 root.push_input(back);assert(state.opened)
 view.input_allowed=func():return true
 root.push_input(back);assert(not state.opened)
 state.open();state.selected_tab=11;state.tab_rows=[state.INITIAL_ROWS[0].duplicate(),state.INITIAL_ROWS[2].duplicate(),state.INITIAL_ROWS[1].duplicate()]
 state.rows=[]
 for row in list_fixture.rows:
  if row.category in ["STRANGE_MOOD","MOOD_BUILDING_CLAIMED","ARTIFACT_BEGUN","MADE_ARTIFACT"]:state.rows.append(row)
 state.changed.emit()
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/wrapping.png")
 state.unit_id=int(list_fixture.unit_log.unit_id);state.unit_category=1
 state.rows=list_fixture.unit_log.rows.duplicate(true);state.log_first=maxi(0,state.rows.size()-17);state.total=697;state.log_start=697-state.rows.size();state.log_requested=680;state.changed.emit()
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/unit_log.png")
 var toggle:=InputEventMouseButton.new();toggle.position=Vector2(940,94);toggle.global_position=toggle.position
 toggle.button_index=MOUSE_BUTTON_LEFT;toggle.pressed=true
 view.input_allowed=func():return false
 root.push_input(toggle);assert(not state.pause_on_new)
 view.input_allowed=func():return true
 root.push_input(toggle);assert(state.pause_on_new)
 toggle=toggle.duplicate();toggle.pressed=false;root.push_input(toggle)
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/unit_log_pause.png")
 var log_wheel:=InputEventMouseButton.new();log_wheel.position=Vector2(968,400);log_wheel.global_position=log_wheel.position
 log_wheel.button_index=MOUSE_BUTTON_WHEEL_UP;log_wheel.pressed=true;root.push_input(log_wheel)
 assert(state.log_requested==680)
 var log_arrow:=InputEventMouseButton.new();log_arrow.position=Vector2(968,118);log_arrow.global_position=log_arrow.position
 log_arrow.button_index=MOUSE_BUTTON_LEFT;log_arrow.pressed=true;root.push_input(log_arrow)
 assert(state.log_requested==679)
 log_arrow=log_arrow.duplicate();log_arrow.pressed=false;root.push_input(log_arrow)
 state.scroll_to(680)
 log_arrow=log_arrow.duplicate();log_arrow.position=Vector2(968,400);log_arrow.pressed=true;root.push_input(log_arrow)
 assert(state.log_requested==663)
 log_arrow=log_arrow.duplicate();log_arrow.pressed=false;root.push_input(log_arrow)
 if not OS.get_environment("DF3D_REPORTS_CONTROLS").is_empty():
  var controls:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DF3D_REPORTS_CONTROLS")))
  state.rows=[]
  for raw in controls.rows:
   var row:Dictionary=raw.duplicate(true)
   for key in ["position","position2"]:row[key]=Vector3i(int(row[key][0]),int(row[key][1]),int(row[key][2]))
   state.rows.append(row)
  state.pending={};state.total=6;state.log_start=0;state.log_first=0;state.log_requested=0;state.next_before=-1;state.next_after=-1;state.changed.emit()
  for i in 3:await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/log_controls.png")
  assert(view.report_targets.size()==7 and view.speaker_targets.size()==3)
  assert(view.report_targets[1].secondary and view.report_targets[1].rect.position.x==880)
  assert(not view.report_targets[2].secondary and view.report_targets[2].rect.position.x==856)
  var retained:Array=state.rows.duplicate(true)
  var secondary:=InputEventMouseButton.new();secondary.position=view.position+view.report_targets[3].rect.get_center();secondary.global_position=secondary.position
  secondary.button_index=MOUSE_BUTTON_LEFT;secondary.pressed=true;root.push_input(secondary)
  assert(not state.opened and centered.back()==Vector3i(140,80,165))
  state.open();state.unit_id=2905;state.unit_category=1;state.rows=retained;state.pending={};state.total=6;state.changed.emit()
  for i in 3:await process_frame;await RenderingServer.frame_post_draw
  var speakers:Array=[];state.speaker_requested.connect(func(id):speakers.append(id))
  secondary=secondary.duplicate();secondary.pressed=false;root.push_input(secondary)
  var speaker:=InputEventMouseButton.new();speaker.position=view.position+view.speaker_targets[1].rect.get_center();speaker.global_position=speaker.position
  speaker.button_index=MOUSE_BUTTON_LEFT;speaker.pressed=true;root.push_input(speaker)
  assert(state.opened and speakers==[2905]) # Router closes only after resolving the speaker.
 for sample in fixture.get("category_rendering",{}).get("categories",[]):
  state.open();state.selected_tab=23+int(sample.category);state.rows=sample.rows.duplicate(true)
  state.pending={};state.total=state.rows.size();state.counts[state.selected_tab-1]=state.rows.size();state.changed.emit()
  for i in 3:await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("DF3D_REPORTS_FRAME")+"/category_"+str(sample.name)+".png")
 print("REPORTS_FRAME_CAPTURE_PASS")
 view.queue_free();assets.queue_free();await process_frame;quit()
