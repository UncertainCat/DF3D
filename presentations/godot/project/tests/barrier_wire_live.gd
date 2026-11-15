extends "res://tests/machinery_wire_live.gd"
func controls(id: int) -> Dictionary:
	return await request("production",{"action":C.ManagementAction.ProductionInspect,"door_controls":true,"building_id":id})
func access(id: int,revision: int,value: bool) -> Dictionary:
	return await request("production",{"action":C.ManagementAction.FarmEdit,"door_controls":true,"building_id":id,"expected_revision":revision,"door_forbidden":int(value)})
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Barrier attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Barrier catalog failed"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/barrier-wire-expected.json"))
	for entry in expected.buildings:
		var id:=int(entry.id)
		var value:=await header(id)
		check(value.get("type")==int(entry.type),"Wrong barrier type")
		var contents:=await request("production",{"action":C.ManagementAction.ProductionInspect,"contents":true,"building_id":id})
		check(contents.get("status")==C.ManagementStatus.Ok,"Barrier contents unavailable")
		var result:=await controls(id)
		if int(entry.type)!=35:
			check(result.get("status")==C.ManagementStatus.Rejected,"Non-hatch accepted access controls");continue
		var before: Dictionary=result.get("production",{}).get("door_controls",{}).get("snapshot",{})
		if not check(not before.is_empty(),"Hatch controls unavailable"):break
		result=await access(id,before.revision+1,not before.forbidden)
		check(result.get("production",{}).get("door_controls",{}).get("outcome")==C.FarmEditOutcome.Stale,"Stale hatch edit accepted")
		result=await access(id,before.revision,not before.forbidden)
		var receipt: Dictionary=result.get("production",{}).get("door_controls",{})
		if not check(receipt.get("outcome")==C.FarmEditOutcome.Completed,"Hatch edit failed"):break
		check(receipt.snapshot.forbidden!=before.forbidden,"Hatch access unchanged")
		var duplicate:=await access(id,before.revision,not before.forbidden)
		check(duplicate.get("production",{}).get("door_controls",{}).get("outcome")==C.FarmEditOutcome.Stale,"Duplicate hatch edit accepted")
		result=await access(id,receipt.snapshot.revision,before.forbidden)
		check(result.get("production",{}).get("door_controls",{}).get("snapshot",{})==before,"Hatch state not restored")
		var removal:=await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":id,"expected_revision":value.revision,"farm_operation":C.FarmOperation.Remove})
		var removed: Dictionary=removal.get("production",{}).get("building_header",{}).get("snapshot",{})
		if not check(removed.get("removing",false),"Hatch removal failed"):break
		result=await access(id,before.revision,not before.forbidden)
		check(result.get("status")==C.ManagementStatus.Rejected,"Removing hatch accepted old access receipt")
		var cancelled:=await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":id,"expected_revision":removed.revision,"farm_operation":C.FarmOperation.CancelRemoval})
		check(cancelled.get("production",{}).get("building_header",{}).get("snapshot",{}).get("removing",true)==false,"Hatch removal not cancelled")
	var f:=FileAccess.open(directory+"/barrier-wire-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"success":not failed}));f.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
