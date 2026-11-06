extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-list-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Residents bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Residents catalog failed"):quit(1);return
	var results: Array=[]
	var sorts: Dictionary={"initial":0,"Cat":0,"Name":1,"Prof":2,"Stress":3,"Job":4}
	for snapshot: Dictionary in expected.snapshots:
		var label: String=snapshot.name
		var query: String=snapshot.get("query","")
		var intent: Dictionary={"action":C.ManagementAction.ResidentsQuery,"sort":sorts[label.get_slice("-",0)],"descending":label.ends_with("-2"),"query_bytes":query.to_utf8_buffer()}
		var response:=await request("residents",intent)
		var ids: PackedInt32Array=response.get("residents",{}).get("unit_ids",PackedInt32Array())
		var matches: bool=response.get("status")==C.ManagementStatus.Ok and response.has("residents") and ids==PackedInt32Array(snapshot.ids)
		check(matches,"Residents wire differs: "+label)
		results.append({"name":label,"count":ids.size(),"matches":matches})
	for bad: Dictionary in [
		{"action":C.ManagementAction.ResidentsQuery,"sort":5,"descending":false,"query_bytes":PackedByteArray()},
		{"action":C.ManagementAction.ResidentsQuery,"sort":0,"descending":false,"query_bytes":PackedByteArray([0])},
		{"action":C.ManagementAction.ResidentsQuery,"sort":0,"descending":false,"query_bytes":[]},
	]:
		check(world.management_request("residents",bad)==0,"Malformed Residents query accepted")
	var cleared:=await request("construction",{"action":C.ManagementAction.Catalog})
	check(cleared.get("status")==C.ManagementStatus.Ok and not cleared.has("residents"),"Unrelated reply retained Residents result")
	var file:=FileAccess.open(directory+"/residents-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"comparisons":results}));file.close()
	world.queue_free();await process_frame
	quit(1 if failed else 0)
