extends "res://tests/item_carrier_wire_live.gd"
func read_display(id: int,category: int,query: String="",ids: Array=[]) -> Dictionary:
	var result:=await request("display",{"action":C.ManagementAction.DisplayRead,"building_id":id,"category":category,"query":query,"item_ids":ids})
	if not check(result.get("status")==C.ManagementStatus.Ok,"Display read failed: "+str(result)):return {}
	return result.get("display",{})
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/display-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Display attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Display catalog failed"):quit(1);return
	var id:=int(expected.id);var item:=int(expected.item_id)
	var parent:=await read_display(id,-1)
	var initial:=await read_display(id,-2)
	check(initial.get("category")==39 and initial.get("categories",[]).size()==93,"Display initial category differs")
	var page:=await read_display(id,37,"",[item])
	if not page.is_empty():
		check(page.groups.size()==expected.picker.groups.size(),"Display group count differs")
		for i in mini(page.groups.size(),expected.picker.groups.size()):
			var reference: Dictionary=expected.picker.groups[i]
			for key in ["subtype","subcat1","subcat2","amount","expanded","matches","caption"]:check(page.groups[i][key]==reference[key],"Display group differs: "+key)
			check(page.groups[i].item_ids==reference.items.map(func(value):return int(value)),"Display group membership differs")
		check(page.items.size()==1 and page.items[0].has("appearance"),"Display item appearance missing")
		var search:=await read_display(id,37,"steel")
		check(search.get("categories",[]).filter(func(row):return row.matches).size()==17,"Display search categories differ")
		var applied:=await request("display",{"action":C.ManagementAction.DisplayCommit,"building_id":id,"expected_revision":page.inventory_revision,"selected_ids":[item]})
		var assigned: Dictionary=applied.get("display",{})
		if check(assigned.get("outcome")==C.DisplayOutcome.Applied,"Display commit failed: "+str(applied)):
			check(assigned.body.size()==1 and assigned.body[0].id==item and assigned.body[0].status=="Assigned","Display assigned receipt differs")
			var stale:=await request("display",{"action":C.ManagementAction.DisplayRemove,"building_id":id,"expected_revision":parent.revision,"selected_ids":[item]})
			check(stale.get("display",{}).get("outcome")==C.DisplayOutcome.Stale,"Display stale removal accepted")
			var removed:=await request("display",{"action":C.ManagementAction.DisplayRemove,"building_id":id,"expected_revision":assigned.revision,"selected_ids":[item]})
			check(removed.get("display",{}).get("outcome")==C.DisplayOutcome.Applied and removed.display.body.is_empty(),"Display removal failed")
	var file:=FileAccess.open(directory+"/display-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"initial":initial,"page":page}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
