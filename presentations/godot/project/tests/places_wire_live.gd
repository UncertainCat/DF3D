extends "res://tests/item_carrier_wire_live.gd"
func page(tab: int,offset:=0,revision:=0) -> Dictionary:
	return await request("places",{"action":C.ManagementAction.PlacesRead,"tab":tab,"offset":offset,"limit":16,"expected_list_revision":revision})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/places-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Places attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var counts: Array=[]
	for tab in 6:
		var rows: Array=[];var revision:=0;var first:=true
		while first or rows.size()<reference[tab].size():
			first=false;var reply:=await page(tab,rows.size(),revision)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Places page rejected"):quit(1);return
			var state: Dictionary=reply.get("places",{})
			check(state.get("tab")==tab and state.get("offset")==rows.size() and state.get("total")==reference[tab].size(),"Places page bounds differ")
			revision=state.get("list_revision",0)
			if not check(not state.get("rows",[]).is_empty() or rows.size()==reference[tab].size(),"Places pagination stalled"):quit(1);return
			rows.append_array(state.rows)
		for i in rows.size():
			var row: Dictionary=rows[i];var expected: Dictionary=reference[tab][i]
			check(row.building_id==int(expected.id),"Places identity differs")
			for key in ["name","subtitle","job_caption","status_caption","secondary_status","status_overlay","operator_caption","additional_jobs","siege_action"]:
				check(row.get(key)==expected.get(key),"Places field differs: "+key)
			var p: Array=expected.position
			check(row.get("position")==Vector3i(int(p[0]),int(p[1]),int(p[2])),"Places position differs")
			check(row.has("appearance")==expected.has("appearance"),"Places artwork presence differs")
			if row.has("appearance"):
				check(row.appearance.tile_pages==expected.appearance.pages,"Places artwork pages differ")
				check(row.appearance.layers==expected.appearance.layers.map(func(layer):return layer.map(func(n):return int(n))),"Places artwork layers differ")
		var stale:=await page(tab,0,revision ^ 1)
		check(stale.get("places",{}).get("outcome")==C.PlacesOutcome.Stale,"Places stale list accepted")
		counts.append(rows.size())
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"counts":counts,"stale_tabs":6}));result.close()
	quit(1 if failed else 0)
