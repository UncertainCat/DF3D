extends "res://tests/item_carrier_wire_live.gd"
const OP=C.SelectionOperation
const KIND=C.SelectionKind
func selection(operation: int,receipt_value:=0,index: int=-1) -> Dictionary:
	var data={"action":C.ManagementAction.Selection,"operation":operation,"receipt":receipt_value}
	if index>=0:data.index=index
	return await request("selection",data)
func ready(owner,service) -> bool:
	var limit:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<limit:
		world.poll();service.poll()
		if owner.phase!=owner.Phase.Reading:return check(owner.phase==owner.Phase.Ready,"Selection owner did not become ready")
		await create_timer(0.01).timeout
	return check(false,"Selection owner timed out")
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Selection bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var results: Array=[]
	for sample in expected.tile_selection_reference.cases:
		var p: Array=sample.tile
		var response:=await request("selection",{"action":C.ManagementAction.Selection,"operation":OP.OpenTile,"origin":Vector3i(p[0],p[1],p[2])})
		if not check(response.get("status")==C.ManagementStatus.Ok,"Selection read rejected"):break
		var page: Dictionary=response.selection;var native: Dictionary=sample.native
		check(page.open and page.kind==int(native.active_kind)+1 and page.id==int(native.active_id),"Native default selection differs")
		check(page.alternatives.size()==native.tabs.size(),"Native alternative count differs")
		for i in mini(page.alternatives.size(),native.tabs.size()):
			check(page.alternatives[i].kind==int(native.tabs[i].kind)+1 and page.alternatives[i].id==int(native.tabs[i].id),"Native alternative order differs")
		var first_receipt: int=page.receipt
		for i in page.alternatives.size():
			if page.alternatives[i].kind!=KIND.ItemList:continue
			response=await selection(OP.SelectAlternative,page.receipt,i)
			if not check(response.get("status")==C.ManagementStatus.Ok,"Group navigation rejected"):break
			page=response.selection
			check(page.kind==KIND.ItemList and page.id==-1 and page.members.size()==native.items.size(),"Item group members missing")
			for j in mini(page.members.size(),native.items.size()):
				check(page.members[j].kind==KIND.Item and page.members[j].id==int(native.items[j]),"Item member order differs")
				if expected.tile_selection_reference.has("item_names"):
					check(page.members[j].name==expected.tile_selection_reference.item_names[str(page.members[j].id)],"Native item group caption differs")
			results.append(page.duplicate(true))
			var group_receipt: int=page.receipt
			response=await selection(OP.SelectMember,page.receipt,page.members.size()-1)
			check(response.get("status")==C.ManagementStatus.Ok,"Member navigation rejected")
			page=response.get("selection",{})
			check(page.get("kind")==KIND.Item and page.get("id")==int(native.items.back()),"Member identity differs")
			var stale:=await selection(OP.SelectMember,group_receipt,0)
			check(stale.get("status")==C.ManagementStatus.Rejected,"Old group receipt accepted")
			break
		var current:=await selection(OP.Inspect,page.receipt)
		check(current.get("status")==C.ManagementStatus.Ok,"Current receipt lost after rejection")
		var closed:=await selection(OP.Back,page.receipt)
		check(closed.get("status")==C.ManagementStatus.Ok and not closed.selection.open,"Back did not retire selection")
		var late:=await selection(OP.Inspect,first_receipt)
		check(late.get("status")==C.ManagementStatus.Rejected,"Closed receipt accepted")
		results.append(page)
	var service=preload("res://scripts/semantic_action_service.gd").new();service.configure(world,true)
	var owner=preload("res://scripts/tile_selection_state.gd").new();owner.configure(service)
	var destinations: Array=[];owner.selected.connect(func(kind,id,tile):destinations.append({"kind":kind,"id":id,"tile":str(tile)}))
	var group_case: Dictionary=expected.tile_selection_reference.cases[2]
	var group_tile: Array=group_case.tile
	owner.open(Vector3i(group_tile[0],group_tile[1],group_tile[2]))
	if await ready(owner,service):
		for index in owner.snapshot.alternatives.size():
			if owner.snapshot.alternatives[index].kind!=KIND.ItemList:continue
			owner.choose_alternative(index)
			if await ready(owner,service):
				owner.choose_member(0)
				if await ready(owner,service):check(owner.snapshot.id==int(group_case.native.items[0]),"Owner handed off wrong member")
			break
	check(destinations.size()==3,"Selection owner did not hand off building, group and member")
	owner.open(Vector3i(group_tile[0],group_tile[1],group_tile[2]));service.poll();owner.close()
	for frame in 20:world.poll();service.poll();await create_timer(0.01).timeout
	check(owner.phase==owner.Phase.Closed and owner.snapshot.is_empty() and destinations.size()==3,"Late reply reopened closed selection")
	owner.dispose();service.free()
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"selections":results,"owner_destinations":destinations}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
