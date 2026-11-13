extends "res://tests/workshop_selector_layout_live.gd"
# Protected native Dyer first-level menu comparison; no task creation.
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Workshop source unavailable"):quit(1);return
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
	var family: Dictionary=reference.task_catalogs[0]
	owner.open_workshop(int(family.building_id),preload("res://scripts/location_staff_indicators.gd").WORKSHOPS["21"])
	await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	owner.panel.tasks.choose_mode(true)
	var roots: Array=owner.tasks.choices()
	check(roots.size()==family.native.size(),"Dyer root count differs")
	for i in mini(roots.size(),family.native.size()):check(roots[i].name==family.native[i].caption,"Dyer root order differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/dyer-root-live.png")
	for page_index in range(1,5):
		click(owner.panel.tasks.global_position+Vector2(24,84+(page_index-1)*36))
		await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
		var choices: Array=owner.tasks.choices()
		var rows: Array=family.pages[page_index].rows
		check(choices.size()==rows.size(),"Dyer page count differs")
		for i in mini(choices.size(),rows.size()):
			check(choices[i].name==rows[i].caption,"Dyer caption/order differs")
			var dye: Dictionary=choices[i].get("dye",{})
			check(dye.get("text")==rows[i].info,"Dyer availability text differs")
			check(dye.get("color_id")==int(rows[i].get("color",rows[i].get("specdata",-1))),"Dyer color identity differs")
			for channel in ["red","green","blue"]:check(absf(float(dye.get(channel,-1))-float(rows[i].swatch[channel]))<0.00001,"Dyer RGB differs")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/dyer-page-"+str(page_index)+"-live.png")
		check(owner.tasks.parent==null,"Dyer page should have Cancel")
		click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
		await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
		check(not owner.panel.tasks.picking,"Dyer Cancel failed")
		owner.panel.tasks.choose_mode(true)
		await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
		check(owner.tasks.choices()==roots,"Dyer root reopen differs")
	owner.close_panel();owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
