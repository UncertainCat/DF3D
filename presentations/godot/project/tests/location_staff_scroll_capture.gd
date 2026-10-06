extends SceneTree
func _initialize() -> void:call_deferred("run")
func pointer_motion(point: Vector2, held := false) -> void:
 var event := InputEventMouseMotion.new(); event.position = point; event.global_position = point
 event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
 root.push_input(event,true)

func pointer_button(point: Vector2, button: int, pressed: bool, shift := false) -> void:
 var event := InputEventMouseButton.new(); event.position = point; event.global_position = point
 event.button_index = button; event.pressed = pressed; event.shift_pressed = shift
 event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
 root.push_input(event,true)


func sample(id: int,count: int) -> Dictionary:
 var rows: Array=[]
 for i in count:rows.append({"source":0,"role":7,"names":{"holder_name":""}})
 return {"id":id,"kind":{0:2,1:1,2:5,3:2,4:3}[id],"staff":{"rows":rows}}
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(77);return
 root.size=Vector2i(1200,800)
 var world:=Df3dWorld.new();root.add_child(world)
 if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
 var view=preload("res://scripts/location_staff_view.gd").new();root.add_child(view);view.configure(world);view.layout(Vector2(1200,800))
 var bar=view.native_scroll
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_scroll.json"))
 var previous:=-1
 for row in data.input:
  if previous!=int(row.id):
   previous=int(row.id);view.display(sample(previous,50));await process_frame;await RenderingServer.frame_post_draw
  bar.move_to(int(row.start))
  var point:=Vector2(952,float(row.y))
  if str(row.label).begins_with("STANDARDSCROLL"):
   var event:=InputEventKey.new();event.pressed=true
   event.keycode={"STANDARDSCROLL_UP":KEY_UP,"STANDARDSCROLL_DOWN":KEY_DOWN,"STANDARDSCROLL_PAGEUP":KEY_PAGEUP,"STANDARDSCROLL_PAGEDOWN":KEY_PAGEDOWN}[row.label]
   root.push_input(event,true);event.pressed=false;root.push_input(event,true)
  elif row.label=="drag":
   var start:=Vector2(952,float(row.top)+18)
   pointer_motion(start);pointer_button(start,MOUSE_BUTTON_LEFT,true)
   pointer_motion(point,true);pointer_button(point,MOUSE_BUTTON_LEFT,false)
  else:
   var button:=MOUSE_BUTTON_LEFT;var shift:=false
   if str(row.label).begins_with("CONTEXT_SCROLL"):
    button=MOUSE_BUTTON_WHEEL_UP if str(row.label).ends_with("UP") else MOUSE_BUTTON_WHEEL_DOWN
    shift="PAGE" in str(row.label)
   pointer_motion(point);pointer_button(point,button,true,shift);pointer_button(point,button,false,shift)
  if bar.first!=int(row.after) or view.first!=int(row.after) or bar.dragging:
   push_error("Staff pointer mismatch "+str(row)+" actual="+str(bar.first));quit(1);return
 # Retain local scroll on same-location receipt refresh; clear on new identity.
 bar.move_to(12);view.display(sample(previous,50))
 if view.first!=12:push_error("Staff refresh reset local scroll");quit(1);return
 view.display(sample(2,8))
 if view.first!=0:push_error("Staff location switch retained scroll");quit(1);return
 var atlas:=Image.load_from_file(OS.get_environment("DF3D_DF_PATH").path_join("data/vanilla/vanilla_interface/graphics/images/interface_bits.png"))
 var origin:=120107-13*64
 pointer_motion(Vector2(1100,750))
 for row in data.art:
  view.display(sample(int(row.id),int(row.count)),int(row.first))
  bar.hover_cell=floori(float(row.hover)/12) if int(row.hover)>=0 else -1;bar.queue_redraw()
  await process_frame;await RenderingServer.frame_post_draw
  if bar.visible!=(int(row.count)>int(row.page)):push_error("Staff scroll visibility mismatch");quit(1);return
  if not bar.visible:continue
  var image:=root.get_texture().get_image()
  for y in int(row.height)/12:
   for column in 2:
    var tile:=int(row.tiles[y].left if column==0 else row.tiles[y].right)-origin
    for py in 12:
     for px in 8:
      if image.get_pixel(944+column*8+px,int(row.top)+y*12+py)!=atlas.get_pixel((tile%64)*8+px,(tile/64)*12+py):
       push_error("Staff scrollbar art mismatch "+str([row.id,row.count,row.first,row.hover,y]));quit(1);return
 view.display({})
 if bar.visible or bar.dragging:push_error("Closed staff retained scrollbar");quit(1);return
 view.queue_free();world.queue_free();await process_frame
 print("LOCATION_STAFF_SCROLL_CAPTURE_PASS");quit(0)
