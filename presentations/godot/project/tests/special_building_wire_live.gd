extends "res://tests/machinery_wire_live.gd"
func edit_header(before: Dictionary,operation: int,fields: Dictionary={}) -> Dictionary:
	var intent={"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":before.id,"expected_revision":before.revision,"farm_operation":operation}
	intent.merge(fields)
	return await request("production",intent)
func confirmed(result: Dictionary) -> Dictionary:
	var state: Dictionary=result.get("production",{}).get("building_header",{})
	if not check(state.get("outcome")==C.FarmEditOutcome.Completed,"Special building edit failed: "+str(result)):return {}
	var value: Dictionary=state.get("snapshot",{})
	check(preload("res://scripts/building_header_state.gd").valid_snapshot(value,value.get("id",-1)),"Invalid special receipt")
	return value
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Special building attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Special building catalog failed"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/special-building-expected.json"))
	var receipts: Array=[]
	for row in expected.buildings:
		var before:=await header(int(row.id))
		if before.is_empty():break
		var kind:=int(row.type)
		if kind==48:
			check(before.nest.claimant_id==int(row.body.claimant_id) and before.nest.name==row.body.name and before.nest.status==row.body.status,"Nest body differs")
			check(before.nest.name_color.color==[2,0,0] and before.nest.name_color.effect==0,"Nest color differs")
		else:
			var operations: Array=[C.FarmOperation.TrapBait] if kind==24 else [C.FarmOperation.HiveInstall,C.FarmOperation.HiveGather]
			for operation in operations:
				var original: int=before.trap.bait_type if kind==24 else int(bool(before.hive.flags & (1 if operation==C.FarmOperation.HiveInstall else 2)))
				var desired: int=48 if kind==24 else 1-original
				var changed:=confirmed(await edit_header(before,operation,{"item_value":desired}))
				if changed.is_empty():break
				check(changed.trap.bait_type==desired if kind==24 else bool(changed.hive.flags & (1 if operation==C.FarmOperation.HiveInstall else 2))==(desired==1),"Wrong special setting")
				var stale:=await edit_header(before,operation,{"item_value":original})
				check(stale.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Stale,"Old specialized revision accepted")
				var restored:=confirmed(await edit_header(changed,operation,{"item_value":original}))
				check(restored==before,"Special setting not restored")
				receipts.append(changed)
		if failed:break
		var renamed:=confirmed(await edit_header(before,C.FarmOperation.Rename,{"farm_name":before.custom_name+"x"}))
		if renamed.is_empty():break
		var restored:=confirmed(await edit_header(renamed,C.FarmOperation.Rename,{"farm_name":before.custom_name}))
		check(restored==before,"Special building rename not restored")
		var removing:=confirmed(await edit_header(restored,C.FarmOperation.Remove))
		if removing.is_empty():break
		check(removing.removing,"Special building removal not queued")
		restored=confirmed(await edit_header(removing,C.FarmOperation.CancelRemoval))
		check(restored==before,"Special building removal not cancelled")
		receipts.append(before)
	check(receipts.size()==6,"Missing specialized transport cases")
	var file:=FileAccess.open(directory+"/special-building-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
