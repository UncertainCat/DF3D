extends "res://tests/workshop_wire_live.gd"
var created_order: Dictionary={}
func settle(service,ready: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01)
		if ready.call():return true
		await create_timer(0.01).timeout
	return false
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-order-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Order bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var bootstrap:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(bootstrap.get("status")==C.ManagementStatus.Ok and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Order bootstrap/assets failed"):quit(1);return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var owner=preload("res://scripts/workshop_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
	owner.order_choices.created.connect(func(receipt):created_order=receipt)
	owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_STILL")
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready),"Order sheet did not load"):quit(1);return
	await process_frame;click(Vector2(640,112))
	if not check(await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready),"Order tab did not load"):quit(1);return
	check(owner.orders.snapshot.manager_available,"Manager fixture missing")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-before-picker.png")
	service.completed.connect(func(_ticket,result):
		if result.get("action",-1) in [C.ManagementAction.WorkOrderCatalog,C.ManagementAction.WorkOrderCreate]:print("Order reply: ",JSON.stringify(result.get("work_order",{}))))
	await process_frame;click(Vector2(880,154))
	if not check(await settle(service,func():return owner.order_choices.phase==owner.order_choices.Phase.Ready),"Native order catalog did not reach picker; phase="+str(owner.order_choices.phase)+" visible="+str(owner.order_picker.visible)):quit(1);return
	check(owner.order_picker.visible and owner.order_choices.rows.size()==4,"Wrong forced-workshop picker")
	click(Vector2(600,94))
	for char in str(expected.query):number_key(KEY_A,char.unicode_at(0))
	if not check(await settle(service,func():return owner.order_choices.phase==owner.order_choices.Phase.Ready),"Order search did not complete"):quit(1);return
	var names: Array=[]
	for row in owner.order_choices.rows:names.append(row.name)
	check(names==expected.search_names and owner.order_picker.query_text()==str(expected.query).to_upper(),"Order search differs from native")
	number_key(KEY_ENTER)
	check(not owner.order_picker.search_focused and owner.order_picker.visible,"Enter did not release order search focus")
	check(owner.order_choices.rows[int(expected.choice)].name==expected.caption,"Recipe order changed")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-picker-live.png")
	click(Vector2(600,130))
	if not check(await settle(service,func():return not created_order.is_empty() and owner.orders.phase==owner.orders.Phase.Ready),"Order creation was not confirmed; no retry"):quit(1);return
	check(created_order.name==expected.caption and created_order.id==int(expected.native_id)+1,"Created order receipt differs")
	check(not owner.order_picker.visible and owner.orders.snapshot.order_ids.has(created_order.id),"Created order absent from refreshed workshop")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-created-live.png")
	var file:=FileAccess.open(directory+"/workshop-order-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"created":created_order,"order_ids":owner.orders.snapshot.order_ids,"search_names":names,"query":owner.order_picker.query_text(),"header":owner.state.snapshot,"title":owner.panel.title,"contents_page":owner.panel.contents.page,"header_font":owner.panel.theme.default_font!=null}));file.close()
	owner.close_panel();owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)
