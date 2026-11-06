extends "res://tests/workshop_wire_live.gd"
var created_order: Dictionary={}
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true);super.click(point)
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
		check(condition.satisfied==step.satisfied,"Condition satisfaction differs from native")
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
	for step in expected.filter_steps:
		click(Vector2(768+int(step.kind)*32,178))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Filter picker did not load"):quit(1);return
		check(owner.conditions.filter_kind==int(step.kind),"Wrong filter picker")
		for char in str(step.query):number_key(KEY_A,char.unicode_at(0))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Filter search did not finish"):quit(1);return
		var ids: Array=[]
		for choice in owner.conditions.filter_rows:
			ids.append(choice.id);check(str(step.text).contains(choice.name),"Filter display caption differs from native: "+choice.name)
		var native_ids: Array=[]
		for id in step.ids:native_ids.append(int(id))
		check(ids==native_ids,"Filter search order differs from native: "+str(ids)+" / "+str(native_ids))
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/workshop-order-filter-search-"+str(int(step.kind))+"-live.png")
		click(Vector2(400,214))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Filter selection was not confirmed; no retry"):quit(1);return
		var condition: Dictionary=owner.conditions.snapshot.conditions[0]
		for key in ["item_type","item_subtype","mat_type","mat_index"]:check(condition[key]==int(step[key]),"Filter selection differs from native: "+key)
		check(owner.conditions.filter_kind==(2 if int(step.kind)==2 else -1),"Filter selection close behavior differs")
		if int(step.kind)==2:check(condition.traits.has(str(ids[0])),"Selected trait indicator absent")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/workshop-order-filter-applied-"+str(int(step.kind))+"-live.png")
		if int(step.kind)==2:
			number_key(KEY_ESCAPE)
			if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready),"Global list did not open after Conditions Back"):quit(1);return
			number_key(KEY_ESCAPE)
			if not check(await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Workshop list did not refresh after global Back"):quit(1);return
			click(Vector2(816,190))
			if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Conditions did not reopen after trait picker"):quit(1);return
	click(Vector2(896,178))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Condition removal was not confirmed; no retry"):quit(1);return
	check(owner.conditions.snapshot.conditions.is_empty() and owner.conditions.snapshot.frequency==1,"Condition removal differs from native")
	check(owner.conditions.snapshot.suggested_conditions[0].editable,"Removed condition did not restore native suggestion availability")
	for key in ["remaining","total","active","validated","finished_year","finished_tick"]:
		check(owner.conditions.snapshot[key]==edited[key],"Condition removal changed unrelated order field: "+key)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-condition-removed-live.png")
	click(Vector2(912,142))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Manual condition was not confirmed; no retry"):quit(1);return
	if not check(owner.conditions.snapshot.conditions.size()==1,"Manual condition missing"):quit(1);return
	for key in expected.manual_condition:
		check(owner.conditions.snapshot.conditions[0][key]==int(expected.manual_condition[key]),"Manual condition differs from native: "+key)
	check(owner.conditions.snapshot.conditions[0].satisfied==expected.manual_satisfied,"Manual condition satisfaction differs from native")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-condition-manual-live.png")
	click(Vector2(896,178))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Manual condition removal was not confirmed"):quit(1);return
	check(owner.conditions.snapshot.conditions.is_empty(),"Manual condition retained after removal")
	for index in 14:
		click(Vector2(912,142))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Overflow condition creation failed"):quit(1);return
	check(owner.conditions_view.condition_scroll.visible,"Condition scrollbar missing")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-conditions-overflow-live.png")
	var wheel:=InputEventMouseButton.new();wheel.position=Vector2(400,240);wheel.global_position=wheel.position;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
	root.push_input(wheel,true)
	wheel.pressed=false;root.push_input(wheel,true)
	check(owner.conditions_view.condition_first==int(expected.condition_scroll.wheel),"Condition wheel differs from native: "+str(owner.conditions_view.condition_first)+" / "+str(expected.condition_scroll.wheel))
	click(Vector2(912,550))
	check(owner.conditions_view.condition_first==int(expected.condition_scroll.first),"Condition arrow differs from native")
	var selected: int=owner.conditions_view.condition_first
	click(Vector2(656,178))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Scrolled condition edit failed"):quit(1);return
	for index in owner.conditions.snapshot.conditions.size():check(owner.conditions.snapshot.conditions[index].threshold==(1 if index==selected else 0),"Scrolled edit targeted wrong condition")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-conditions-scrolled-live.png")
	while not owner.conditions.snapshot.conditions.is_empty():
		click(Vector2(880 if owner.conditions_view.condition_scroll.visible else 896,178))
		if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Scrolled condition removal failed"):quit(1);return
	check(owner.conditions_view.condition_first==0 and not owner.conditions_view.condition_scroll.visible,"Condition scroll did not reset after removal")
	click(Vector2(944,142))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Dependency picker did not load"):quit(1);return
	check(owner.conditions.filter_kind==3,"Dependency picker not open")
	check(owner.conditions.filter_total==expected.dependency_candidates.size(),"Dependency candidate count differs")
	root.size=Vector2i(1200,900);await process_frame;await process_frame
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.conditions.filter_rows.size()>=owner.conditions_view.page_rows),"Tall dependency picker did not fill across transport pages"):quit(1);return
	for index in owner.conditions.filter_rows.size():
		check(owner.conditions.filter_rows[index].id==int(expected.dependency_candidates[index]),"Dependency candidate order differs")
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-dependency-picker-live.png")
	click(Vector2(400,202))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Dependency addition was not confirmed"):quit(1);return
	if not check(owner.conditions.snapshot.conditions.size()==1,"Dependency missing"):quit(1);return
	var dependency: Dictionary=owner.conditions.snapshot.conditions[0]
	check(dependency.kind==1 and dependency.target_order==int(expected.dependency.target) and dependency.dependency==int(expected.dependency.condition),"Dependency differs from native")
	check(owner.conditions.snapshot.frequency==int(expected.dependency.frequency),"Dependency addition changed frequency")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-dependency-added-live.png")
	click(Vector2(640,178))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Dependency toggle was not confirmed"):quit(1);return
	check(owner.conditions.snapshot.conditions[0].dependency==int(expected.dependency.toggled),"Dependency toggle differs from native")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-dependency-toggled-live.png")
	click(Vector2(896,178))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready and owner.orders.phase==owner.orders.Phase.Ready and owner.orders.row_ticket==0),"Dependency removal was not confirmed"):quit(1);return
	check(owner.conditions.snapshot.conditions.is_empty(),"Dependency retained after removal")
	number_key(KEY_ESCAPE)
	check(not owner.conditions_view.visible and owner.conditions.phase==owner.conditions.Phase.Closed,"Conditions did not retire on close")
	if not check(await settle(service,func():return owner.global_orders.phase==owner.global_orders.Phase.Ready),"Global orders did not open"):quit(1);return
	var global=owner.global_orders
	check(owner.global_orders_view.visible and global.total==expected.global_order_ids.size(),"Global list count/navigation differs from native")
	global.seek(global.total-1,owner.global_orders_view.page_rows)
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0 and not global.find_order(created_order.id).is_empty()),"Global last page did not load"):quit(1);return
	var global_row: Dictionary=global.find_order(created_order.id)
	var global_y: float=142+(global_row.position-global.first)*36
	click(Vector2(424,global_y))
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0),"Global quantity edit failed"):quit(1);return
	check(global.find_order(created_order.id).remaining==edited.remaining+1,"Global quantity effect missing")
	click(Vector2(488,global_y))
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0),"Global priority move failed"):quit(1);return
	global_row=global.find_order(created_order.id)
	check(global_row.position==global.total-2,"Global priority effect missing")
	global_y=142+(global_row.position-global.first)*36
	click(Vector2(552,global_y))
	if not check(await settle(service,func():return owner.conditions.phase==owner.conditions.Phase.Ready),"Global Conditions did not open"):quit(1);return
	check(owner.conditions.building_id==-2 and owner.conditions.snapshot.id==created_order.id,"Global Conditions targeted another order")
	number_key(KEY_ESCAPE)
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0),"Conditions Back did not refresh global orders"):quit(1);return
	global_row=global.find_order(created_order.id);global_y=142+(global_row.position-global.first)*36
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/global-work-orders-live.png")
	click(Vector2(584,global_y))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Details did not open through global row"):quit(1);return
	check(owner.details.snapshot.id==created_order.id and owner.details.snapshot.options.size()==expected.details.options.size(),"Details target/options differ")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-details-live.png")
	click(Vector2(200,106))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.snapshot.get("selected_option",-1)==0),"Details material choices did not open"):quit(1);return
	check(owner.details.rows.size()==expected.details.choices[0].rows.size(),"Details material choice count differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-details-material-live.png")
	click(Vector2(200,142))
	for character in expected.details.choices[0].search:number_key(KEY_A,character.unicode_at(0))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.ticket==0),"Details search did not finish"):quit(1);return
	if not check(owner.details.rows.size()==expected.details.choices[0].filtered.size() and owner.details.rows.size()==1 and owner.details.rows[0].id==1,"Native Details filtered identity differs"):quit(1);return
	number_key(KEY_ENTER)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-details-search-live.png")
	click(Vector2(200,178))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Details material selection did not close and refresh"):quit(1);return
	global_row=global.find_order(created_order.id);global_y=142+(global_row.position-global.first)*36
	click(Vector2(584,global_y))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Details did not reopen after material selection"):quit(1);return
	click(Vector2(200,142))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.snapshot.get("selected_option",-1)==1),"Details plant choices did not open"):quit(1);return
	click(Vector2(200,142))
	for character in expected.details.choices[1].search:number_key(KEY_A,character.unicode_at(0))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.ticket==0),"Details plant search did not finish"):quit(1);return
	check(owner.details.rows.size()==expected.details.choices[1].filtered.size(),"Native plant search count differs")
	number_key(KEY_ENTER)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-details-plant-live.png")
	click(Vector2(200,178))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Details plant selection did not close and refresh"):quit(1);return
	global_row=global.find_order(created_order.id);global_y=142+(global_row.position-global.first)*36
	click(Vector2(888,global_y))
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0),"Global removal failed; no retry"):quit(1);return
	check(global.find_order(created_order.id).is_empty(),"Global removed identity retained")
	# Enter the global picker through its visible native Create control.
	check(global.native_state.get("manager_available",false),"Native global manager observation missing")
	click(Vector2(944,142))
	if not check(await settle(service,func():return owner.order_choices.phase==owner.order_choices.Phase.Ready),"Global creation catalog did not load"):quit(1);return
	var native_groups: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/global-work-order-picker.json"))
	check(owner.order_choices.groups.size()==native_groups.groups.size(),"Global category count differs")
	var still_group: int=-1
	for index in owner.order_choices.groups.size():
		var group: Dictionary=owner.order_choices.groups[index]
		check(group.name==native_groups.groups[index].name and group.count==native_groups.groups[index].rows.size(),"Global category differs from native")
		if group.type==13 and group.subtype==15 and group.custom==-1:still_group=index
	if not check(still_group>=0,"Global Still category missing"):quit(1);return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/global-order-picker-live.png")
	owner.order_picker.group_scroll.move_to(still_group)
	click(Vector2(200,94+(still_group-owner.order_picker.group_first)*36))
	if not check(await settle(service,func():return owner.order_choices.phase==owner.order_choices.Phase.Ready),"Global category selection failed"):quit(1);return
	check(owner.order_choices.rows.size()==4,"Global Still catalog differs")
	click(Vector2(600,94))
	for char in "extract":number_key(KEY_A,char.unicode_at(0))
	if not check(await settle(service,func():return owner.order_choices.phase==owner.order_choices.Phase.Ready),"Global search failed"):quit(1);return
	check(owner.order_choices.rows.size()==1 and owner.order_choices.rows[0].name=="Extract from plants","Global search differs")
	number_key(KEY_ENTER)
	var global_created: Dictionary={}
	owner.order_choices.created.connect(func(receipt):global_created.merge(receipt,true),CONNECT_ONE_SHOT)
	click(Vector2(600,130))
	if not check(await settle(service,func():return not global_created.is_empty() and global.phase==global.Phase.Ready and global.ticket==0),"Global creation was not confirmed; no retry"):quit(1);return
	check(global_created.workshop_id==-1 and global_created.total==10 and global_created.remaining==10,"Global creation defaults differ")
	global.seek(global.total-1,owner.global_orders_view.page_rows)
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0 and not global.find_order(global_created.id).is_empty()),"Created global order not visible"):quit(1);return
	var global_created_row: Dictionary=global.find_order(global_created.id)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/global-order-created-live.png")
	click(Vector2(888,142+(global_created_row.position-global.first)*36))
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0),"Global created order removal failed"):quit(1);return
	global.seek(int(expected.improvement.position),owner.global_orders_view.page_rows)
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0 and not global.find_order(int(expected.improvement.id)).is_empty()),"Encrust order did not load"):quit(1);return
	var improvement_row: Dictionary=global.find_order(int(expected.improvement.id))
	click(Vector2(584,142+(improvement_row.position-global.first)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Encrust Details did not open"):quit(1);return
	click(Vector2(200,106+int(expected.improvement.option)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.snapshot.get("selected_option",-1)==int(expected.improvement.option)),"Improvement choices did not open"):quit(1);return
	check(owner.details.rows.size()==expected.improvement.rows.size(),"Improvement choices differ")
	for index in mini(owner.details.rows.size(),expected.improvement.rows.size()):check(owner.details.rows[index].caption==expected.improvement.rows[index].caption,"Improvement caption differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-details-improvement-live.png")
	click(Vector2(200,142+int(expected.improvement.choice)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Improvement selection did not close and refresh"):quit(1);return
	improvement_row=global.find_order(int(expected.improvement.id))
	click(Vector2(584,142+(improvement_row.position-global.first)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Artwork parent did not reopen"):quit(1);return
	click(Vector2(200,106+int(expected.improvement.option)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.snapshot.get("selected_option",-1)==int(expected.improvement.option)),"Artwork type chooser did not open"):quit(1);return
	click(Vector2(200,142))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.has_art()),"Image did not enter artwork picker"):quit(1);return
	check(owner.details.art_page()==-1 and owner.details.rows.size()==6,"Artwork root differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-root-live.png")
	click(Vector2(200,154))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==1),"Figure subjects did not open"):quit(1);return
	check(owner.details.snapshot.art.total==expected.artwork_subjects[0].count and owner.details.rows.size()==128 and owner.details.rows[0].id==expected.artwork_subjects[0].first,"Figure page differs from native")
	owner.details.seek(128)
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.first==128),"Artwork page did not advance"):quit(1);return
	check(owner.details.rows[0].id==expected.artwork_subjects[0].later,"Artwork paging changed subject identity")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-figures-live.png")
	var back:=InputEventMouseButton.new();back.button_index=MOUSE_BUTTON_RIGHT;back.pressed=true;root.push_input(back,true);back=back.duplicate();back.pressed=false;root.push_input(back,true)
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==-1),"Artwork Back did not return to root"):quit(1);return
	click(Vector2(200,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==2),"Site subjects did not open"):quit(1);return
	click(Vector2(200,154))
	for character in expected.artwork_search.query:number_key(KEY_A,character.unicode_at(0))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.ticket==0),"Artwork search did not finish"):quit(1);return
	check(owner.details.rows[0].id==expected.artwork_search.first and owner.details.snapshot.art.total==expected.artwork_search.count,"Native artwork search differs")
	number_key(KEY_ENTER)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-search-live.png")
	click(Vector2(200,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Artwork selection did not close and refresh"):quit(1);return
	improvement_row=global.find_order(int(expected.improvement.id))
	click(Vector2(584,142+(improvement_row.position-global.first)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Existing image parent did not reopen"):quit(1);return
	click(Vector2(200,106+int(expected.improvement.option)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.snapshot.get("selected_option",-1)==int(expected.improvement.option)),"Existing image type chooser did not open"):quit(1);return
	click(Vector2(200,142))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.has_art()),"Existing image root did not open"):quit(1);return
	click(Vector2(200,262))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==5),"Existing images did not load"):quit(1);return
	check(owner.details.snapshot.art.total==expected.artwork_images.size(),"Native existing image count differs")
	var image_motion:=InputEventMouseMotion.new();image_motion.position=Vector2(200,190);image_motion.global_position=image_motion.position;root.push_input(image_motion,true)
	if not check(await settle(service,func():return owner.details.preview_ticket==0 and not owner.details.preview_lines.is_empty()),"Existing image preview did not load"):quit(1);return
	check(owner.details.preview_lines==expected.artwork_preview,"Native image description/wrapping differs")
	check(owner.details.rows[0].get("badge","")=="Group symbol" and owner.details.rows[1].get("badge","")=="Civilization symbol","Native image symbol labels differ")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-existing-live.png")
	click(Vector2(200,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Existing image selection did not close and refresh"):quit(1);return
	improvement_row=global.find_order(int(expected.improvement.id))
	click(Vector2(584,142+(improvement_row.position-global.first)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Draft parent did not reopen"):quit(1);return
	click(Vector2(200,106+int(expected.improvement.option)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Draft type picker did not open"):quit(1);return
	click(Vector2(200,142))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.has_art()),"Draft artwork root did not open"):quit(1);return
	click(Vector2(200,298))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"New image draft did not open"):quit(1);return
	click(Vector2(70,154))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==7),"Draft creatures did not load"):quit(1);return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-draft-creatures-live.png")
	click(Vector2(300,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Draft creature was not added"):quit(1);return
	check(owner.details.snapshot.art.draft_description==expected.artwork_draft.one,"Native one-element draft description differs")
	click(Vector2(60,226))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==9),"Draft plants did not load"):quit(1);return
	click(Vector2(300,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Draft plant was not added"):quit(1);return
	check(owner.details.snapshot.art.draft_description==expected.artwork_draft.two,"Native two-element draft description differs")
	click(Vector2(100,334))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==14),"Draft relationships did not load"):quit(1);return
	click(Vector2(300,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==15),"Draft actor selection did not open"):quit(1);return
	click(Vector2(300,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==16),"Draft target selection did not open"):quit(1);return
	check(owner.details.rows.size()==1,"Draft target list did not exclude actor")
	click(Vector2(300,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Draft relationship was not added"):quit(1);return
	check(owner.details.snapshot.art.draft_description==expected.artwork_draft.related,"Native related draft description differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-draft-related-live.png")
	click(Vector2(90,370))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==17),"Draft delete list did not open"):quit(1);return
	click(Vector2(960,154))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.draft_value.elements.size()==1),"Draft element was not deleted"):quit(1);return
	check(owner.details.draft_value.relationships.is_empty(),"Draft deletion retained dependent relationship")
	check(owner.details.snapshot.art.draft_description==expected.artwork_draft.deleted,"Native deleted draft description differs")
	click(Vector2(70,418))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Stop deleting did not return to draft"):quit(1);return
	click(Vector2(168,418));await process_frame
	check(owner.details.draft_discard,"Changed draft did not request discard confirmation")
	click(Vector2(300,366))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==-1),"Draft discard did not return to artwork root"):quit(1);return
	click(Vector2(200,298))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Commit draft did not open"):quit(1);return
	check(owner.details.draft_value.has("name"),"DF did not generate the draft name")
	click(Vector2(60,226))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==9),"Commit draft plants did not load"):quit(1);return
	click(Vector2(300,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Commit draft plant was not added"):quit(1);return
	click(Vector2(56,418))
	var artwork_names=owner.details_view.name_state
	if not check(await settle(service,func():return artwork_names.active and artwork_names.phase==artwork_names.Phase.Ready),"Artwork Name editor did not load"):quit(1);return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-name-live.png")
	click(Vector2(400,166))
	if not check(await settle(service,func():return artwork_names.phase==artwork_names.Phase.Ready and owner.details.ticket==0),"Artwork name selection did not complete"):quit(1);return
	check(owner.details.draft_value.name.words[0]==int(expected.artwork_draft.name_word),"Artwork name word differs from native")
	click(Vector2(312,130))
	if not check(await settle(service,func():return artwork_names.phase==artwork_names.Phase.Ready and owner.details.ticket==0),"Artwork name Clear did not complete"):quit(1);return
	check(owner.details.draft_value.name.words[0]==-1,"Artwork name Clear retained its word")
	click(Vector2(848,70))
	if not check(await settle(service,func():return artwork_names.phase==artwork_names.Phase.Ready and owner.details.ticket==0),"Artwork random name did not complete"):quit(1);return
	click(Vector2(400,166))
	if not check(await settle(service,func():return artwork_names.phase==artwork_names.Phase.Ready and owner.details.ticket==0),"Artwork final name selection did not complete"):quit(1);return
	click(Vector2(928,70))
	if not check(await settle(service,func():return not artwork_names.active and owner.details.phase==owner.details.Phase.Ready and owner.details.art_page()==6),"Name Done did not return to artwork"):quit(1);return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-art-draft-done-live.png")
	click(Vector2(112,418))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Done did not install artwork and refresh the order"):quit(1);return
	var size_position: int=-1
	for index in expected.global_order_ids.size():
		if int(expected.global_order_ids[index])==int(expected.clothing_size.id):size_position=index;break
	if not check(size_position>=0,"Clothing order missing from reference list"):quit(1);return
	global.seek(size_position,global.capacity)
	if not check(await settle(service,func():return global.phase==global.Phase.Ready and global.ticket==0 and not global.find_order(int(expected.clothing_size.id)).is_empty()),"Clothing order did not load"):quit(1);return
	var size_row: Dictionary=global.find_order(int(expected.clothing_size.id))
	click(Vector2(584,142+(size_row.position-global.first)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready),"Clothing Details did not open"):quit(1);return
	click(Vector2(200,106+int(expected.clothing_size.option)*36))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.snapshot.get("selected_option",-1)==int(expected.clothing_size.option)),"Clothing sizes did not load"):quit(1);return
	check(owner.details.snapshot.get("current_value","")=="dwarves","Native current clothing size differs")
	check(owner.details.rows.size()==expected.clothing_size.rows.size(),"Native clothing size count differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-order-clothing-size-live.png")
	click(Vector2(200,154))
	for character in "human":number_key(KEY_A,character.unicode_at(0))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Ready and owner.details.ticket==0 and owner.details.query=="human" and not owner.details.rows.is_empty()),"Clothing search did not complete"):quit(1);return
	number_key(KEY_ENTER)
	click(Vector2(200,190))
	if not check(await settle(service,func():return owner.details.phase==owner.details.Phase.Closed and global.phase==global.Phase.Ready and global.ticket==0),"Clothing selection did not update and refresh the order"):quit(1);return
	number_key(KEY_ESCAPE)
	if not check(await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.rows_available and owner.orders.row_ticket==0),"Workshop list did not refresh after global removal"):quit(1);return
	check(not owner.orders.snapshot.order_ids.has(created_order.id) and owner.orders.row_total==0 and owner.orders.rows.is_empty(),"Removed order retained in workshop list")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-order-removed-live.png")
	var file:=FileAccess.open(directory+"/workshop-order-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"created":created_order,"rows":displayed,"quantity":edited,"removed":created_order.id,"order_ids":owner.orders.snapshot.order_ids,"search_names":names,"query":owner.order_picker.query_text(),"header":owner.state.snapshot,"title":owner.panel.title,"contents_page":owner.panel.contents.page,"header_font":owner.panel.theme.default_font!=null}));file.close()
	owner.close_panel();owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)
