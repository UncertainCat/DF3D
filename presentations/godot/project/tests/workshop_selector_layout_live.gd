extends "res://tests/workshop_wire_live.gd"
# Protected composed selector against recorded native widget geometry.
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Selector live source unavailable"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Workshop bootstrap failed"):quit(1);return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var owner=preload("res://scripts/workshop_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
	owner.open_workshop(int(reference.building_id),"BUILDING_ICON_WORKSHOP_STILL")
	await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	click(Vector2(536,112))
	await settle(service,func():return owner.workers.phase==owner.workers.Phase.Ready)
	click(Vector2(448,154));await process_frame
	if not check(owner.selector.visible,"Worker picker did not open"):quit(1);return
	var samples: Array=[]
	for sample in reference.selector_layout:
		root.size=Vector2i(int(sample.dimx)*8,int(sample.dimy)*12+(8 if sample.size=="default" else 0))
		await process_frame;await process_frame;owner._process(0)
		await settle(service,func():return owner.candidate_modes.receipts.size()>=mini(owner.selector.page_rows,owner.selector.rows.size()))
		var outer: Array=[];var rows: Array=[]
		for widget in sample.geometry:
			if widget.type=="<type: unit_selector_interfacest>":outer=widget.rect
			if widget.type=="<type: widget_scroll_rows>" and rows.is_empty():rows=widget.rect
		check(owner.selector.size.x==(outer[2]-outer[0]+3)*8,"Native selector frame width differs")
		check(owner.selector.row_columns()==rows[2]-rows[0],"Native row width differs")
		check(owner.selector.scrollbar.global_position.x==(rows[2]+1)*8,"Native scrollbar position differs")
		var filter_point: Vector2=owner.selector.global_position+Vector2(48,owner.selector.filter_cell()*12+18)
		click(filter_point);check(owner.selector.filter_focused,"Resized filter missed input")
		number_key(KEY_ENTER);check(not owner.selector.filter_focused and owner.selector.visible,"Filter Enter selected worker")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/workshop-selector-"+sample.size+"-live.png")
		samples.append({"size":sample.size,"width":owner.selector.size.x,"row_columns":owner.selector.row_columns(),"scrollbar_x":owner.selector.scrollbar.global_position.x})
	number_key(KEY_ESCAPE);await process_frame
	check(not owner.selector.visible,"Escape retained selector")
	owner.close_panel();owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"selector_layout":samples}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)

func settle(service,ready: Callable) -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01)
		if ready.call():return
		await create_timer(0.01).timeout
	check(false,"Selector observation timed out; no replay")
