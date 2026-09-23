extends "res://tests/mesh_batch_profile_live.gd"
# Running simulation smoke, sequential comparisons are not identical DF frames.
func set_paused(value: bool) -> bool:
 scene.world.send_set_pause(value)
 var deadline=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  await create_timer(0.1).timeout
  if scene.world.poll_session().get("paused",not value)==value: return true
 return false
func run():
 root.size=Vector2i(1920,1080)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 scene=load("res://scenes/main.tscn").instantiate()
 root.add_child(scene)
 var deadline=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(0.1).timeout
 if not scene._loader.entered: push_error("Running batch profile load failed"); quit(1); return
 scene.world.set_mesh_batching_enabled(true)
 var phases=[{"name":"running_uncached","mode":"billboard","cache":false},{"name":"running_cached","mode":"billboard","cache":true}]
 if OS.get_environment("DF3D_PERF_FINAL_MODES")=="1":
  phases=[]
 for mode in ["free","df","billboard"]: phases.append({"name":"running_"+mode,"mode":mode,"cache":true})
 if OS.get_environment("DF3D_PERF_SPATIAL_SWEEP")=="1":
  phases=[]
  for mode in ["free","df","billboard"]:
   for cell in [0,16,32]: phases.append({"name":"running_"+mode+"_cell"+str(cell),"mode":mode,"cache":true,"cell":cell})
 for phase in phases:
  if phase.has("cell"): scene.configure_sprite_batches(phase.cell!=0,maxi(16,phase.cell),1)
  scene.camera_rig.set_df_mode(phase.mode=="df")
  scene._sprite_presentation.set_style("billboard" if phase.mode=="billboard" else "classic")
  await go_level(128)
  scene._instance_uploads.enabled=phase.cache
  await settle()
  if not await set_paused(false): push_error("Cannot resume"); quit(1); return
  var before: Dictionary=scene._instance_uploads.stats()
  await sample(phase.name,phase.mode=="df",true,180,15)
  var after: Dictionary=scene._instance_uploads.stats()
  for key in after: after[key]-=before.get(key,0)
  results.back()["instance_uploads"]=after
  results.back()["sprite_batches"]=scene.sprite_batch_stats()
  results.back()["auxiliary_caches"]=scene.world.auxiliary_cache_stats()
  if not await set_paused(true): push_error("Cannot restore pause"); quit(1); return
  await settle()
  print("BATCH_STATS ",JSON.stringify(scene.world.mesh_batch_stats()))
  if results.back().tick_end<=results.back().tick_start:
   push_error("Simulation did not advance"); quit(1); return
 var f=FileAccess.open(output+".json",FileAccess.WRITE)
 f.store_string(JSON.stringify(results,"  "))
 if not scene.world.layout_matches_reference(): push_error("Tile layout differs from reference"); quit(1); return
 print("FLOOR_PROFILE_PASS")
 quit()
