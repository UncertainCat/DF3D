extends "res://tests/workshop_selector_layout_live.gd"
# Native family root choices and composed picker/cancellation.
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
	var checked:=0;var created: Dictionary={};var refused:=0
	for family in reference.task_catalogs:
		owner.open_workshop(int(family.building_id),preload("res://scripts/location_staff_indicators.gd").WORKSHOPS[family.kind.split(":")[1]])
		await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
		owner.panel.tasks.choose_mode(true)
		var choices: Array=owner.tasks.choices()
		check(choices.size()==family.native.size(),"Family choice count differs: "+family.kind)
		for i in mini(choices.size(),family.native.size()):
			check(choices[i].name==family.native[i].caption,"Family caption/order differs: "+family.kind)
			check(choices[i].availability.available==family.native[i].available and choices[i].availability.objection==family.native[i].objection,"Family availability differs: "+family.kind)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/family-"+family.kind.split(":")[1]+"-live.png")
		click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
		check(not owner.panel.tasks.picking,"Family Cancel did not return to Tasks")
		for entry in family.effects:
			owner.panel.tasks.choose_mode(true)
			click(owner.panel.tasks.global_position+Vector2(24,84+(int(entry.index)-1)*36))
			await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
			var id: int=owner.tasks.snapshot.get("created_job",-1)
			check(id>=0 and not owner.panel.tasks.picking,"Family task did not queue: "+entry.caption)
			created[str(int(family.building_id))+":"+str(int(entry.index))]=id
		for i in choices.size():
			if choices[i].availability.available:continue
			owner.panel.tasks.choose_mode(true)
			click(owner.panel.tasks.global_position+Vector2(24,84+i*36))
			check(owner.panel.tasks.picking and owner.tasks.phase==owner.tasks.Phase.Ready,"Unavailable family row accepted a click")
			var rejected:=await request("production",{"action":C.ManagementAction.ProductionQueue,"building_id":int(family.building_id),"recipe":choices[i].key,"task_category":""})
			check(rejected.get("status")==C.ManagementStatus.Rejected,"Unavailable family task was queued")
			refused+=1
		owner.close_panel();checked+=1
	check(checked==3,"Missing family reference")
	owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"families":checked,"created":created,"refused":refused}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
