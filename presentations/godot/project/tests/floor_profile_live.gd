extends "res://tests/frame_profile.gd"
# Paused, fixed-framing floor sweep; run only in an owned native lane.
var output := OS.get_environment("DF3D_FLOOR_PERF_OUT")
var offset := 0
var records: Array = []
func capture(label: String, frames: int) -> Dictionary:
 var w=scene.world
 var before: Dictionary=w.presentation_perf_stats()
 var elapsed: Array=[]
 var cpu: Array=[]
 var gpu: Array=[]
 var process: Array=[]
 var last=Time.get_ticks_usec()
 for i in frames:
  await process_frame
  var now=Time.get_ticks_usec()
  elapsed.append((now-last)/1000.0)
  last=now
  cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
 var totals: Dictionary=w.presentation_perf_stats()
 for key in totals:
  if typeof(totals[key]) in [TYPE_INT,TYPE_FLOAT]: totals[key]-=before.get(key,0)
 var r={"phase":label,"z":w.get_top_z(),"elevation":w.get_top_z()+offset,"frames":frames,"frame_ms":distribution(elapsed),"render_cpu_ms":distribution(cpu),"gpu_ms":distribution(gpu),"process_ms":distribution(process),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"totals":totals,"items":w.item_drawn_count(),"units":w.unit_count(),"window":w.get_window_depth()}
 records.append(r)
 var f=FileAccess.open(output+".json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"resolution":[1920,1080],"distance":60,"focus_xz":[72,72],"vsync":false,"paused":true,"phases":records},"  "))
 print("FLOOR_PERF ",label," elevation=",r.elevation," p50=",r.frame_ms.p50," p95=",r.frame_ms.p95," gpu=",r.gpu_ms.p50," render_cpu=",r.render_cpu_ms.p50," draws=",r.draw_calls)
 return r
func settle():
 var end=Time.get_ticks_msec()+15000
 for i in 12: await process_frame
 while not ready_scene() and Time.get_ticks_msec()<end: await process_frame
 for i in 12: await process_frame
func go_level(z: int):
 scene.world.set_top_z(z)
 scene.camera_rig.focus_on(Vector3(72,z+1,72),60)
 await settle()
func run():
 root.size=Vector2i(1920,1080)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 scene=load("res://scenes/main.tscn").instantiate()
 root.add_child(scene)
 var deadline=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(0.1).timeout
 if not scene._loader.entered: push_error("Floor profile load failed"); quit(1); return
 if not scene._session_state.get("paused",false): push_error("Expected paused fort"); quit(1); return
 offset=int(scene._session_state.get("fortress_summary",{}).get("elevation_offset",0))
 scene.camera_rig.set_df_mode(false)
 scene._sprite_presentation.set_style("billboard")
 for z in range(int(scene.world.map_size().y)-1,-1,-1):
  await go_level(z)
  await capture("sweep_billboard",48)
 var ranked=records.duplicate()
 ranked.sort_custom(func(a,b): return a.frame_ms.p50>b.frame_ms.p50)
 var targets: Array=[]
 for r in ranked:
  if targets.all(func(z):return absi(z-r.z)>2): targets.append(r.z)
  if targets.size()==4: break
 for z in targets:
  scene.camera_rig.set_df_mode(false)
  scene._sprite_presentation.set_style("billboard")
  await go_level(z)
  await capture("billboard",360)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output+"-z"+str(z)+".png")
  scene._sprite_presentation.set_style("classic")
  await settle()
  await capture("free_plain",360)
  scene.camera_rig.set_df_mode(true)
  await settle()
  await capture("df",360)
 print("FLOOR_PROFILE_PASS")
 quit()
