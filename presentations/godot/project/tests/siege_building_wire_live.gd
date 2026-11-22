extends "res://tests/special_building_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Siege attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Siege catalog failed"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/siege-building-expected.json"))
	var receipts: Array=[]
	for row in expected.buildings:
		var before:=await header(int(row.id))
		if before.is_empty():break
		for key in ["type","action","resting","facing"]:check(before.siege[key]==int(row.body[key]),"Siege control differs: "+key)
		if before.siege.type==2:
			for i in 4:check(before.siege[["loaded","available","squads","hunters"][i]]==int(row.body.ammunition[i]),"Siege count differs")
		var operations: Array=[C.FarmOperation.SiegeMode]
		if before.siege.type==2:operations.append(C.FarmOperation.SiegeResting)
		for operation in operations:
			var original: int=before.siege.action if operation==C.FarmOperation.SiegeMode else before.siege.resting
			var desired: int=3 if operation==C.FarmOperation.SiegeMode else (original+1)%8
			var changed:=confirmed(await edit_header(before,operation,{"item_value":desired}))
			if changed.is_empty():break
			check(changed.siege.facing==before.siege.facing,"Siege facing changed")
			check((changed.siege.action if operation==C.FarmOperation.SiegeMode else changed.siege.resting)==desired,"Siege edit wrong value")
			var stale:=await edit_header(before,operation,{"item_value":original})
			check(stale.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Stale,"Old siege revision accepted")
			var restored:=confirmed(await edit_header(changed,operation,{"item_value":original}))
			check(restored==before,"Siege controls not restored")
			receipts.append(changed)
		if failed:break
		var renamed:=confirmed(await edit_header(before,C.FarmOperation.Rename,{"farm_name":before.custom_name+"x"}))
		if renamed.is_empty():break
		var restored:=confirmed(await edit_header(renamed,C.FarmOperation.Rename,{"farm_name":before.custom_name}))
		check(restored==before,"Siege rename not restored")
		var removing:=confirmed(await edit_header(restored,C.FarmOperation.Remove))
		if removing.is_empty():break
		check(removing.removing,"Siege removal not queued")
		restored=confirmed(await edit_header(removing,C.FarmOperation.CancelRemoval))
		check(restored==before,"Siege removal not cancelled")
		receipts.append(before)
	check(receipts.size()==7,"Missing siege transport cases")
	var file:=FileAccess.open(directory+"/siege-building-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
