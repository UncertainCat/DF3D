extends "res://tests/workshop_order_wire_live.gd"
func check_search(service,state,plan: Dictionary) -> bool:
 if not plan.has("search"):return true
 click(Vector2(200,142))
 for character in str(plan.search.query):number_key(KEY_A,character.unicode_at(0))
 if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.ticket==0),"Dye search did not finish"):return false
 for stage in ["filtered","cleared"]:
  if stage=="cleared":
   for _character in str(plan.search.query):number_key(KEY_BACKSPACE)
   if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.ticket==0),"Dye clear did not finish"):return false
  var actual: Array=[]
  var expected: Array=[]
  for row in state.rows:actual.append(int(row.id))
  for value in plan.search[stage]:expected.append(int(value))
  if not check(actual==expected,"Dye "+stage+" choice order differs from native"):return false
 number_key(KEY_ENTER)
 return true
func capture(flow: String,stage: String) -> void:
 for _frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/work-order-dye-"+flow+"-"+stage+"-live.png")
func run() -> void:
 directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
 var plans: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-order-dye-expected.json"))
 world=Df3dWorld.new();root.add_child(world)
 if not check(world.attach(),"Dye bridge attach failed"):quit(1);return
 var deadline:=Time.get_ticks_msec()+5000
 while Time.get_ticks_msec()<deadline:
  world.poll()
  if world.poll_management().get("transport_alive",false):break
  await create_timer(0.01).timeout
 var bootstrap:=await request("construction",{"action":C.ManagementAction.Catalog})
 if not check(bootstrap.get("status")==C.ManagementStatus.Ok and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Dye bootstrap/assets failed"):quit(1);return
 var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
 root.size=Vector2i(1200,800)
 for _frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
 var state=preload("res://scripts/work_order_details_state.gd").new();state.configure(service)
 var view=preload("res://scripts/work_order_details_view.gd").new();root.add_child(view);view.configure_details(world,state)
 view.cancelled.connect(state.close);state.applied.connect(state.close)
 var observed: Array=[]
 for plan in plans:
  view.open(-2,int(plan.id));view.layout(Vector2(1200,800))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready),"Dye Details failed to open"):quit(1);return
  await process_frame;click(Vector2(200,106+int(plan.option)*36))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.snapshot.selected_option==int(plan.option)),"Dye targets failed to load"):quit(1);return
  check(view.selected_kind()==int(plan.kind) and not state.rows.is_empty(),"Wrong dye chooser")
  check(state.snapshot.get("setting_heading","")==("Choose dye color" if int(plan.kind)==4 else "Setting mix color"),"Dye heading differs from native")
  observed.append({"flow":plan.flow,"heading":state.snapshot.get("setting_heading",""),"targets":state.rows.duplicate(true)})
  await capture(plan.flow,"targets")
  if int(plan.target)<0 and not await check_search(service,state,plan):quit(1);return
  state.seek(int(plan.root_row))
  await process_frame
  click(Vector2(200,178+(int(plan.root_row)-state.first)*36))
  if int(plan.target)>=0:
   if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.snapshot.get("dye_target",-1)==int(plan.target)),"Dye ingredient navigation failed"):quit(1);return
   check(not state.rows.is_empty() and not state.rows[0].get("opens_menu",true) and not state.rows[0].has("swatch"),"Wrong dye ingredient row")
   observed[-1]["ingredients"]=state.rows.duplicate(true)
   await capture(plan.flow,"reagents")
   if not await check_search(service,state,plan):quit(1);return
   click(Vector2(200,178))
  if not check(await settle(service,func():return state.phase==state.Phase.Closed),"Dye selection was not confirmed; no replay"):quit(1);return
 var file:=FileAccess.open(directory+"/work-order-dye-wire-result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"success":not failed,"flows":observed}));file.close()
 state.dispose();view.queue_free();service.queue_free();await process_frame
 world.detach_live();world.queue_free();await process_frame
 quit(1 if failed else 0)
