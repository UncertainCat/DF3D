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
 var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
 var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
 var owner=preload("res://scripts/workshop_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
 owner.open_global_orders()
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready),"Standalone order list did not load"):quit(1);return
 for _frame in 3:await process_frame
 check(host.active==owner and owner.global_orders_view.visible and not owner.panel.visible,"Standalone owner lost focus or showed a workshop")
 click(order_point(owner,int(plan.id),5))
 if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Conditions navigation failed"):quit(1);return
 check(not owner.global_orders_view.visible and owner.conditions_view.visible,"Conditions did not replace list")
 await resize_view(Vector2i(1600,900))
 check(owner.conditions_view.size.x==1344 and host.active==owner,"Conditions resize lost layout or ownership")
 root.get_texture().get_image().save_png(directory+"/work-order-navigation-conditions-wide.png")
 number_key(KEY_ESCAPE)
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders_view.visible),"Conditions Back did not restore list"):quit(1);return
 check(not owner.conditions_view.visible and host.active==owner,"Conditions Back retained child or lost input")
 click(order_point(owner,int(plan.id),6))
 if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Details navigation failed"):quit(1);return
 await resize_view(Vector2i(912,552))
 check(owner.details_view.size.x==688 and host.active==owner,"Details resize lost layout or ownership")
 root.get_texture().get_image().save_png(directory+"/work-order-navigation-details-small.png")
 number_key(KEY_ESCAPE)
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready and owner.global_orders_view.visible),"Details Back did not restore list"):quit(1);return
 number_key(KEY_ESCAPE);await process_frame;await process_frame
 check(host.active==null and not owner.global_orders_view.visible,"Closing standalone list retained input ownership")
 owner.open_global_orders()
 if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready),"Standalone list failed to reopen"):quit(1);return
 host.close_active();await process_frame
 check(host.active==null and owner.global_orders.phase==owner.global_orders.Phase.Closed,"Host close retained order state")
 var file:=FileAccess.open(directory+"/work-order-navigation-wire-result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"success":not failed}));file.close()
 owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
 world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
