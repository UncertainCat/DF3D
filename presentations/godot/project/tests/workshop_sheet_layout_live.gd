extends "res://tests/workshop_selector_layout_live.gd"
# Protected native sheet navigation at the captured window sizes.
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Workshop layout source unavailable"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Workshop bootstrap failed"):quit(1);return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var owner=preload("res://scripts/workshop_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
	owner.open_workshop(int(reference.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	var samples: Array=[]
	for sample in reference.sheet_layout:
		root.size=Vector2i(int(sample.dimx)*8,int(sample.dimy)*12+(8 if sample.size=="default" else 0))
		await process_frame;await process_frame;owner._process(0)
		for tab in 3:
			click(owner.panel.global_position+owner.panel.tab_rect(tab).get_center())
			await settle(service,func():return owner.panel.selected_tab==tab and (tab!=1 or owner.workers.phase==owner.workers.Phase.Ready) and (tab!=2 or owner.orders.phase==owner.orders.Phase.Ready))
			if tab==2 and reference.has("sheet_orders"):
				await settle(service,func():return owner.orders.rows.size()==2 and owner.orders.row_ticket==0)
			if tab==1 and reference.has("sheet_assigned"):
				await settle(service,func():return owner.panel.workers.unit_icon!=null)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/workshop-sheet-"+sample.size+"-"+["Tasks","Workers","Work-orders"][tab]+"-live.png")
			if tab==1 and reference.has("sheet_assigned"):
				var worker_id: int=reference.sheet_assigned.unit_id
				var initial: bool=reference.sheet_assigned.specialized
				check(owner.workers.assigned.get("id")==worker_id,"Assigned worker identity differs")
				click(owner.panel.workers.global_position+owner.panel.workers.specialization_rect().get_center())
				await settle(service,func():return worker_ready(owner) and owner.workers.assigned.specialized!=initial)
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/workshop-sheet-"+sample.size+"-Workers-mode-live.png")
				click(owner.panel.workers.global_position+owner.panel.workers.specialization_rect().get_center())
				await settle(service,func():return worker_ready(owner) and owner.workers.assigned.specialized==initial)
				click(owner.panel.workers.global_position+owner.panel.workers.remove_rect().get_center())
				await settle(service,func():return worker_ready(owner) and owner.workers.permitted_workers.is_empty())
				click(owner.panel.workers.global_position+owner.panel.workers.assign_rect().get_center());await process_frame
				if not check(owner.selector.visible and not owner.selector.rows.is_empty() and int(owner.selector.rows[0].unit_id)==worker_id,"Resized worker selector lost native first candidate"):quit(1);return
				click(Vector2(80,106))
				await settle(service,func():return worker_ready(owner) and owner.workers.assigned.get("id")==worker_id)
		if reference.has("sheet_orders"):
			var initial: int=reference.sheet_orders.quantity
			for value in [12,initial]:
				click(owner.panel.orders.global_position+Vector2(344,54))
				for digit in str(value):number_key(KEY_0+digit.to_int(),digit.unicode_at(0))
				number_key(KEY_ENTER)
				await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.rows.get(0,{}).get("remaining",-1)==value and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
		var limit: int=owner.orders.snapshot.general_order_limit
		click(owner.panel.orders.global_position+owner.panel.orders.button_rect(1).get_center())
		await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.snapshot.general_order_limit==limit+1)
		click(owner.panel.orders.global_position+owner.panel.orders.button_rect(2).get_center())
		await settle(service,func():return owner.orders.phase==owner.orders.Phase.Ready and owner.orders.snapshot.general_order_limit==limit)
		click(owner.panel.global_position+owner.panel.tab_rect(0).get_center());await process_frame
		click(owner.panel.tasks.global_position+owner.panel.tasks.add_rect().get_center())
		check(owner.panel.tasks.picking,"Resized task picker did not open")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/workshop-sheet-"+sample.size+"-picker-live.png")
		click(owner.panel.tasks.global_position+owner.panel.tasks.cancel_rect().get_center())
		await process_frame
		check(not owner.panel.tasks.picking and owner.tasks.jobs().size()==2,"Resized Cancel changed queue or retained picker")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/workshop-sheet-"+sample.size+"-return-live.png")
		samples.append({"size":sample.size,"jobs":owner.tasks.jobs().size(),"panel_position":[owner.panel.position.x,owner.panel.position.y],"panel_size":[owner.panel.size.x,owner.panel.size.y]})
	owner.close_panel();owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"sheet_layout":samples}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)

func worker_ready(owner) -> bool:
	return owner.workers.phase==owner.workers.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready
