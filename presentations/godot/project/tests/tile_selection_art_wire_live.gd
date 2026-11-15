extends "res://tests/tile_selection_wire_live.gd"
func art_read(receipt_value: int,page: int=-1,revision: int=0,extra: Dictionary={}) -> Dictionary:
	var art: Dictionary={"page":page};art.merge(extra)
	return await request("selection_art",{"action":C.ManagementAction.SelectionArtRead,"receipt":receipt_value,"expected_revision":revision,"art":art})
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var sample: Dictionary=expected.tile_selection_reference.engraving.planned
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Artwork bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var p: Array=sample.tile
	var response:=await request("selection",{"action":C.ManagementAction.Selection,"operation":OP.OpenTile,"origin":Vector3i(p[0],p[1],p[2])})
	if not check(response.get("status")==C.ManagementStatus.Ok and response.get("selection",{}).get("kind")==KIND.PlannedEngraving,"Planned engraving missing"):quit(1);return
	var receipt_value: int=response.selection.receipt
	response=await art_read(receipt_value)
	if not check(response.get("status")==C.ManagementStatus.Ok,"Artwork root rejected"):quit(1);return
	var initial: Dictionary=response.selection_art
	check(initial.art.caption==sample.image.header and initial.art.rows.size()==6,"Artwork root differs from native")
	response=await art_read(receipt_value,2,initial.revision)
	if not check(response.get("status")==C.ManagementStatus.Ok,"Site page rejected"):quit(1);return
	var sites: Dictionary=response.selection_art
	var native_sites: Dictionary=sample.image.choices[1]
	check(sites.art.total==native_sites.choices.size(),"Site count differs")
	for i in sites.art.rows.size():check(sites.art.rows[i].id==native_sites.choices[i].id,"Site order differs")
	response=await art_read(receipt_value,2,initial.revision,{"cursor":128,"expected_list_revision":sites.art.list_revision})
	check(response.get("status")==C.ManagementStatus.Ok and response.get("selection_art",{}).get("art",{}).get("rows",[]).size()==128,"Site continuation failed")
	var selected_site: int=sites.art.rows[0].id
	var intent: Dictionary={"action":C.ManagementAction.SelectionArtApply,"receipt":receipt_value,"expected_revision":initial.revision,"art":{"page":2,"subject":selected_site,"expected_list_revision":sites.art.list_revision}}
	response=await request("selection_art",intent)
	check(response.get("status")==C.ManagementStatus.Ok and response.get("selection_art",{}).get("applied",false),"Site assignment failed")
	response=await request("selection_art",intent)
	check(response.get("status")==C.ManagementStatus.Rejected,"Stale assignment accepted")
	response=await art_read(receipt_value,-1,initial.revision)
	check(response.get("status")==C.ManagementStatus.Rejected,"Stale artwork read accepted")
	response=await art_read(receipt_value)
	check(response.get("status")==C.ManagementStatus.Ok,"Fresh artwork read rejected")
	await selection(OP.Back,receipt_value)
	response=await art_read(receipt_value)
	check(response.get("status")==C.ManagementStatus.Rejected,"Retired selection read accepted")
	response=await request("selection_art",intent)
	check(response.get("status")==C.ManagementStatus.Rejected,"Retired selection edit accepted")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"selected_site":selected_site,"root":initial,"site_page":sites,"stale_and_retired_rejected":true}));file.close()
	world.detach_live();world.queue_free();await process_frame;quit(1 if failed else 0)
