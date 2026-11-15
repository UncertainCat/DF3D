extends "res://tests/item_carrier_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Machinery contract bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Machinery contract catalog failed"):quit(1);return
	var read={"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":61}
	var before:=await request("production",read)
	var header: Dictionary=before.get("production",{}).get("building_header",{}).get("snapshot",{})
	if check(preload("res://scripts/building_header_state.gd").valid_snapshot(header,61),"Existing header incompatible with new protocol"):
		for desired in [0,1]:
			var result:=await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":61,
				"expected_revision":header.revision,"farm_operation":C.FarmOperation.PumpManual,"item_value":desired})
			check(result.get("status")==C.ManagementStatus.Rejected and result.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Rejected,"Pump setting accepted on a lever")
		var after:=await request("production",read)
		check(after.get("production",{}).get("building_header",{}).get("snapshot",{})==header,"Rejected pump setting changed lever")
	var file:=FileAccess.open(directory+"/machinery-contract-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"legacy_header":true,"unsupported_pump_rejected":true}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
