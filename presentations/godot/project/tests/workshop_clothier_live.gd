extends "res://tests/workshop_selector_layout_live.gd"
# Native Clothier fabric navigation and task effects.
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
	owner.open_workshop(int(family.building_id),preload("res://scripts/location_staff_indicators.gd").WORKSHOPS["13"])
	await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	for invalid in ["clothier:0","clothier:04","clothier:16","clothier:4097"]:
		var rejected:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(family.building_id),"task_category":invalid})
		check(rejected.get("status")==C.ManagementStatus.Rejected,"Invalid fabric accepted")
	owner.panel.tasks.choose_mode(true)
	var roots: Array=owner.tasks.choices()
	check(roots.size()==family.native.size(),"Clothier root count differs")
	for i in mini(roots.size(),family.native.size()):check(roots[i].name==family.native[i].caption,"Clothier root caption/order differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/clothier-root-live.png")
	var created: Dictionary={}
	for index in family.navigation.size():
		var nav: Dictionary=family.navigation[index]
		click(owner.panel.tasks.global_position+Vector2(24,84+index*36))
		await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
		check(owner.tasks.parent=="" and owner.panel.tasks.picking,"Fabric Back missing")
		var choices: Array=owner.tasks.choices()
		check(choices.size()==nav.rows.size(),"Fabric task count differs")
		for i in mini(choices.size(),nav.rows.size()):check(choices[i].name==nav.rows[i].caption and choices[i].availability.available==nav.rows[i].available,"Fabric task differs")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/clothier-page-"+str(index+1)+"-live.png")
		click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
		await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
		check(owner.tasks.category.is_empty() and owner.panel.tasks.picking and owner.tasks.choices()==roots,"Fabric Back did not restore root")
		for entry in nav.effects:
			click(owner.panel.tasks.global_position+Vector2(24,84+index*36))
			await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
			for step in 96:
				if int(entry.index)-1<owner.panel.tasks.first+owner.panel.tasks.scrollbar.page:break
				var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=owner.panel.tasks.global_position+Vector2(60,120);root.push_input(wheel);await process_frame
			click(owner.panel.tasks.global_position+Vector2(24,84+(int(entry.index)-1-owner.panel.tasks.first)*36))
			await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
			var id: int=owner.tasks.snapshot.get("created_job",-1)
			check(id>=0 and not owner.panel.tasks.picking,"Fabric task did not queue")
			created[str(int(nav.fabric))+":"+str(int(entry.index))]=id
			owner.panel.tasks.choose_mode(true)
			await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
	check(not owner.panel.tasks.picking,"Clothier root Cancel failed")
	owner.close_panel();owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"created":created}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
