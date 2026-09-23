extends "res://tests/mesh_batch_motion_live.gd"
func run():
 root.size=Vector2i(1920,1080)
 scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
 var deadline=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
 if not scene._loader.entered: push_error("Inspector load failed");quit(1);return
 if not await set_paused(true): quit(1);return
 await go_level(128);await settle()
 var world=scene.world
 world.demand_resident_info(1)
 deadline=Time.get_ticks_msec()+30000
 while not world.resident_info_state().get("complete",false) and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
 var targets={}
 for id in world.unit_ids():
  var row: Dictionary=world.inspect_entity(1,id)
  if not row.is_empty() and row.get("summary_available",false): targets[1]=row;break
 # Find local map pieces once for the capture, not a runtime polling pattern.
 for y in range(30,160):
  for x in range(30,160):
   for row in world.inspect_tile(Vector3i(x,y,128)):
    if int(row.kind) in [2,3] and not targets.has(int(row.kind)): targets[int(row.kind)]=row
   if targets.has(2) and targets.has(3): break
  if targets.has(2) and targets.has(3): break
 assert(targets.size()==3,"Need unit, item and building examples")
 var evidence={}
 for kind in [1,2,3]:
  var row: Dictionary=targets[kind]
  await go_level(row.tile.z)
  scene.camera_rig.focus_on(Vector3(row.tile.x+.5,row.tile.z,row.tile.y+.5),12)
  scene._interaction._preferred_unit=row.id if kind==1 else -1
  scene._interaction._preferred_item=row.id if kind==2 else -1
  scene._interaction._preferred_building=row.id if kind==3 else -1
  scene._interaction._select_items(row.tile)
  for i in 30: await process_frame
  assert(scene._ui.controller("inspector").panel.visible and scene._ui.controller("inspector").selected.id==row.id)
  evidence[str(kind)]=scene._ui.controller("inspector").selected
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output+"-"+str(kind)+".png")
  scene._ui.controller("inspector").close_panel()
 var file=FileAccess.open(output+"-data.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "))
 print("CONTEXT_INSPECT_LIVE_PASS");quit()
