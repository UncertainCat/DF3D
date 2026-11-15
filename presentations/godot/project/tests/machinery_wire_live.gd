extends "res://tests/item_carrier_wire_live.gd"
func header(id: int) -> Dictionary:
	var result:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":id})
	var value: Dictionary=result.get("production",{}).get("building_header",{}).get("snapshot",{})
	check(result.get("status")==C.ManagementStatus.Ok and preload("res://scripts/building_header_state.gd").valid_snapshot(value,id),"Machinery header unavailable: "+str(id))
	return value
func set_pump(id: int,revision: int,desired: int) -> Dictionary:
	return await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":id,
		"expected_revision":revision,"farm_operation":C.FarmOperation.PumpManual,"item_value":desired})
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Machinery bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Machinery catalog failed"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/machinery-wire-expected.json"))
	var observed:=0
	for entry in expected.buildings:
		if int(entry.type)==13:continue
		var before:=await header(int(entry.id))
		if before.is_empty():break
		var semantic: Dictionary=entry.semantic.duplicate(true)
		for field in ["machine_id","produced","required","status","pump_manual","pump_direction"]:semantic[field]=int(semantic[field])
		check(before.machinery==semantic,"Machinery semantic facts changed across wire: "+str(entry.type)+" observed="+str(before.machinery)+" expected="+str(semantic));observed+=1
		if int(entry.type)!=33:continue
		var original: int=before.machinery.pump_manual
		var stale:=await set_pump(before.id,before.revision+1,1-original)
		check(stale.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Stale,"Stale pump setting accepted")
		var result:=await set_pump(before.id,before.revision,1-original)
		var receipt: Dictionary=result.get("production",{}).get("building_header",{})
		if not check(receipt.get("outcome")==C.FarmEditOutcome.Completed,"Pump setting failed"):break
		var changed: Dictionary=receipt.snapshot
		check(changed.machinery.pump_manual==1-original,"Pump flag did not change")
		var duplicate:=await set_pump(before.id,before.revision,1-original)
		check(duplicate.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Stale,"Old pump revision replayed")
		var same:=await set_pump(before.id,changed.revision,1-original)
		check(same.get("production",{}).get("building_header",{}).get("snapshot",{})==changed,"Already-set pump changed authority")
		result=await set_pump(before.id,changed.revision,original)
		check(result.get("production",{}).get("building_header",{}).get("snapshot",{})==before,"Pump state not restored")
	var lever:=await header(61)
	if not lever.is_empty():
		var wrong:=await set_pump(61,lever.revision,1)
		check(wrong.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Rejected,"Lever accepted pump setting")
	check(observed==7,"Missing machinery observations")
	var file:=FileAccess.open(directory+"/machinery-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"observed":observed,"pump_restored":true}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
