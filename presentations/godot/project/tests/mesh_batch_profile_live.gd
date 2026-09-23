extends "res://tests/floor_profile_live.gd"
# Same save/frame/camera, old submission vs spatial batches; no fidelity toggles.
func settle():
 var deadline=Time.get_ticks_msec()+120000
 for i in 12: await process_frame
 var next_report=Time.get_ticks_msec()+10000
 while not ready_scene() and Time.get_ticks_msec()<deadline:
  await process_frame
  if Time.get_ticks_msec()>=next_report:
   next_report=Time.get_ticks_msec()+10000
   print("SETTLE_WAIT ",JSON.stringify({"focused":scene._focused,"blocks":scene.world.pending_block_count(),"units":scene.world.composite_pending_count(),"items":scene.world.item_composite_pending_count(),"buildings":scene.world.building_pending_count()}))
 if not ready_scene():
  push_error("Batch profile did not settle: "+JSON.stringify({"batches":scene.world.mesh_batch_stats(),"focused":scene._focused,"terrain":scene.world.terrain_loaded(),"block_pending":scene.world.pending_block_count(),"unit_pending":scene.world.composite_pending_count(),"item_pending":scene.world.item_composite_pending_count(),"building_pending":scene.world.building_pending_count()}))
  quit(1)
 for i in 12: await process_frame
func run():
 root.size=Vector2i(1920,1080)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 scene=load("res://scenes/main.tscn").instantiate()
 root.add_child(scene)
 var deadline=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(0.1).timeout
 if not scene._loader.entered: push_error("Batch profile load failed"); quit(1); return
 offset=int(scene._session_state.get("fortress_summary",{}).get("elevation_offset",0))
 for z in [128,72,153]:
  for mode in ["free","billboard","df"]:
   scene.camera_rig.set_df_mode(mode=="df")
   scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
   await go_level(z)
   for enabled in [false,true]:
    scene.world.set_mesh_batching_enabled(enabled)
    await settle()
    for i in 60: await process_frame
    var label=mode+("_batched" if enabled else "_original")
    await capture(label,240)
    print("BATCH_STATS ",z," ",label," ",JSON.stringify(scene.world.mesh_batch_stats()))
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output+"-"+str(z)+"-"+label+".png")
 # Moving camera measures whether batching adds rebuild overhead to interaction.
 scene.camera_rig.set_df_mode(false)
 scene._sprite_presentation.set_style("billboard")
 await go_level(128)
 for enabled in [false,true]:
  scene.world.set_mesh_batching_enabled(enabled)
  await settle()
  # Inherited profiler includes an equal scripted pan on both paths.
  await sample("moving_"+("batched" if enabled else "original"),false,true)
 var f=FileAccess.open(output+"-moving.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(results,"  "))
 print("MESH_BATCH_PROFILE_LIVE_PASS")
 quit()
