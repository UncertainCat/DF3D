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
	if not check(await settle(service,func():return not created_order.is_empty() and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.rows_available and owner.orders.row_ticket==0),"Order creation was not confirmed; no retry"):quit(1);return
	check(created_order.name==expected.caption and created_order.id==int(expected.native_id)+1,"Created order receipt differs")
	check(not owner.order_picker.visible and owner.orders.snapshot.order_ids.has(created_order.id),"Created order absent from refreshed workshop")
	var displayed: Array=owner.orders.rows.values()
	var found:=false
	for row in displayed:
		if row.id==created_order.id:
			found=row.name==expected.caption and row.remaining==10 and row.total==10 and row.native_state.phase==C.WorkOrderPhase.Ready
	check(found,"New order missing from rendered native row data")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-created-live.png")
	click(Vector2(775,190))
	check(owner.panel.orders.editing and owner.panel.orders.quantity_order==created_order.id,"Order quantity field did not focus")
	number_key(KEY_1,49);number_key(KEY_2,50)
	if not check(await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.ticket==0),"Order quantity was not confirmed; no retry"):quit(1);return
	var edited: Dictionary={}
	for row in owner.orders.rows.values():
		if row.id==created_order.id:edited=row
	check(edited.get("remaining",-1)==12 and edited.get("total",-1)==12,"Order quantity differs from native")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-quantity-live.png")
	number_key(KEY_ENTER)
	check(not owner.panel.orders.editing,"Enter did not release order quantity focus")
	click(Vector2(816,190))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Conditions panel did not load"):quit(1);return
	check(owner.conditions_view.visible,"Conditions panel remained hidden")
	var suggestions: Array=owner.conditions.snapshot.get("suggested_conditions",[])
	check(suggestions.size()==expected.suggestions.size(),"Conditions suggestion count differs")
	for index in mini(suggestions.size(),expected.suggestions.size()):
		for key in ["item_caption","compare","threshold","item_type","item_subtype","mat_type","mat_index"]:
			check(suggestions[index].get(key)!=null and suggestions[index][key]==expected.suggestions[index][key],"Native Conditions field differs: "+str(key))
	await process_frame;await RenderingServer.frame_post_draw
	for _frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var conditions_image:=root.get_texture().get_image()
	conditions_image.save_png(directory+"/workshop-order-conditions-live.png")
	check(conditions_image.get_pixel(864,124).r>0.5,"Clock icon missing from rendered Conditions")
	for frequency in [1,2,3,4,0]:
		click(Vector2(880,142))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Frequency change did not complete"):quit(1);return
		check(owner.conditions.snapshot.frequency==frequency,"Clock frequency differs from native")
		for key in ["remaining","total","active","validated","finished_year","finished_tick"]:
			check(owner.conditions.snapshot[key]==edited[key],"Frequency changed unrelated order field: "+key)
	click(Vector2(768,586))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Suggested condition add was not confirmed; no retry"):quit(1);return
	check(owner.conditions.snapshot.frequency==1 and owner.conditions.snapshot.conditions.size()==1,"Suggested add did not match native count/frequency")
	if owner.conditions.snapshot.conditions.size()==1:
		for key in ["item_caption","compare","threshold","item_type","item_subtype","mat_type","mat_index"]:
			check(owner.conditions.snapshot.conditions[0][key]==expected.added_condition[key],"Added condition differs from native: "+key)
	check(not owner.conditions.snapshot.suggested_conditions[0].editable,"Duplicate native suggestion remains available")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-condition-added-live.png")
	for step in expected.condition_steps:
		click(Vector2(step.x,178))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Condition amount/comparison edit was not confirmed; no retry"):quit(1);return
		var condition: Dictionary=owner.conditions.snapshot.conditions[0]
		check(condition.compare==int(step.compare) and condition.threshold==int(step.threshold),"Condition amount/comparison differs from native")
		for key in ["item_caption","item_type","item_subtype","mat_type","mat_index"]:
			check(condition[key]==expected.added_condition[key],"Condition amount edit changed filter: "+key)
	click(Vector2(640,178))
	check(owner.conditions_view.editing_index==0 and owner.conditions_view.number_draft.is_empty(),"Condition number field did not focus with an empty draft")
	number_key(KEY_1,49);number_key(KEY_2,50)
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Condition number edit was not confirmed; no retry"):quit(1);return
	check(owner.conditions.snapshot.conditions[0].threshold==int(expected.condition_number) and owner.conditions_view.number_draft=="12","Condition number differs from native or dropped input")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-condition-number-live.png")
	number_key(KEY_ENTER)
	check(owner.conditions_view.editing_index==-1 and owner.conditions_view.visible,"Enter did not release condition number focus")
	click(Vector2(896,178))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Condition removal was not confirmed; no retry"):quit(1);return
	check(owner.conditions.snapshot.conditions.is_empty() and owner.conditions.snapshot.frequency==1,"Condition removal differs from native")
	check(owner.conditions.snapshot.suggested_conditions[0].editable,"Removed condition did not restore native suggestion availability")
	for key in ["remaining","total","active","validated","finished_year","finished_tick"]:
		check(owner.conditions.snapshot[key]==edited[key],"Condition removal changed unrelated order field: "+key)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-condition-removed-live.png")
	number_key(KEY_ESCAPE)
	check(not owner.conditions_view.visible and owner.conditions.phase==owner.conditions.Phase.Closed,"Conditions did not retire on close")
	click(Vector2(872,190))
	if not check(await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.rows_available and owner.orders.row_ticket==0),"Order removal was not confirmed; no retry"):quit(1);return
	check(not owner.orders.snapshot.order_ids.has(created_order.id) and owner.orders.row_total==0 and owner.orders.rows.is_empty(),"Removed order retained in workshop list")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-removed-live.png")
	var file:=FileAccess.open(directory+"/workshop-order-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"created":created_order,"rows":displayed,"quantity":edited,"removed":created_order.id,"order_ids":owner.orders.snapshot.order_ids,"search_names":names,"query":owner.order_picker.query_text(),"header":owner.state.snapshot,"title":owner.panel.title,"contents_page":owner.panel.contents.page,"header_font":owner.panel.theme.default_font!=null}));file.close()
	owner.close_panel();owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)
