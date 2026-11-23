extends "res://tests/workshop_order_wire_live.gd"
func resize_view(dimensions: Vector2i) -> void:
 root.size=dimensions
 for _frame in 3:await process_frame
 await RenderingServer.frame_post_draw
func order_point(owner,id: int,button: int) -> Vector2:
 for index in owner.global_orders.rows:
  if int(owner.global_orders.rows[index].id)==id:
   return owner.global_orders_view.position+Vector2(owner.global_orders_view.button_positions()[button]+16,owner.global_orders_view.list_top()+(index-owner.global_orders.first)*36+18)
 return Vector2(-1,-1)
func run() -> void:
 directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
 var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-order-navigation-expected.json"))
 var scene
 var service
 var host
 var owner
 var public_scene: bool=OS.get_environment("DF3D_WORK_ORDER_PUBLIC_SCENE")=="1"
 if public_scene:
  Engine.max_fps=30;OS.set_environment("DF3D_FIXTURE","")
  var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
  root.size=Vector2i(1200,800)
  scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
  var deadline:=Time.get_ticks_msec()+60000
  while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
  if not check(scene._loader.entered,"Work orders main scene did not enter fortress"):quit(1);return
  service=scene._ui.actions;service.set_process(false);host=scene._ui.host;owner=scene._ui.controller("workshop")
  var button: Rect2=scene._fortress_hud.launcher_rect("Work orders")
  if not check(button.has_area(),"Work orders HUD launcher missing"):quit(1);return
  click(button.get_center())
 else:
  world=Df3dWorld.new();root.add_child(world)
  if not check(world.attach(),"Navigation bridge attach failed"):quit(1);return
  var deadline:=Time.get_ticks_msec()+5000
  while Time.get_ticks_msec()<deadline:
   world.poll()
   if world.poll_management().get("transport_alive",false):break
   await create_timer(0.01).timeout
  var bootstrap:=await request("construction",{"action":C.ManagementAction.Catalog})
  if not check(bootstrap.get("status")==C.ManagementStatus.Ok and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Navigation bootstrap failed"):quit(1);return
  var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
  await resize_view(Vector2i(1200,800))
  service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
  host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
  owner=preload("res://scripts/workshop_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
  owner.open_global_orders()
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready),"Standalone order list did not load"):quit(1);return
 for _frame in 3:await process_frame
 check(host.active==owner and owner.global_orders_view.visible and not owner.panel.visible,"Standalone owner lost focus or showed a workshop")
 click(order_point(owner,int(plan.id),5))
 if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Conditions navigation failed"):quit(1);return
 check(not owner.global_orders_view.visible and owner.conditions_view.visible,"Conditions did not replace list")
 await resize_view(Vector2i(1600,900))
 check(owner.conditions_view.size.x==1344 and host.active==owner,"Conditions resize lost layout or ownership")
 if plan.get("edits",false):
  click(Vector2(1072,150))
  if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.ticket==0),"Resized condition amount was not confirmed"):quit(1);return
  check(owner.conditions.snapshot.conditions[0].threshold==int(plan.threshold)+1,"Resized condition amount differs")
 if plan.get("filters",false):
  click(Vector2(1200,150))
  if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.filter_kind==1),"Resized material filter did not open"):quit(1);return
  for character in "IRON":number_key(KEY_A,character.unicode_at(0))
  if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.ticket==0 and owner.conditions.filter_query=="IRON"),"Material search failed"):quit(1);return
  check(not owner.conditions.filter_rows.is_empty(),"Material search found no rows")
  await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(directory+"/work-order-navigation-material-wide.png")
  click(Vector2(400,186))
  if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.filter_kind==-1),"Material selection did not return to Conditions"):quit(1);return
  check(owner.conditions.snapshot.conditions[0].mat_type==int(plan.material_type) and owner.conditions.snapshot.conditions[0].mat_index==int(plan.material_index),"Material selection differs")
  click(Vector2(1344,114))
  if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.filter_kind==3),"Resized dependency picker did not open"):quit(1);return
  check(not owner.conditions.filter_rows.is_empty() and owner.conditions.filter_rows[0].id==int(plan.dependency),"Dependency candidate order differs")
  click(Vector2(400,186))
  if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.filter_kind==-1),"Dependency selection did not return to Conditions"):quit(1);return
  var linked:=false
  for condition in owner.conditions.snapshot.conditions:
   if condition.kind==1 and condition.target_order==int(plan.dependency):linked=true
  check(linked,"Dependency absent after confirmation")
 root.get_texture().get_image().save_png(directory+"/work-order-navigation-conditions-wide.png")
 number_key(KEY_ESCAPE)
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders_view.visible),"Conditions Back did not restore list"):quit(1);return
 check(not owner.conditions_view.visible and host.active==owner,"Conditions Back retained child or lost input")
 if plan.get("edits",false):
  var y: float=order_point(owner,int(plan.id),1).y
  click(Vector2(560,y))
  if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders.ticket==0),"Resized quantity was not confirmed"):quit(1);return
  var row: Dictionary={}
  for candidate in owner.global_orders.rows.values():
   if int(candidate.id)==int(plan.id):row=candidate
  check(row.get("remaining",-1)==int(plan.remaining)+1 and row.get("total",-1)==int(plan.remaining)+1,"Resized quantity differs")
  if plan.get("boundary",false):
   for sample in [[2,9999],[1,10000]]:
    click(order_point(owner,int(plan.id),int(sample[0])))
    if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders.ticket==0),"Boundary arrow did not settle"):quit(1);return
    row=owner.global_orders.find_order(int(plan.id))
    check(row.get("remaining",-1)==int(sample[1]) and row.get("total",-1)==int(sample[1]),"Boundary arrow quantity differs")
  click(Vector2(1088,y))
  if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders.ticket==0),"Resized workshop limit was not confirmed"):quit(1);return
  for candidate in owner.global_orders.rows.values():
   if int(candidate.id)==int(plan.id):row=candidate
  check(row.get("max_workshops",-1)==int(plan.limit)+1,"Resized workshop limit differs")
  if plan.get("text_edit",false):
   click(Vector2(112,y))
   check(owner.global_orders_view.editing_id==int(plan.id) and not owner.global_orders_view.editing_limit and owner.global_orders_view.draft.is_empty(),"Order text did not focus empty quantity entry")
   number_key(KEY_1,49);number_key(KEY_2,50)
   if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders.ticket==0),"Text quantity edit was not confirmed"):quit(1);return
   row=owner.global_orders.find_order(int(plan.id))
   check(row.get("remaining",-1)==12 and row.get("total",-1)==12,"Text quantity effect differs")
   number_key(KEY_ENTER)
   check(owner.global_orders_view.editing_id==-1,"Enter retained text quantity focus")
 click(order_point(owner,int(plan.id),6))
 if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Details navigation failed"):quit(1);return
 await resize_view(Vector2i(912,552))
 check(owner.details_view.size.x==688 and host.active==owner,"Details resize lost layout or ownership")
 root.get_texture().get_image().save_png(directory+"/work-order-navigation-details-small.png")
 number_key(KEY_ESCAPE)
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders_view.visible),"Details Back did not restore list"):quit(1);return
 number_key(KEY_ESCAPE);await process_frame;await process_frame
 check(host.active==null and not owner.global_orders_view.visible,"Closing standalone list retained input ownership")
 if public_scene:click(scene._fortress_hud.launcher_rect("Work orders").get_center())
 else:owner.open_global_orders()
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready),"Standalone list failed to reopen"):quit(1);return
 host.close_active();await process_frame
 check(host.active==null and owner.global_orders.phase==owner.global_orders.Phase.Closed,"Host close retained order state")
 var file:=FileAccess.open(directory+"/work-order-navigation-wire-result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"success":not failed}));file.close()
 if public_scene:scene.queue_free();await process_frame
 else:
  owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
  world.detach_live();world.queue_free();await process_frame
 quit(1 if failed else 0)
