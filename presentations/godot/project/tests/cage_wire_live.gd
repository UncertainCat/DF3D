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
	var read={"action":C.ManagementAction.ProductionInspect,"cage_operation":0,"building_id":int(expected.id),"cage_sort":2}
	var response:=await request("production",read)
	var page: Dictionary=response.get("production",{}).get("cage",{})
	if not check(response.get("status")==C.ManagementStatus.Ok and page.get("revision",0)>0,"Cage read failed: "+str(response)):quit(1);return
	var initial:=page.duplicate(true)
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
	file.store_string(JSON.stringify({"success":not failed,"initial":initial,"search":search,"receipts":receipts}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
