extends "res://tests/machinery_wire_live.gd"
func mode(id: int,revision: int,desired: int) -> Dictionary:
	return await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":id,"expected_revision":revision,"farm_operation":C.FarmOperation.DepotMode,"item_value":desired})
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Depot bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Depot catalog failed"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-wire-expected.json"))
	# No caravan is present in this settings fixture, so goods are unavailable.
	var goods:=await request("depot_goods",{"action":C.ManagementAction.DepotGoodsRead,"depot_id":int(expected.id),"category":-1,"query":"","sort_by_distance":true,"pending_on_top":true,"exclude_prohibited":false,"item_ids":[]})
	check(goods.get("status")==C.ManagementStatus.Rejected and not goods.has("depot_goods"),"Unavailable depot goods read did not reject")
	var before:=await header(int(expected.id))
	if not before.is_empty():
		check(before.type==6 and not before.depot.requested and not before.depot.anyone,"Unexpected depot baseline")
		var current: Dictionary=before
		for desired in [0,1,0,2,1,2,0,2]:
			var stale:=await mode(before.id,current.revision+1,desired)
			check(stale.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Stale,"Stale depot mode accepted")
			var result:=await mode(before.id,current.revision,desired)
			var receipt: Dictionary=result.get("production",{}).get("building_header",{})
			if not check(receipt.get("outcome")==C.FarmEditOutcome.Completed,"Depot mode failed: "+str(result)):break
			current=receipt.snapshot
			check(current.depot.requested==(desired!=2),"Wrong trader request flag")
			if desired!=2:check(current.depot.anyone==(desired==1),"Wrong broker/anyone mode")
			var duplicate:=await mode(before.id,current.revision,desired)
			check(duplicate.get("production",{}).get("building_header",{}).get("snapshot",{})==current,"Duplicate depot mode changed authority")
		check(current==before,"Depot state not restored")
	var f:=FileAccess.open(directory+"/depot-wire-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"success":not failed}));f.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
