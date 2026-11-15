extends "res://tests/lever_wire_live.gd"
func lever(op: int,revision: int=0,extra: Dictionary={}) -> Dictionary:
	var intent: Dictionary={"action":C.ManagementAction.ProductionQueue if op>=2 else C.ManagementAction.ProductionInspect,
		"building_id":61,"lever_operation":op,"expected_revision":revision}
	intent.merge(extra)
	var result:=await request("production",intent);receipts.append(result);return result
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/pressure-plate-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Plate attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var initial:=await lever(0)
	var state: Dictionary=initial.get("production",{}).get("lever",{})
	if not check(initial.get("status")==C.ManagementStatus.Ok and not state.is_empty(),"Plate read rejected"):quit(1);return
	check(state.source_mechanism==int(expected.source_mechanism) and state.target_mechanism==int(expected.target_mechanism),"Plate initial mechanism order differs")
	check(not state.source_name.is_empty() and not state.target_name.is_empty(),"Plate mechanism captions missing")
	var selection: Dictionary={"lever_x":int(expected.x),"lever_y":int(expected.y),"lever_z":int(expected.z),
		"lever_source_mechanism":state.source_mechanism,"lever_target_mechanism":state.target_mechanism}
	var preview:=await lever(1,state.revision,selection)
	check(preview.get("production",{}).get("lever",{}).get("target_id",-1)==int(expected.target_id),"Plate target preview differs")
	var pull:=await lever(2,state.revision)
	check(pull.get("production",{}).get("lever",{}).get("outcome")==2,"Plate Pull was not rejected")
	selection.lever_target_id=int(expected.target_id)
	var stale:=await lever(3,state.revision+1,selection)
	check(stale.get("status")==C.ManagementStatus.Rejected,"Stale plate Link accepted")
	var link:=await lever(3,state.revision,selection)
	var linked: Dictionary=link.get("production",{}).get("lever",{})
	if not check(linked.get("outcome")==1 and linked.get("job_id",-1)>=0,"Plate Link not confirmed"):quit(1);return
	var old:=await lever(3,state.revision,selection)
	check(old.get("status")==C.ManagementStatus.Rejected,"Old plate revision retained authority")
	var duplicate:=await lever(3,linked.revision,selection)
	check(duplicate.get("production",{}).get("lever",{}).get("outcome")==2,"Duplicate plate Link accepted")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts,"link_job":linked.job_id}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
