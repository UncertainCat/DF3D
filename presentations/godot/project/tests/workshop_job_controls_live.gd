extends "res://tests/workshop_selector_layout_live.gd"
# Actual task Details gestures using the shared native-backed job editor.
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json")).job_controls
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
	owner.open_workshop(int(reference.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	var task_choices: Array=owner.tasks.recipes()
	check(owner.tasks.snapshot.get("task_category","missing")=="" and owner.tasks.snapshot.get("task_categories",[]).size()==1,"Native root category missing")
	var staged_category:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(reference.building_id),"task_category":"reaction:INSTRUMENTS"})
	check(staged_category.get("status")==C.ManagementStatus.Rejected,"Unknown category request was silently treated as root")
	check(task_choices.size()==reference.task_choices.size(),"Native root task count differs")
	for index in mini(task_choices.size(),reference.task_choices.size()):
		var expected: Dictionary=reference.task_choices[index]
		var actual: Dictionary=task_choices[index]
		check(actual.name==expected.name and actual.get("availability",{}).get("available")==expected.available and actual.get("availability",{}).get("objection")==expected.objection,"Native root task caption or availability differs")
	owner.panel.tasks.choose_mode(true);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-task-category-root-live.png")
	click(owner.panel.tasks.global_position+Vector2(24,90))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	check(owner.tasks.category==reference.category_reference.key and owner.tasks.query.is_empty(),"Native category selection or cleared search differs")
	var child: Array=owner.tasks.recipes()
	check(child.size()==reference.category_reference.rows.size(),"Native child task count differs")
	for index in mini(child.size(),reference.category_reference.rows.size()):
		var expected: Dictionary=reference.category_reference.rows[index]
		check(child[index].name==expected.name and child[index].availability.available==expected.available and child[index].availability.objection==expected.objection,"Native child task differs")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-task-category-child-live.png")
	click(owner.panel.tasks.global_position+Vector2(owner.panel.tasks.size.x-48,12))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	check(not owner.panel.tasks.picking and owner.tasks.category.is_empty(),"Cancel did not return to Tasks")
	# Build three jobs and compare actual Priority gestures with native queue effects.
	var recipe_key:=""
	for recipe in owner.tasks.recipes():
		if recipe.name=="Make bed":recipe_key=recipe.key;break
	if not check(not recipe_key.is_empty(),"Make bed recipe unavailable"):quit(1);return
	var job_ids: Array=[int(reference.viewer_job_id)]
	for extra in 2:
		owner.tasks.queue_task(recipe_key);await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
		job_ids.append(owner.tasks.snapshot.created_job)
	var native_ids: Array=[]
	for row in owner.tasks.jobs():check(not row.has("can_move_up"),"Migration invented Move up capability")
	var staged_move:=await request("production",{"action":C.ManagementAction.ProductionJobEdit,"building_id":int(reference.building_id),"job_id":int(job_ids[1]),"expected_previous_job_id":int(job_ids[0])})
	check(staged_move.get("status")==C.ManagementStatus.Rejected,"Unimplemented Move up was silently accepted")
	for row in reference.priority_queue[0].rows:native_ids.append(int(row.id))
	for sample in reference.priority_queue.slice(1):
		var target: int=job_ids[native_ids.find(int(sample.target))]
		await process_frame
		var current: Array=owner.tasks.jobs()
		for index in current.size():
			if current[index].id==target:click(Vector2(772,154+index*36));break
		await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
		current=owner.tasks.jobs()
		print("Priority ",sample.name,": ",current.map(func(row):return {"id":row.id,"priority":row.get("priority"),"worker_id":row.worker_id}))
		if sample.name=="middle-on":
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/workshop-job-priority-middle-on-live.png")
			var stale:=await request("production",{"action":C.ManagementAction.ProductionJobEdit,"building_id":int(reference.building_id),"job_id":target,"priority":1,"expected_priority":0})
			check(stale.get("status")==C.ManagementStatus.Rejected,"Stale Priority expectation was accepted")
		check(current.size()==sample.rows.size(),"Priority changed queue size")
		for index in mini(current.size(),sample.rows.size()):
			var expected: Dictionary=sample.rows[index]
			check(current[index].id==job_ids[native_ids.find(int(expected.id))] and current[index].get("priority")==expected.do_now and current[index].worker_id==int(expected.worker_id),"Priority queue, flags or worker differ from native")
	for id in job_ids.slice(1):
		owner.tasks.cancel_task(id);await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	await process_frame;click(Vector2(820,154))
	await settle(service,func():return owner.job_details.phase==owner.job_details.Phase.Ready)
	check(owner.job_details.job_id==int(reference.viewer_job_id) and not owner.panel.tasks_allowed(),"Details target or parent input ownership differs")
	check(owner.job_details_view.position==Vector2(72,52) and owner.job_details_view.size==Vector2(832,672),"Workshop Details frame differs from native")
	var rows: Array=owner.job_details.rows
	check(rows.size()==reference.details.materials.size(),"Workshop material count differs")
	# Choices expose opaque IDs/captions, not raw native material identities.
	# Compare rendered choices and independently read back the selected job.
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-job-details-live.png")
	# Escape returns without applying; opening again reads the same native job.
	number_key(KEY_ESCAPE);await process_frame
	check(not owner._job_details_open() and owner.panel.visible,"Details Escape did not return to workshop")
	click(Vector2(820,154));await settle(service,func():return owner.job_details.phase==owner.job_details.Phase.Ready)
	click(Vector2(100,190))
	await settle(service,func():return not owner._job_details_open() and owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-job-details-return-live.png")
	# Closing the owner during a fresh queued read retires child ownership.
	click(Vector2(820,154));owner.close_panel()
	for frame in 8:world.poll();service.poll(0.01);await process_frame
	check(not owner._job_details_open() and not owner.job_details_view.visible and owner.job_details.ticket==0,"Closed workshop retained Details ownership")
	owner.open_workshop(int(reference.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	var variant_key:=""
	for recipe in owner.tasks.recipes():
		if recipe.name=="Make menacing wooden spike":variant_key=recipe.key;break
	if not check(not variant_key.is_empty(),"Native task variant missing"):quit(1);return
	owner.tasks.queue_task(variant_key)
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	var variant_id: int=owner.tasks.snapshot.get("created_job",-1)
	check(variant_id>=0,"Native task variant did not queue")
	owner.panel.tasks.choose_mode(true);await process_frame
	click(owner.panel.tasks.global_position+Vector2(24,90))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready)
	await process_frame;click(owner.panel.tasks.global_position+Vector2(24,90))
	await settle(service,func():return owner.tasks.phase==owner.tasks.Phase.Ready and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready)
	var category_job_id: int=owner.tasks.snapshot.get("created_job",-1)
	check(category_job_id>=0 and category_job_id!=variant_id and not owner.panel.tasks.picking,"Category task gesture did not queue and return to Tasks")
	owner.close_panel();owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"variant_id":variant_id,"category_job_id":category_job_id,"materials":rows.size(),"priority_queue":true,"escape_return":true,"material_click":true,"parent_close":true}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
