extends "res://tests/mesh_batch_motion_live.gd"
# Fixed paused world: separate spatial-batch and occlusion effects without sim drift.
func run():
 root.size=Vector2i(1920,1080)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
 var deadline=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(0.1).timeout
 if not scene._loader.entered: push_error("Visibility profile load failed");quit(1);return
 if not await set_paused(true): push_error("Cannot pause visibility fixture");quit(1);return
 if OS.get_environment("DF3D_PERF_DEMAND_COMPARE")=="1":
  var close_view=OS.get_environment("DF3D_PERF_DEMAND_CLOSE")=="1"
  if close_view: scene.world.set_window_depth(4)
  for mode in ["free","df","billboard"]:
   scene.camera_rig.set_df_mode(mode=="df");scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
   await go_level(128)
   if close_view:
    scene.camera_rig.focus_on(Vector3(24,129,96),20)
    await settle()
   for demand in [false,true]:
    scene._presentation_demand_enabled=demand
    await settle()
    var label=mode+("_demand" if demand else "_full")
    await sample(label,mode=="df",false,180,60)
    results.back()["materialized_items"]=scene.world.item_drawn_count()
    results.back()["art_margin"]=scene.world.presentation_art_margin()
    results.back()["window"]=scene.world.get_window_depth()
    results.back()["region"]=str(preload("res://scripts/presentation_demand.gd").region(scene.get_node("CameraRig/Camera3D"),scene.world.get_top_z(),scene.world.get_window_depth(),scene.world.presentation_art_margin()))
    if not scene.world.layout_matches_reference(): push_error("Demand layout mismatch: "+label);quit(1);return
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output+"-"+label+".png")
   var f=FileAccess.open(output+".json",FileAccess.WRITE);f.store_string(JSON.stringify(results,"  "))
  print("FLOOR_PROFILE_PASS");quit();return
 if OS.get_environment("DF3D_PERF_DEPTH_SWEEP")=="1":
  scene.camera_rig.set_df_mode(false);scene._sprite_presentation.set_style("billboard")
  scene.configure_sprite_batches(false,16,1)
  for depth in [1,4,8,16,24]:
   scene.world.set_window_depth(depth)
   await go_level(128)
   for occlusion in [false,true]:
    root.use_occlusion_culling=occlusion
    await settle()
    await sample("billboard_depth"+str(depth)+("_occlusion" if occlusion else "_open"),false,false,180,60)
    results.back()["mesh_batches"]=scene.world.mesh_batch_stats()
   var f=FileAccess.open(output+".json",FileAccess.WRITE);f.store_string(JSON.stringify(results,"  "))
  print("FLOOR_PROFILE_PASS");quit();return
 var configs=[
  {"name":"global","enabled":false,"xy":16,"z":1,"occlusion":false},
  {"name":"spatial_16x1","enabled":true,"xy":16,"z":1,"occlusion":false},
  {"name":"spatial_32x1","enabled":true,"xy":32,"z":1,"occlusion":false},
  {"name":"spatial_32x4","enabled":true,"xy":32,"z":4,"occlusion":false},
  {"name":"occlusion_16x1","enabled":true,"xy":16,"z":1,"occlusion":true},
  {"name":"occlusion_global","enabled":false,"xy":16,"z":1,"occlusion":true}]
 for mode in ["free","df","billboard"]:
  scene.camera_rig.set_df_mode(mode=="df");scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
  await go_level(128)
  for config in configs:
   scene.configure_sprite_batches(config.enabled,config.xy,config.z)
   root.use_occlusion_culling=config.occlusion
   await settle()
   await sample(mode+"_"+config.name,mode=="df",false,180,60)
   results.back()["sprite_batches"]=scene.sprite_batch_stats()
   var rectangles=0
   for node in scene.get_node("Terrain").get_children(): rectangles+=int(node.get_meta("df3d_occluder_rects",0))
   results.back()["occluder_rectangles"]=rectangles
   if config.name in ["spatial_16x1","occlusion_16x1"]:
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output+"-"+mode+"-"+config.name+".png")
   var f=FileAccess.open(output+".json",FileAccess.WRITE);f.store_string(JSON.stringify(results,"  "))
 print("FLOOR_PROFILE_PASS")
 quit()
