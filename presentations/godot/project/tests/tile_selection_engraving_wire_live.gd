extends "res://tests/tile_selection_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var sample: Dictionary=expected.tile_selection_reference.engraving
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Engraving bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var p: Array=sample.tile
	var response:=await request("selection",{"action":C.ManagementAction.Selection,"operation":OP.OpenTile,"origin":Vector3i(p[0],p[1],p[2])})
	check(response.get("status")==C.ManagementStatus.Ok,"Engraving selection rejected")
	var page: Dictionary=response.get("selection",{})
	if page.get("kind")!=KIND.Engraving:
		for i in page.get("alternatives",[]).size():
			if page.alternatives[i].kind==KIND.Engraving:
				response=await selection(OP.SelectAlternative,page.receipt,i);page=response.get("selection",{});break
	check(page.get("kind")==KIND.Engraving and page.get("id")==-1,"Engraving identity missing")
	check(page.get("title")==sample.title and page.get("description")==sample.description,"Engraving wire text differs from native")
	var first: Dictionary=page.duplicate(true)
	if page.has("receipt"):
		response=await selection(OP.Inspect,page.receipt)
		check(response.get("status")==C.ManagementStatus.Ok and response.get("selection",{}).get("description")==sample.description,"Repeated engraving inspection differs")
		response=await selection(OP.Back,page.receipt)
		check(response.get("status")==C.ManagementStatus.Ok and not response.get("selection",{}).get("open",true),"Engraving Back failed")
		response=await selection(OP.Inspect,page.receipt)
		check(response.get("status")==C.ManagementStatus.Rejected,"Retired engraving receipt accepted")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"engraving":first,"retired_receipt_rejected":true}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
