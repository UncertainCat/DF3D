extends "res://tests/farm_body_capture.gd"
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(77);return
 root.size=Vector2i(1200,800)
 var world:=Df3dWorld.new();root.add_child(world)
 if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Health assets unavailable");return
 var background:=ColorRect.new();root.add_child(background)
 background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12);background.size=Vector2(1200,800)
 var view=preload("res://scripts/creature_health_view.gd").new();root.add_child(view)
 view.position=Vector2(424,232);view.size=Vector2(472,516);view.configure(world)
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_health_pages_reference
 var references: Array=fixture.rendered_text_reference.pages
 var failures:=0
 for index in 5:
  var reference: Dictionary=references[index]
  view.present(fixture.owned_probe_reference.pages[index].probe.rows,str(index))
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
  image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-health-"+reference.name+".png"))
  var r: Array=reference.rect;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
  hash.update(image.get_region(Rect2i(r[0],r[1],r[2],r[3])).get_data())
  if hash.finish().hex_encode()!=reference.sha256:push_error("Native Health pixels differ: "+reference.name);failures+=1
 var layout: Dictionary=fixture.layout_reference
 var overflow: Array=[]
 for _i in int(layout.line_count):overflow.append("")
 for sample in layout.cases:
  root.size=Vector2i(sample.viewport[0],sample.viewport[1]);background.size=root.size
  var r: Array=sample.view_rect;view.position=Vector2(r[0],r[1]);view.size=Vector2(r[2],r[3])
  view.first=0;view.present(overflow,"History")
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  if view.capacity()!=int(sample.capacity):push_error("Native Health capacity differs: "+sample.name);failures+=1
  var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
  var crop: Array=sample.scrollbar_rect;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
  hash.update(image.get_region(Rect2i(crop[0],crop[1],crop[2],crop[3])).get_data())
  image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-health-layout-"+sample.name+".png"))
  if hash.finish().hex_encode()!=sample.rgb_sha256:push_error("Native Health scrollbar pixels differ: "+sample.name);failures+=1
 for sample in layout.input:
  if not str(sample.name).begins_with("CONTEXT_SCROLL_"):continue
  view.first=7;view.layout()
  var point: Vector2=view.get_global_transform_with_canvas()*Vector2(120,100)
  var event:=InputEventMouseButton.new();event.position=point;event.pressed=true
  event.button_index=MOUSE_BUTTON_WHEEL_UP if str(sample.name).ends_with("UP") else MOUSE_BUTTON_WHEEL_DOWN
  event.shift_pressed=str(sample.name).contains("PAGE");root.push_input(event,true)
  event.pressed=false;root.push_input(event,true)
  if view.first!=int(sample.first):push_error("Native Health wheel differs: "+sample.name);failures+=1
 var expected: Dictionary={}
 for sample in layout.input:expected[sample.name]=sample
 var observe:=func(name):return view.first==int(expected[name].first) and view.scrollbar.dragging==expected[name].dragging
 for sample in [["up-left",874,250],["up-right",880,250],["down-left",874,730],["down-right",880,730],["track-above",880,270],["track-below",880,680]]:
  view.first=7;view.layout();click(Vector2(sample[1],sample[2]))
  if not observe.call("input-"+sample[0]):push_error("Health native scrollbar click differs: "+sample[0]);failures+=1
 view.first=7;view.layout()
 var motion:=InputEventMouseMotion.new();motion.position=Vector2(880,400);root.push_input(motion,true)
 var press:=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
 if not observe.call("drag-start"):push_error("Health native drag start differs");failures+=1
 motion=InputEventMouseMotion.new();motion.position=Vector2(880,500);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
 if not observe.call("drag-move"):push_error("Health native drag move differs");failures+=1
 press=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;root.push_input(press,true)
 if not observe.call("drag-release"):push_error("Health native drag release differs");failures+=1
 for sample in [["body",600,400],["top-padding",600,238],["bottom-padding",600,746],["footer",600,770],["outside",400,400]]:
  view.first=7;view.layout()
  var wheel:=InputEventMouseButton.new();wheel.position=Vector2(sample[1],sample[2]);wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;root.push_input(wheel,true)
  wheel.pressed=false;root.push_input(wheel,true)
  if not observe.call("wheel-"+sample[0]):push_error("Health native wheel boundary differs: "+sample[0]);failures+=1
 view.first=7;view.present(fixture.owned_probe_reference.pages[0].probe.rows,"Status")
 await process_frame;await RenderingServer.frame_post_draw
 var short_page:=root.get_texture().get_image();short_page.convert(Image.FORMAT_RGB8)
 var short_hash:=HashingContext.new();short_hash.start(HashingContext.HASH_SHA256)
 short_hash.update(short_page.get_region(Rect2i(432,244,424,312)).get_data())
 if view.first!=7 or short_hash.finish().hex_encode()!=references[0].sha256:push_error("Short Health page lost native shared scroll or text");failures+=1
 var short_wheel:=InputEventMouseButton.new();short_wheel.position=view.get_global_transform_with_canvas()*Vector2(120,100);short_wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;short_wheel.pressed=true;root.push_input(short_wheel,true)
 short_wheel.pressed=false;root.push_input(short_wheel,true)
 view.present(overflow,"History")
 if view.first!=7:push_error("Health subtab return lost shared scroll");failures+=1
 view.queue_free();world.queue_free();background.queue_free();await process_frame
 if failures==0:print("CREATURE_HEALTH_CAPTURE_PASS")
 quit(1 if failures else 0)
