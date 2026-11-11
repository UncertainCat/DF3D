extends "res://tests/item_carrier_wire_live.gd"
func page(offset: int,revision: int) -> Dictionary:
	return await request("nobles",{"action":C.ManagementAction.NoblesRead,"offset":offset,"limit":4,"expected_list_revision":revision})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/nobles-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Nobles attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var rows: Array=[];var revision:=0;var pages:=0
	while pages==0 or rows.size()<reference.size():
		var reply:=await page(rows.size(),revision)
		if not check(reply.get("status")==C.ManagementStatus.Ok,"Nobles read rejected"):quit(1);return
		var state: Dictionary=reply.get("nobles",{})
		check(state.get("offset")==rows.size() and state.get("total")==reference.size(),"Nobles page bounds differ")
		if not check(not state.get("rows",[]).is_empty() or rows.size()==reference.size(),"Nobles paging stalled"):quit(1);return
		if revision:check(state.list_revision==revision,"Nobles continuation revision changed")
		revision=state.list_revision;rows.append_array(state.rows);pages+=1
	for i in rows.size():
		var expected: Dictionary=reference[i];var row: Dictionary=rows[i]
		for key in ["entity_id","position_id","assignment_id","unit_id","nemesis_id","title","squad_caption","holder_caption","can_appoint","has_room_assessment","required_rooms","actual_rooms","required_furniture","actual_furniture","demand_status","mandate_status"]:
			var wanted: Variant=expected.get(key)
			if wanted is Array:wanted=wanted.map(func(value):return int(value))
			check(row.get(key)==wanted,"Nobles field differs: "+key)
		check(row.priority==expected.value,"Nobles priority differs")
	var stale:=await page(0,revision ^ 1)
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("nobles",{}).get("outcome")==C.NoblesOutcome.Stale,"Nobles stale revision accepted")
	var end_page:=await page(rows.size(),revision)
	check(end_page.get("status")==C.ManagementStatus.Ok and end_page.get("nobles",{}).get("rows",[1]).is_empty(),"Nobles end page differs")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var model=preload("res://scripts/nobles_state.gd").new();model.configure(actions);model.open()
	deadline=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	check(model.phase==model.Phase.Ready and model.rows==rows,"Live Nobles controller differs from transport")
	if OS.get_environment("DF3D_NOBLES_RENDER")=="1":
		if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Nobles assets unavailable"):quit(1);return
		root.size=Vector2i(1200,800)
		var view=preload("res://scripts/nobles_view.gd").new();root.add_child(view);view.configure_nobles(world,model);view.layout(Vector2(1200,800))
		for token in ["NOBLES_ADD","NOBLES_ASSIGN_SYMBOL","NOBLES_OFFICE_GOOD","NOBLES_FURN_MISSING","NOBLES_DEMANDS_NA","NOBLES_MANDATES_TIME_WARN_1"]:check(view.art.texture(token)!=null,"Missing native Nobles artwork: "+token)
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-view.png")
		view.queue_free();await process_frame
	model.refresh();model.close()
	for frame in 5:world.poll();await process_frame
	check(model.phase==model.Phase.Closed and model.rows.is_empty() and model.ticket==0,"Closed Nobles controller accepted live read")
	model.dispose();actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"controller_ready":true,"closed_read_retired":true,"success":not failed,"rows":rows.size(),"pages":pages,"stale_rejected":true,"empty_end_page":true}));result.close()
	quit(1 if failed else 0)
