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
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"rows":rows.size(),"pages":pages,"stale_rejected":true,"empty_end_page":true}));result.close()
	quit(1 if failed else 0)
