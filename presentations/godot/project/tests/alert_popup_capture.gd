extends SceneTree
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1200,800)
 var directory:=OS.get_environment("DF3D_ALERT_FRAMES")
 var world:=Df3dWorld.new();root.add_child(world)
 if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DF3D_ALERT_FIXTURE")))
 var source:Dictionary=fixture.render_fixture.report
 var state=preload("res://scripts/alert_entries_state.gd").new()
 state.opened=true;state.complete=true;state.loaded=true
 state.rows=[{"kind":"report","data":{"id":int(source.id),"text":source.text,"text_complete":true,"repeat_count":2,"color":2,"bright":true,"position_visible":true,"position":Vector3i(125,50,165)}}]
 var view=preload("res://scripts/alert_entries_view.gd").new();root.add_child(view);view.configure(world,state,OS.get_environment("DF3D_DF_PATH"))
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/open.png")
 var metadata:={"lines":view.lines.size(),"page":view.PAGE_LINES,"first":view.first_line}
 for i in 4:
  var track_click:=InputEventMouseButton.new();track_click.position=Vector2(759,430);track_click.global_position=track_click.position;track_click.button_index=MOUSE_BUTTON_LEFT;track_click.pressed=true
  var track_motion:=InputEventMouseMotion.new();track_motion.position=track_click.position;track_motion.global_position=track_motion.position;root.push_input(track_motion);root.push_input(track_click)
  track_click=track_click.duplicate();track_click.pressed=false;root.push_input(track_click)
  await process_frame
 var leave:=InputEventMouseMotion.new();leave.position=Vector2(500,300);leave.global_position=leave.position;root.push_input(leave)
 print("AFTER_TRACK ",view.scrollbar.hover_cell," ",view.scrollbar.dragging)
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/bottom.png")
 metadata["bottom"]=view.first_line
 var bar_motion:=InputEventMouseMotion.new();bar_motion.position=Vector2(759,430);bar_motion.global_position=bar_motion.position;root.push_input(bar_motion)
 bar_motion=bar_motion.duplicate();bar_motion.position=Vector2(500,300);bar_motion.global_position=bar_motion.position;root.push_input(bar_motion)
 assert(view.scrollbar.hover_cell==-1)
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 print("SCROLLBAR_POINTER_STATE ",view.scrollbar.hover_cell," ",root.get_mouse_position())
 root.get_texture().get_image().save_png(directory+"/pointer-bottom.png")
 # Native112636 wheel/page input goes through the actual viewport route.
 var old_first:int=view.first_line
 var wheel:=InputEventMouseButton.new();wheel.position=Vector2(500,300);wheel.global_position=wheel.position;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
 root.push_input(wheel);assert(view.first_line==old_first-1)
 wheel=wheel.duplicate();wheel.shift_pressed=true;root.push_input(wheel)
 assert(view.first_line==maxi(0,old_first-1-view.PAGE_LINES))
 view.input_allowed=func():return false
 var blocked_first:int=view.first_line;root.push_input(wheel);assert(view.first_line==blocked_first)
 view.input_allowed=Callable();view.scroll_to(old_first)
 var f:=FileAccess.open(directory+"/geometry.json",FileAccess.WRITE);f.store_string(JSON.stringify(metadata));f.close()
 # Independent native mixed report/unit capture053415.
 var units_fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DF3D_ALERT_UNITS")))
 var unit:Dictionary={}
 for candidate in units_fixture.rows:
  if int(candidate.unit_id)==6837 and int(candidate.category)==1:unit=candidate;break
 assert(not unit.is_empty())
 var previous:Array=state.rows.duplicate(true)
 state.rows=[]
 for label in ["Entries native second","Entries native first","Entries native second"]:
  state.rows.append({"kind":"report","data":{"id":1,"text":label,"text_complete":true,"color":2,"bright":true,"position_visible":true,"position":Vector3i(125,50,165)}})
 state.rows.append({"kind":"unit","data":unit});state.rows.append({"kind":"unit","data":unit})
 state.generation+=1;state.changed.emit()
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/mixed.png")
 assert(view.lines.size()==15 and not view.scrollbar.visible and view.has_units)
 var selected:Array=[];view.unit_requested.connect(func(id,category):selected.append([id,category]))
 var unit_click:=InputEventMouseButton.new();unit_click.position=view.position+view.targets[3].rect.get_center();unit_click.global_position=unit_click.position;unit_click.button_index=MOUSE_BUTTON_LEFT;unit_click.pressed=true
 var unit_motion:=InputEventMouseMotion.new();unit_motion.position=unit_click.position;unit_motion.global_position=unit_motion.position;root.push_input(unit_motion);root.push_input(unit_click)
 assert(selected==[[6837,1]] and state.opened)
 unit_click=unit_click.duplicate();unit_click.pressed=false;root.push_input(unit_click)
 # Native084855: prose from a partial final row remains, but its control does not.
 state.rows=[];state.unit_id=17
 for id in 11:state.rows.append({"kind":"report","data":{"id":id,"text":"Fixture","text_complete":true,"position_visible":true,"position":Vector3i(125,50,165)}})
 state.generation+=1;state.changed.emit()
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 assert(view.lines.size()==33 and view.targets.size()==9)
 # Native113534/real client113650: unit wheel reacts inside header/body/bar,
 # while outside wheel leaves its position unchanged.
 for at in [Vector2(500,80),Vector2(500,300),Vector2(759,150),Vector2(1000,600)]:
  view.scroll_to(0)
  var down:=InputEventMouseButton.new();down.position=at;down.global_position=at;down.button_index=MOUSE_BUTTON_WHEEL_DOWN;down.pressed=true
  root.push_input(down);assert(view.first_line==(0 if at.x==1000 else 1))
 view.scroll_to(0)

 state.unit_id=-1
 state.rows=previous;state.generation+=1;state.changed.emit()
 # Actual viewport pointer route and host guard.
 view.scroll_to(0)
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 var centered:Array=[];view.recenter_requested.connect(func(tile):centered.append(tile))
 var click:=InputEventMouseButton.new();click.position=view.position+view.targets[0].rect.get_center();click.global_position=click.position;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
 var motion:=InputEventMouseMotion.new();motion.position=click.position;motion.global_position=motion.position;root.push_input(motion)
 view.input_allowed=func():return false
 root.push_input(click);assert(state.opened and centered.is_empty())
 click=click.duplicate();click.pressed=false;root.push_input(click)
 view.input_allowed=func():return true
 click=click.duplicate();click.pressed=true;root.push_input(click)
 assert(not state.opened and centered==[Vector3i(125,50,165)])
 state.opened=true;state.complete=true;state.changed.emit()
 var outside:=InputEventMouseButton.new();outside.position=Vector2(1000,600);outside.global_position=outside.position;outside.button_index=MOUSE_BUTTON_LEFT;outside.pressed=true
 root.push_input(outside);assert(not state.opened and centered.size()==1)
 state.opened=true;state.complete=true;state.changed.emit()
 for extent in [Vector2i(1600,900),Vector2i(960,600),Vector2i(1237,805),Vector2i(1238,810),Vector2i(1200,800)]:
  root.size=extent
  for i in 3:await process_frame;await RenderingServer.frame_post_draw
  assert(view.position==Vector2(32+int((extent.x%8)/2),48+int((extent.y%12)/2)))
  assert(view.size==Vector2(752,420) and view.scrollbar.page==29)
 var launcher=preload("res://scripts/red_alert_launcher.gd").new();launcher.world=world;root.add_child(launcher)
 launcher.position=Vector2(0,76)
 var opened:Array=[];launcher.group_requested.connect(func(group):opened.append(group))
 launcher.update_state({"fortress_valid":true,"fortress_epoch":7,"alert_button_report_count":257,"alert_button_report_ids":[],"alert_button_complete":false},true)
 assert(launcher.visible)
 var press:=InputEventMouseButton.new();press.position=Vector2(28,94);press.global_position=press.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 state.close();root.push_input(press);assert(opened==[{"alert_button":true,"fortress_epoch":7}])
 launcher.update_state({"fortress_valid":true,"fortress_epoch":8,"alert_button_report_count":1},false)
 root.push_input(press);assert(opened.size()==1)
 launcher.update_state({"fortress_valid":true,"fortress_epoch":8,"alert_button_report_count":1},true)
 root.push_input(press);assert(opened.back().fortress_epoch==8)
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/red-alert.png")
 launcher.update_state({},true);assert(not launcher.visible)
 launcher.free()
 print("ALERT_POPUP_FRAME_PASS")
 view.free();world.queue_free();await process_frame;quit()
