# Protected acceptance: tools/smoke/terrain_hover_acceptance.ps1 owns DF and the verified save.
extends SceneTree
var scene
var directory:String
var failed:=false
func _initialize():call_deferred("run")
func check(ok:bool,message:String)->bool:
 if not ok:failed=true;push_error(message)
 return ok
func wait_for(predicate:Callable)->bool:
 var until:=Time.get_ticks_msec()+20000
 while Time.get_ticks_msec()<until:
  if predicate.call():return true
  await process_frame
 return false
func pointer(position:Vector2)->void:
 root.warp_mouse(position)
 var motion:=InputEventMouseMotion.new();motion.position=position;motion.global_position=position
 root.push_input(motion,true)
 await process_frame
func run():
 directory=OS.get_environment("DF3D_HOVER_ACCEPTANCE")
 if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
 var preferences=preload("res://scripts/presentation_settings.gd")
 preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
 OS.set_environment("DF3D_FIXTURE","")
 root.size=Vector2i(1200,800)
 scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
 var until:=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<until:await create_timer(0.05).timeout
 if check(scene._loader.entered,"main scene failed to load"):await exercise()
 var f:=FileAccess.open(directory+"/viewer-result.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"success":not failed}));f.close()
 scene.queue_free();await process_frame
 print("TERRAIN_HOVER_LIVE_PASS" if not failed else "TERRAIN_HOVER_LIVE_FAIL")
 quit(1 if failed else 0)
func exercise():
 var hover=scene._ui.get_node("TileHover")
 var world=scene.world
 var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/hover/collector.json"))
 var count:=0
 for row in evidence.captures[0].cases:
  var p:=Vector3i(int(row.pos.x),int(row.pos.y),int(row.pos.z))
  world.set_top_z(p.z)
  scene.camera_rig.focus_on(Vector3(p.x+0.5,p.z+1.0,p.y+0.5),30)
  for i in 20:await process_frame
  var high:=1.0 if row.kind in ["StoneWallSmoothRD","StoneFortification"] else float(world.floor_height())
  var point:=Vector3(p.x+0.5,p.z+high,p.y+0.5)
  var position:Vector2=hover.camera.unproject_position(point)
  if not check(world.pick_tile(hover.camera.project_ray_origin(position),hover.camera.project_ray_normal(position),world.get_top_z())==p,"pointer picking mismatch "+row.kind):return
  await pointer(position)
  if not check(await wait_for(func():return hover.panel.visible and hover.target==p and entries_match(hover.panel.entries,row.expected)),"hover did not receive native text "+row.kind+" got "+str(hover.panel.entries)+" target "+str(hover.target)):return
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(directory+"/"+row.kind+".png")
  count+=1
  # A control blocks map hover and clears the currently displayed response.
  await pointer(scene._fortress_hud.navigation.Dig.get_global_transform_with_canvas()*Vector2(8,8))
  if not check(await wait_for(func():return not hover.panel.visible),"HUD hover retained map prose"):return
  await pointer(position)
  if not check(await wait_for(func():return hover.panel.visible),"map hover failed to recover"):return
 scene._fortress_hud.toggle_settings()
 await process_frame;await process_frame
 check(not hover.panel.visible,"settings retained map prose")
 scene._fortress_hud.close_menus()
 var previous_z:int=world.get_top_z()
 world.set_top_z(previous_z-1)
 await process_frame;await process_frame
 check(hover.target.z!=previous_z,"elevation change retained previous target")
 # Real service invalidation: no old text survives disconnect/generation changes.
 scene._ui.actions._invalidate()
 check(not hover.panel.visible and hover.ticket==0,"session invalidation retained prose")
 check(count==evidence.captures[0].cases.size(),"missing native cases")

func entries_match(actual:Array,expected:Array)->bool:
 if actual.size()!=expected.size():return false
 for i in actual.size():
  for key in ["kind","text","foreground","background","bright"]:
   if actual[i].get(key)!=expected[i].get(key):return false
 return true
