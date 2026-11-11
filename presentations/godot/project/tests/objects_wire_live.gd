extends "res://tests/item_carrier_wire_live.gd"
func page(tab: int, offset: int, revision: int) -> Dictionary:
	return await request("objects",{"action":C.ManagementAction.ObjectsRead,"tab":tab,"offset":offset,"limit":4,"expected_list_revision":revision})
func locate(tab: int, artifact: int, revision: int) -> Dictionary:
	return await request("objects",{"action":C.ManagementAction.ObjectsLocate,"tab":tab,"artifact_id":artifact,"expected_list_revision":revision})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/objects-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Objects attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var counts: Array=[];var lookups:=0
	for tab in 4:
		var expected: Array=reference.ownership[tab];var rows: Array=[];var revision:=0;var first:=true
		while first or rows.size()<expected.size():
			first=false;var reply:=await page(tab,rows.size(),revision)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Objects page rejected"):quit(1);return
			var state: Dictionary=reply.get("objects",{})
			check(state.get("tab")==tab and state.get("offset")==rows.size() and state.get("total")==expected.size(),"Objects page identity differs")
			revision=state.get("list_revision",0)
			if not check(not state.get("rows",[]).is_empty() or rows.size()==expected.size(),"Objects page stalled"):quit(1);return
			rows.append_array(state.rows)
		for i in rows.size():
			for key in ["artifact_id","item_id","native_name","translated_name","ownership"]:
				check(rows[i].get(key)==expected[i][key],"Objects row differs: "+key)
			var target: Dictionary=reference.destinations[tab][i]
			check(rows[i].has("position")==target.available,"Objects availability differs")
			if target.available:
				check(rows[i].position==Vector3i(int(target.position[0]),int(target.position[1]),int(target.position[2])),"Objects position differs")
			if i==0 or (target.available and lookups==1):
				var reply:=await locate(tab,int(rows[i].artifact_id),revision)
				check(reply.get("status")==C.ManagementStatus.Ok,"Objects lookup rejected")
				var d: Dictionary=reply.get("objects",{}).get("destination",{})
				check(d.get("artifact_id")==rows[i].artifact_id and d.get("item_id")==rows[i].item_id,"Objects lookup target differs")
				check(d.get("position")==rows[i].get("position"),"Objects fresh position differs");lookups+=1
		var stale:=await page(tab,0,revision+1)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("objects",{}).get("outcome")==C.ObjectsOutcome.Stale,"Objects stale revision accepted")
		var missing:=await locate(tab,2147483647,revision)
		check(missing.get("status")==C.ManagementStatus.Rejected and missing.get("objects",{}).get("outcome")==C.ObjectsOutcome.Stale,"Objects foreign target accepted")
		counts.append(rows.size())
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"counts":counts,"lookups":lookups,"stale_tabs":4}));result.close()
	quit(1 if failed else 0)
