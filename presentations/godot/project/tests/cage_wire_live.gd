extends "res://tests/item_carrier_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/cage-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Cage bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Cage catalog failed"):quit(1);return
	if expected.get("glass",false):
		await glass_settings(int(expected.id));return
	var read={"action":C.ManagementAction.ProductionInspect,"cage_operation":0,"building_id":int(expected.id),"cage_sort":2}
	var response:=await request("production",read)
	var page: Dictionary=response.get("production",{}).get("cage",{})
	if not check(response.get("status")==C.ManagementStatus.Ok and page.get("revision",0)>0,"Cage read failed: "+str(response)):quit(1);return
	var initial:=page.duplicate(true)
	# Protocol migration: the parent provider remains staged; neither operation
	# may fall through to the picker's different assignment callback.
	for operation in [2,3]:
		var intent={"action":C.ManagementAction.ProductionInspect if operation==2 else C.ManagementAction.ProductionQueue,
			"building_id":int(expected.id),"expected_revision":initial.revision,"cage_operation":operation}
		if operation==3:intent.merge({"cage_candidate_id":5969,"cage_entity":2,"cage_assigned":false})
		var rejected:=await request("production",intent)
		var value: Dictionary=rejected.get("production",{}).get("cage",{})
		check(rejected.get("status")==C.ManagementStatus.Rejected and value.get("revision",-1)==0 and value.get("occupants",[1]).is_empty(),"Staged parent intent gained picker authority")
	var parent_response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":int(expected.id)})
	var parent: Dictionary=parent_response.get("production",{}).get("building_header",{}).get("snapshot",{})
	if not check(parent_response.get("status")==C.ManagementStatus.Ok and parent.get("type")==28 and parent.has("cage"),"Cage parent read failed: "+str(parent_response)):quit(1);return
	check(not parent.cage.glass and not parent.cage.justice_restraint,"Expected ordinary lead cage")
	check(parent.cage.room.room_id==259 and parent.cage.room.room_type==87 and parent.cage.room.name=="Unnamed memorial hall" and parent.cage.room.introduction=="This furniture is a part of","Cage room facts differ from native")
	check(parent.cage.room.location_type==2 and parent.cage.room.location_tier==1 and parent.cage.room.location_has_contents,"Cage room temple facts differ from native")
	var unavailable:=await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":int(expected.id),"expected_revision":parent.revision,"farm_operation":C.FarmOperation.CageAquarium,"item_value":1})
	check(unavailable.get("status")==C.ManagementStatus.Rejected and unavailable.get("production",{}).get("building_header",{}).get("outcome")==C.FarmEditOutcome.Rejected,"Non-glass cage setting must reject without effects")
	check(page.rows.size()==expected.rows.size() and page.next_cursor==0,"Cage rows missing")
	for native in expected.rows:
		var matches: Array=page.rows.filter(func(row):return row.id==int(native.id) and row.entity==int(native.kind)+1)
		check(matches.size()==1 and matches[0].assigned==native.assigned,"Cage membership differs")
	var searched: Dictionary=read.duplicate();searched.query="Stray";searched.cage_sort=1;searched.cage_descending=true
	var search_response:=await request("production",searched)
	var search: Dictionary=search_response.get("production",{}).get("cage",{})
	check(search_response.get("status")==C.ManagementStatus.Ok and search.get("total")==6,"Native cage search failed")
	var receipts: Array=[]
	for edit in [{"entity":1,"id":6960,"assigned":true},{"entity":1,"id":6960,"assigned":false},{"entity":2,"id":5969,"assigned":false},{"entity":2,"id":5969,"assigned":true}]:
		var intent={"action":C.ManagementAction.ProductionQueue,"cage_operation":1,"building_id":int(expected.id),"cage_sort":2,
			"expected_revision":page.revision,"cage_candidate_id":edit.id,"cage_entity":edit.entity,"cage_assigned":edit.assigned}
		var applied:=await request("production",intent)
		var receipt: Dictionary=applied.get("production",{}).get("cage",{})
		if not check(applied.get("status")==C.ManagementStatus.Ok and receipt.get("outcome")==C.FarmEditOutcome.Completed,"Cage edit uncertain/rejected; no replay: "+str(applied)):quit(1);return
		var matches: Array=receipt.rows.filter(func(row):return row.id==edit.id and row.entity==edit.entity)
		check(matches.size()==1 and matches[0].assigned==edit.assigned,"Cage edit receipt differs")
		var stale: Dictionary=intent.duplicate();stale.cage_assigned=not edit.assigned
		var rejected:=await request("production",stale)
		check(rejected.get("status")==C.ManagementStatus.Rejected and rejected.get("production",{}).get("cage",{}).get("outcome")==C.FarmEditOutcome.Stale,"Stale cage edit was not refused")
		page=receipt;receipts.append(receipt)
	check(page.rows==initial.rows and page.revision==initial.revision,"Cage wire toggles did not restore original facts")
	var file:=FileAccess.open(directory+"/cage-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"parent":parent,"initial":initial,"search":search,"receipts":receipts}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func glass_settings(id: int) -> void:
	var response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":id})
	var parent: Dictionary=response.get("production",{}).get("building_header",{}).get("snapshot",{})
	if not check(parent.get("cage",{}).get("glass",false),"Glass parent absent"):quit(1);return
	var receipts: Array=[]
	for aquarium in [true,false]:
		response=await request("production",{"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":id,"expected_revision":parent.revision,"farm_operation":C.FarmOperation.CageAquarium,"item_value":int(aquarium)})
		var header: Dictionary=response.get("production",{}).get("building_header",{})
		if not check(response.get("status")==C.ManagementStatus.Ok and header.get("outcome")==C.FarmEditOutcome.Completed,"Glass setting failed: "+str(response)):quit(1);return
		parent=header.snapshot
		check(parent.cage.aquarium==aquarium,"Glass receipt differs");receipts.append(parent)
	var file:=FileAccess.open(directory+"/cage-glass-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
