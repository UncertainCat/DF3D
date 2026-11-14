extends "res://tests/item_carrier_wire_live.gd"
var shop: int
var pile: int
func read_links() -> Dictionary:
	var result:=await request("areas",{"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.Links,"kind":2,"id":shop})
	check(result.get("status")==C.ManagementStatus.Ok,"Workshop links read failed")
	return result.get("area",{})
func edit(give: bool,unlink: bool,revision: int) -> Dictionary:
	var observed:=await request("areas",{"action":C.ManagementAction.AreaInspect,"kind":0,"id":pile})
	if not check(observed.get("status")==C.ManagementStatus.Ok and observed.get("areas",[]).size()==1,"Destination pile read failed"):return {}
	return await request("areas",{"action":C.ManagementAction.AreaLink,"operation":C.AreaOperation.WorkshopLink,"kind":2,"id":shop,"link_id":pile,"give":give,"unlink":unlink,"expected_revision":observed.areas[0].revision,"expected_list_revision":revision})
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	shop=int(expected.building_id);pile=int(expected.connections_reference.pile_id)
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Workshop links attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var initial:=await read_links()
	if not check(initial.get("links",[]).size()==1 and initial.links[0].id==pile and initial.links[0].direction==1,"Native Give list differs"):quit(1);return
	var point: Dictionary=expected.connections_reference.pile_tile
	for give in [true,false]:
		var picked:=await request("areas",{"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LinkTarget,"kind":2,"id":shop,"give":give,"origin":Vector3i(point.x,point.y,point.z),"expected_revision":initial.list_revision})
		check(picked.get("status")==C.ManagementStatus.Ok and picked.get("area",{}).get("links",[]).size()==(0 if give else 1),"Workshop pick did not preserve duplicate/direction rules")
	var changed:=await edit(false,false,initial.list_revision)
	check(changed.get("status")==C.ManagementStatus.Ok,"Take reversal failed")
	var taken:=await read_links()
	if not check(taken.get("links",[]).size()==1 and taken.links[0].id==pile and taken.links[0].direction==2,"Take list differs"):quit(1);return
	var stale:=await edit(true,false,initial.list_revision)
	check(stale.get("status")==C.ManagementStatus.Rejected,"Stale workshop link receipt accepted")
	var removed:=await edit(false,true,taken.list_revision)
	check(removed.get("status")==C.ManagementStatus.Ok,"Workshop unlink failed")
	var empty:=await read_links();check(empty.get("links",[]).is_empty(),"Unlink retained row")
	var restored:=await edit(true,false,empty.list_revision)
	check(restored.get("status")==C.ManagementStatus.Ok,"Workshop Give restoration failed")
	var final:=await read_links();check(final.get("links",[])==initial.links,"Restored native list differs")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"initial":initial,"taken":taken,"empty":empty,"restored":final}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
