extends "res://tests/frame_profile.gd"
# GPU lifecycle check for the separate renderer: resize, mode switches, capture,
# and complete scene teardown. Use a fixed recorded fortress, never native input.
func run():
 root.size = Vector2i(1920,1080)
 scene = load("res://scenes/main.tscn").instantiate()
 root.add_child(scene)
 var deadline = Time.get_ticks_msec()+120000
 while not ready_scene() and Time.get_ticks_msec()<deadline: await process_frame
 if not ready_scene(): push_error("Thread fixture did not settle"); quit(1); return
 for cycle in 2:
  for mode in ["df","free","billboard"]:
   root.size = Vector2i(1280,720) if cycle == 0 else Vector2i(1920,1080)
   scene.camera_rig.set_df_mode(mode=="df")
   scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
   for frame in 120: await process_frame
   await RenderingServer.frame_post_draw
   var image = root.get_texture().get_image()
   var colors = {}
   for y in range(0,image.get_height(),16):
    for x in range(0,image.get_width(),16): colors[image.get_pixel(x,y)] = true
   if colors.size()<100: push_error("Blank render after mode/resize"); quit(1); return
   if cycle == 1:
    image.save_png(OS.get_environment("DF3D_THREAD_TEST_OUT")+"-"+mode+".png")
 scene.queue_free()
 for frame in 10: await process_frame
 print("RENDER_THREAD_FIXTURE_PASS")
 quit()
