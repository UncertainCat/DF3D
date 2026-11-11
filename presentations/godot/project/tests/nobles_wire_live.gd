extends "res://tests/item_carrier_wire_live.gd"
func normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=normalize(value[key])
		return result
	if value is Array:return value.map(normalize)
	return int(value) if typeof(value)==TYPE_FLOAT else value
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
		for key in ["entity_id","position_id","assignment_id","unit_id","nemesis_id","title","squad_caption","holder_caption","can_appoint","has_room_assessment","required_rooms","actual_rooms","required_furniture","actual_furniture","demand_status","mandate_status","help"]:
			var wanted: Variant=normalize(expected.get(key))
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
		for row in model.rows:
			if row.unit_id>=0:check(row.has("appearance") and view.portraits.get(row.unit_id,{}).get("texture")!=null,"Nobles holder portrait unavailable")
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-view.png")
		view.set_process(false)
		for sample in [["rooms",Vector2(552,126)],["furniture",Vector2(680,126)],["mandates",Vector2(760,126)],["description",Vector2(24,342)]]:
			view.hovered=view.hover_at(sample[1]);check(view.hovered.get("kind")==sample[0],"Nobles live hover selection differs: "+sample[0]);view.queue_redraw()
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/nobles-help-"+sample[0]+".png")
		root.size=Vector2i(1600,900);view.layout(Vector2(1600,900));view.hovered={};view.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-wide.png")
		var accounting_row:=-1
		for index in model.rows.size():
			if model.rows[index].get("help",{}).has("accounting"):accounting_row=index;break
		check(accounting_row>=0,"Live fixture lacks accounting holder")
		if accounting_row>=0:
			view.hovered=view.hover_at(Vector2(view.status_x()+320,view.list_top()+accounting_row*36+18));check(view.hovered.get("kind")=="accounting","Nobles accounting hover missing")
			view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/nobles-help-accounting.png")
		view.queue_free();await process_frame
	model.refresh();model.close()
	for frame in 5:world.poll();await process_frame
	check(model.phase==model.Phase.Closed and model.rows.is_empty() and model.ticket==0,"Closed Nobles controller accepted live read")
	model.dispose();actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"controller_ready":true,"closed_read_retired":true,"success":not failed,"rows":rows.size(),"pages":pages,"stale_rejected":true,"empty_end_page":true}));result.close()
	quit(1 if failed else 0)
