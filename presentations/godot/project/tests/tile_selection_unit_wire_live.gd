extends "res://tests/tile_selection_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var sample: Dictionary=expected.tile_selection_reference.unit_group
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Unit-group bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var response:=await request("selection",{"action":C.ManagementAction.Selection,"operation":OP.OpenTile,"origin":Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])})
	var page: Dictionary=response.get("selection",{})
	if check(response.get("status")==C.ManagementStatus.Ok and page.get("kind")==KIND.UnitList,"Unit group did not open"):
		check(page.members.size()==sample.native.units.size(),"Unit group count differs")
		for i in mini(page.members.size(),sample.native.units.size()):
			var row: Dictionary=page.members[i]
			check(row.kind==KIND.Unit and row.id==int(sample.native.units[i]),"Unit group order differs")
			check(row.name==sample.names[str(row.id)],"Native unit-group caption differs")
			check(row.has("unit_appearance"),"Recorded unit row lacks appearance")
		response=await selection(OP.SelectMember,page.receipt,0)
		check(response.get("status")==C.ManagementStatus.Ok and response.get("selection",{}).get("id")==int(sample.member.id),"Native unit member destination differs")
		var stale:=await selection(OP.SelectMember,page.receipt,0)
		check(stale.get("status")==C.ManagementStatus.Rejected,"Old unit-group receipt accepted")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"selections":[page]}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
