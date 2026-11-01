extends "res://tests/farm_body_capture.gd"
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(77);return
 root.size=Vector2i(1200,800)
 var world:=Df3dWorld.new();root.add_child(world)
 if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Knowledge assets unavailable");return
 var background:=ColorRect.new();root.add_child(background)
 background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12);background.size=Vector2(1200,800)
 var view=preload("res://scripts/native_creature_paragraph_view.gd").new();root.add_child(view)
 view.position=Vector2(424,232);view.size=Vector2(472,516);view.configure(world)
 var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_skills_reference.detail_render_reference
 var failures:=0
 for sample in reference.cases:
  view.first=0;view.present(sample.rows,str(sample.kind)+"/"+str(sample.id))
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
  image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-knowledge-"+str(sample.kind)+".png"))
  var r: Array=sample.rect;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
  hash.update(image.get_region(Rect2i(r[0],r[1],r[2],r[3])).get_data())
  if hash.finish().hex_encode()!=sample.rgb_sha256:push_error("Native Knowledge detail pixels differ: "+str(sample.kind));failures+=1
 var inputs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_skills_reference.detail_input_reference
 var expected: Dictionary={}
 for sample in inputs.observations:expected[sample.name]=sample
 view.present(inputs.rows,"music")
 if view.lines.size()!=int(expected.opened.line_count):push_error("Knowledge native wrapped line count differs");failures+=1
 var matches:=func(name):return view.first==int(expected[name].first) and view.scrollbar.dragging==expected[name].dragging
 for sample in inputs.observations:
  if not str(sample.name).begins_with("CONTEXT_SCROLL_"):continue
  view.first=7;view.layout()
  var wheel:=InputEventMouseButton.new();wheel.position=Vector2(600,400);wheel.pressed=true
  wheel.button_index=MOUSE_BUTTON_WHEEL_UP if str(sample.name).ends_with("UP") else MOUSE_BUTTON_WHEEL_DOWN
  wheel.shift_pressed=str(sample.name).contains("PAGE");root.push_input(wheel,true);wheel.pressed=false;root.push_input(wheel,true)
  if not matches.call(sample.name):push_error("Knowledge wheel differs: "+sample.name);failures+=1
 for sample in [["up-left",874,250],["up-right",880,250],["down-left",874,730],["down-right",880,730],["track-above",880,260],["track-below",880,680]]:
  view.first=7;view.layout();click(Vector2(sample[1],sample[2]))
  if not matches.call("input-"+sample[0]):push_error("Knowledge click differs: "+sample[0]);failures+=1
 view.first=7;view.layout()
 var motion:=InputEventMouseMotion.new();motion.position=Vector2(880,400);root.push_input(motion,true)
 var press:=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
 if not matches.call("drag-start"):push_error("Knowledge drag start differs");failures+=1
 motion=InputEventMouseMotion.new();motion.position=Vector2(880,500);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
 if not matches.call("drag-move"):push_error("Knowledge drag move differs");failures+=1
 press=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;root.push_input(press,true)
 if not matches.call("drag-release"):push_error("Knowledge drag release differs");failures+=1
 for sample in [["body",600,400],["top-padding",600,238],["bottom-padding",600,746],["footer",600,770],["outside",400,400]]:
  view.first=7;view.layout()
  var wheel:=InputEventMouseButton.new();wheel.position=Vector2(sample[1],sample[2]);wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;root.push_input(wheel,true);wheel.pressed=false;root.push_input(wheel,true)
  if not matches.call("wheel-"+sample[0]):push_error("Knowledge wheel boundary differs: "+sample[0]);failures+=1
 for sample in inputs.rendered:
  view.first=int(expected[sample.name].first);view.layout()
  motion=InputEventMouseMotion.new();motion.position=Vector2(400,400);root.push_input(motion,true)
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
  image.save_png(ProjectSettings.globalize_path("res://../../../build/knowledge-input-"+sample.name+".png"))
  var r: Array=sample.rect;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
  hash.update(image.get_region(Rect2i(r[0],r[1],r[2],r[3])).get_data())
  if hash.finish().hex_encode()!=sample.rgb_sha256:push_error("Knowledge scrolled pixels differ: "+sample.name);failures+=1
 view.queue_free();world.queue_free();background.queue_free();await process_frame
 if failures==0:print("CREATURE_KNOWLEDGE_CAPTURE_PASS")
 quit(1 if failures else 0)
