extends "res://tests/workshop_selector_layout_live.gd"
# Composed forge category/material navigation and native job effect.
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json")).forge_choices
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
	owner.open_workshop(int(reference.building_id),"BUILDING_ICON_WORKSHOP_METALSMITH")
	await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)

	for invalid in ["forge:00","forge:0:999999","forge:0:4294967296","forge:6:0"]:
		var rejected:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(reference.building_id),"task_category":invalid})
		check(rejected.get("status")==C.ManagementStatus.Rejected,"Invalid forge key was accepted")
	owner.panel.tasks.choose_mode(true)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-forge-root-live.png")
	var root_choices: Array=owner.tasks.choices()
	check(root_choices.size()>=7,"Forge root categories missing")
	for i in mini(7,root_choices.size()):check(root_choices[i].name==reference.pages[0].native[i].caption,"Forge category order or caption differs")
	click(owner.panel.tasks.global_position+Vector2(24,68))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	check(owner.tasks.parent=="" and owner.panel.tasks.picking,"Forge material page lacks Back to root")
	var materials: Array=owner.tasks.choices()
	check(materials.size()==reference.pages[1].native.size(),"Forge material count differs")
	for i in mini(materials.size(),reference.pages[1].native.size()):check(materials[i].name==reference.pages[1].native[i].caption,"Forge material order or caption differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-forge-material-live.png")
	check(owner.panel.tasks.scrollbar.page==14,"Forge material viewport differs from native 1200x800 capture")
	click(owner.panel.tasks.global_position+Vector2(24,72+14*36+12))
	await process_frame
	check(owner.tasks.category=="forge:0" and owner.tasks.phase==owner.tasks.Phase.Ready,"Blank picker footer selected a hidden material")
	click(owner.panel.tasks.global_position+Vector2(24,90))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var tasks: Array=owner.tasks.recipes();var native_tasks: Array=data.forge_navigation[0].rows
	check(tasks.size()==native_tasks.size(),"Forge task count differs")
	for i in mini(tasks.size(),native_tasks.size()):check(tasks[i].name==native_tasks[i].caption and tasks[i].availability.available,"Forge task caption or availability differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-forge-tasks-live.png")
	click(owner.panel.tasks.global_position+Vector2(32,48))
	for char in "bolt":number_key(KEY_NONE,char.unicode_at(0))
	number_key(KEY_ENTER)
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	check(owner.tasks.recipes().size()==1,"Forge task filter differs")
	click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	check(owner.panel.tasks.picking and owner.tasks.parent=="" and owner.tasks.query.is_empty() and owner.tasks.choices().size()==materials.size(),"Back did not restore unfiltered materials")
	click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	check(owner.panel.tasks.picking and owner.tasks.parent==null and owner.tasks.category.is_empty(),"Back did not restore root picker")
	for step in 2:
		click(owner.panel.tasks.global_position+Vector2(24,90));await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	click(owner.panel.tasks.global_position+Vector2(24,90))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	var created: int=owner.tasks.snapshot.get("created_job",-1)
	check(created>=0 and not owner.panel.tasks.picking,"Forge task did not queue and return to Tasks")
	owner.close_panel();owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"created_job":created}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
