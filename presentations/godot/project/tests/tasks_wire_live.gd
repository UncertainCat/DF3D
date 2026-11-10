extends "res://tests/item_carrier_wire_live.gd"
func page(offset:=0,revision:=0) -> Dictionary:
	return await request("tasks",{"action":C.ManagementAction.TasksRead,"offset":offset,"limit":16,"expected_list_revision":revision})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/tasks-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Tasks attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var rows: Array=[];var revision:=0
	while rows.size()<reference.size():
		var reply:=await page(rows.size(),revision)
		if not check(reply.get("status")==C.ManagementStatus.Ok,"Tasks page rejected"):quit(1);return
		var state: Dictionary=reply.get("tasks",{})
		check(state.get("offset")==rows.size() and state.get("total")==reference.size(),"Tasks page bounds differ")
		revision=state.get("list_revision",0)
		if not check(not state.get("rows",[]).is_empty(),"Tasks pagination stalled"):quit(1);return
		rows.append_array(state.rows)
	for i in rows.size():
		var row: Dictionary=rows[i];var expected: Dictionary=reference[i]
		for key in ["job_id","building_id","caption","worker_name","building_caption","can_view_job","can_repeat","can_remove_worker","can_suspend","can_cancel","repeating","suspended"]:check(row.get(key)==expected.get(key),"Tasks field differs: "+key)
		check(row.worker_id==int(expected.unit_id),"Tasks worker differs")
		for key in ["worker_appearance","building_appearance"]:
			check(row.has(key)==expected.has(key),"Tasks artwork presence differs")
			if row.has(key):
				check(row[key].tile_pages==expected[key].pages,"Tasks artwork pages differ")
				var expected_layers: Array=expected[key].layers.map(func(layer):return layer.map(func(n):return int(n)))
				check(row[key].layers==expected_layers,"Tasks artwork layers differ")
	var stale:=await page(16,revision ^ 1)
	check(stale.get("tasks",{}).get("outcome")==C.TasksOutcome.Stale,"Tasks stale list accepted")
	var target: Dictionary={}
	for row in rows:
		if row.job_id==68196:target=row
	if not check(not target.is_empty(),"Tasks edit fixture absent"):quit(1);return
	for step in [1,2]:
		var intent: Dictionary={"action":C.ManagementAction.TasksApply,"job_id":target.job_id,"worker_id":target.worker_id,"building_id":target.building_id,"expected_revision":target.revision,"operation":C.TasksOperation.Suspend,"expected_state":int(target.suspended)}
		var applied:=await request("tasks",intent)
		if not check(applied.get("tasks",{}).get("outcome")==C.TasksOutcome.Applied,"Tasks suspend failed"):quit(1);return
		var file=FileAccess.open(directory+"/tasks-wire-step",FileAccess.WRITE);file.store_string(str(step));file.close()
		deadline=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-wire-ack")!=str(step):await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/tasks-wire-ack")==str(step),"Native Tasks effect unconfirmed")
		var duplicate:=await request("tasks",intent)
		check(duplicate.get("tasks",{}).get("outcome")==C.TasksOutcome.Stale,"Tasks stale edit replayed")
		var offset:=0;var found:=false
		while offset<reference.size():
			var fresh:=await page(offset,revision);var entries: Array=fresh.get("tasks",{}).get("rows",[])
			if entries.is_empty():break
			for row in entries:
				if row.job_id==target.job_id:target=row;found=true
			offset+=entries.size()
		check(found,"Edited Tasks row disappeared")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var state=preload("res://scripts/tasks_state.gd").new();state.configure(actions);state.open()
	deadline=Time.get_ticks_msec()+5000
	while state.phase==state.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	check(state.phase==state.Phase.Ready and state.rows.size()==reference.size(),"Tasks controller did not assemble native pages")
	if OS.get_environment("DF3D_TASKS_RENDER")=="1":
		root.size=Vector2i(1200,800)
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Tasks assets unavailable")
		var view=preload("res://scripts/tasks_view.gd").new();root.add_child(view)
		view.configure_tasks(world,state);view.layout(Vector2(1200,800))
		for first in [0,17,24]:
			state.seek(first,view.capacity());await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/tasks-view-%d.png"%first)
		view.queue_free();await process_frame
	state.dispose();actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"rows":rows.size(),"suspend_steps":2}));result.close()
	quit(1 if failed else 0)
