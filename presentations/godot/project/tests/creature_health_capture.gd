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
  view.present(fixture.owned_probe_reference.pages[index].probe.rows,str(index),0)
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
  image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-health-"+reference.name+".png"))
  var r: Array=reference.rect;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
  hash.update(image.get_region(Rect2i(r[0],r[1],r[2],r[3])).get_data())
  if hash.finish().hex_encode()!=reference.sha256:push_error("Native Health pixels differ: "+reference.name);failures+=1
 view.queue_free();world.queue_free();background.queue_free();await process_frame
 if failures==0:print("CREATURE_HEALTH_CAPTURE_PASS")
 quit(1 if failures else 0)
