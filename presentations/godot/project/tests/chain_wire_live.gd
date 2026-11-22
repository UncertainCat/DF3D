extends "res://tests/item_carrier_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/chain-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Chain bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Chain catalog failed"):quit(1);return
	var id: int=int(expected.id)
	var header_response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":id})
	var header: Dictionary=header_response.get("production",{}).get("building_header",{}).get("snapshot",{})
	if not check(header.get("type")==27 and header.has("cage"),"Chain header unavailable: "+str(header_response)):quit(1);return
	check(not header.cage.glass and not header.cage.aquarium and not header.cage.justice_restraint,"Unexpected chain controls")
	var read={"action":C.ManagementAction.ProductionInspect,"cage_operation":0,"building_id":id,"cage_sort":2,"cage_columns":26}
	var response:=await request("production",read)
	var initial: Dictionary=response.get("production",{}).get("cage",{})
	if not check(response.get("status")==C.ManagementStatus.Ok,"Chain picker read failed: "+str(response)):quit(1);return
	check(initial.rows.size()==expected.order.size(),"Chain row count differs")
	for i in mini(initial.rows.size(),expected.order.size()):check(initial.rows[i].id==int(expected.order[i]) and not initial.rows[i].assigned,"Native chain Category order differs")
	var select={"action":C.ManagementAction.ProductionQueue,"cage_operation":1,"building_id":id,"cage_sort":2,"cage_columns":26,
		"expected_revision":initial.revision,"cage_candidate_id":int(expected.unit_id),"cage_entity":1,"cage_assigned":true}
	var selected:=await request("production",select)
	if not check(selected.get("status")==C.ManagementStatus.Ok and selected.production.cage.outcome==C.FarmEditOutcome.Completed,"Chain selection uncertain; no replay: "+str(selected)):quit(1);return
	var parent_read={"action":C.ManagementAction.ProductionInspect,"cage_operation":2,"building_id":id}
	var body_response:=await request("production",parent_read)
	var body: Dictionary=body_response.get("production",{}).get("cage",{})
	if not check(body_response.get("status")==C.ManagementStatus.Ok and body.get("occupants",[]).size()==1,"Chain body unavailable: "+str(body_response)):quit(1);return
	var row: Dictionary=body.occupants[0]
	check(row.id==int(expected.unit_id) and row.name==expected.name and row.status=="Assigned" and row.assigned and not row.contained,"Chain body differs from native")
	check(row.get("appearance",{}).get("layers",[]).size()>0,"Chain occupant artwork missing")
	var remove={"action":C.ManagementAction.ProductionQueue,"cage_operation":3,"building_id":id,
		"expected_revision":body.revision,"cage_candidate_id":int(expected.unit_id),"cage_entity":1,"cage_assigned":false}
	var removed:=await request("production",remove)
	if not check(removed.get("status")==C.ManagementStatus.Ok and removed.production.cage.outcome==C.FarmEditOutcome.Completed and removed.production.cage.occupants.is_empty(),"Chain removal uncertain; no replay: "+str(removed)):quit(1);return
	var stale:=await request("production",remove)
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.production.cage.outcome==C.FarmEditOutcome.Stale,"Chain stale removal was not rejected")
	var final:=await request("production",read)
	check(final.get("status")==C.ManagementStatus.Ok and final.production.cage.rows==initial.rows and final.production.cage.revision==initial.revision,"Chain round trip did not restore picker")
	var file:=FileAccess.open(directory+"/chain-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"header":header,"initial":initial,"body":body,"removed":removed.production.cage}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
