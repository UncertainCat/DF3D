extends "res://tests/workshop_selector_layout_live.gd"
# Native custom reaction navigation, refusals and job effects.
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
	var created: Dictionary={}
	var checked:=0
	var refused:=0
	for family in reference.task_catalogs:
		var icons=preload("res://scripts/location_staff_indicators.gd")
		owner.open_workshop(int(family.building_id),(icons.FURNACES if family.kind.begins_with("5:") else icons.WORKSHOPS)[family.kind.split(":")[1]])
		await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
		for page_index in family.pages.size():
			var page: Dictionary=family.pages[page_index]
			if page.get("reaction_parent","").is_empty():continue
			owner.panel.tasks.choose_mode(true)
			for step in page.path:
				var choices: Array=owner.tasks.choices()
				var index:=int(step.index)-1
				if not check(index<choices.size() and choices[index].name==step.caption,"Reaction path differs"):quit(1);return
				click(owner.panel.tasks.global_position+Vector2(24,84+index*36))
				await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
			var choices: Array=owner.tasks.choices()
			check(choices.size()==page.rows.size(),"Reaction child count differs")
			for i in mini(choices.size(),page.rows.size()):
				check(choices[i].name==page.rows[i].caption,"Reaction child caption/order differs")
				if page.rows[i].has("available"):
					check(choices[i].availability.available==page.rows[i].available and choices[i].availability.objection==page.rows[i].objection,"Reaction child availability differs")
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/reaction-page-"+str(page_index+1)+"-live.png")
			for i in choices.size():
				if not choices[i].has("availability") or choices[i].availability.available:continue
				click(owner.panel.tasks.global_position+Vector2(24,84+i*36))
				check(owner.panel.tasks.picking and owner.tasks.phase==owner.tasks.Phase.Ready,"Unavailable reaction accepted click")
				var rejected:=await request("production",{"action":C.ManagementAction.ProductionQueue,"building_id":int(family.building_id),"recipe":choices[i].key,"task_category":owner.tasks.category})
				check(rejected.get("status")==C.ManagementStatus.Rejected,"Unavailable child reaction queued")
				refused+=1
			click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
			await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
			check(not owner.panel.tasks.picking and page.cancel_returns_tasks,"Reaction Cancel differs from native")
			owner.panel.tasks.choose_mode(true)
			for step in page.path:
				click(owner.panel.tasks.global_position+Vector2(24,84+(int(step.index)-1)*36))
				await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
			if page.has("effect"):
				click(owner.panel.tasks.global_position+Vector2(24,84+(int(page.effect.index)-1)*36))
				await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
				var id: int=owner.tasks.snapshot.get("created_job",-1)
				check(id>=0 and not owner.panel.tasks.picking,"Reaction child did not queue")
				created[str(int(family.building_id))+":"+str(page_index+1)]=id
				var jobs: Array=owner.tasks.jobs()
				var index:=jobs.size()-1
				if check(index>=0 and jobs[index].id==id and jobs[index].editable,"Reaction child lost root controls"):
					for desired in [true,false]:
						click(owner.panel.tasks.global_position+Vector2(316,48+index*36))
						await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
						check(owner.tasks.jobs()[index].repeat==desired,"Reaction Repeat differs")
			else:
				click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
				check(not owner.panel.tasks.picking,"Reaction Cancel did not return to Tasks")
			checked+=1
		owner.close_panel()
	check(checked>0,"No reaction child pages checked")
	owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"pages":checked,"created":created,"refused":refused}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
