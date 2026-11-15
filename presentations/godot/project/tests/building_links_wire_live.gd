extends "res://tests/item_carrier_wire_live.gd"

func links(id: int,cursor: int=0,revision: int=0) -> Dictionary:
	return await request("production",{"action":C.ManagementAction.ProductionInspect,"building_links":true,
		"building_id":id,"cursor":cursor,"expected_revision":revision})

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/building-links-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Building links attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var receipts: Array=[]
	for building in expected.buildings:
		var native: Dictionary=building.provider
		var reply:=await links(int(building.id))
		if not check(reply.get("status")==C.ManagementStatus.Ok,"Building links read rejected"):break
		var page: Dictionary=reply.get("production",{}).get("building_links",{})
		if not check(not page.is_empty(),"Building links response missing"):break
		check(page.building_id==int(building.id) and page.tabs==native.tabs and page.total==native.rows.size(),"Building links page identity differs")
		check(page.revision==int(native.revision) and page.cursor==0 and page.next_cursor==0,"Building links receipt differs")
		check(page.rows.size()==native.rows.size(),"Building links row count differs")
		for i in mini(page.rows.size(),native.rows.size()):
			for field in ["id","type","item_id","reference_type","x","y","z","name"]:
				check(page.rows[i].get(field)==native.rows[i].get(field),"Building links field differs: "+field)
		if page.total>1:
			var continuation:=await links(int(building.id),1,page.revision)
			check(continuation.get("status")==C.ManagementStatus.Ok,"Building links continuation rejected")
			check(continuation.get("production",{}).get("building_links",{}).get("rows",[])==page.rows.slice(1),"Building links continuation changed order")
		var stale:=await links(int(building.id),0,page.revision+1)
		check(stale.get("status")==C.ManagementStatus.Rejected and not stale.get("production",{}).has("building_links"),"Stale building links retained authority")
		receipts.append(page)
	var empty:=await links(65)
	var empty_page: Dictionary=empty.get("production",{}).get("building_links",{})
	check(empty.get("status")==C.ManagementStatus.Ok and not empty_page.get("tabs",true) and empty_page.get("total",-1)==0,"Unlinked chair acquired tabs")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"pages":receipts,"empty":empty_page}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
