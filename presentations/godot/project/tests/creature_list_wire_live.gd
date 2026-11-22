extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/creature-tabs-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Creature list bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Creature list catalog failed"):quit(1);return
	var results: Array=[]
	for snapshot: Dictionary in expected:
		var tab:=int(snapshot.tab)
		if tab==0:continue
		var intent: Dictionary={"action":C.ManagementAction.CreatureListQuery,"tab":tab,"sort":0,"descending":false,"query_bytes":str(snapshot.query).to_utf8_buffer()}
		var response:=await request("creature_list",intent)
		var value: Dictionary=response.get("creature_list",{})
		var rows: Array=value.get("entries",[])
		var matches: bool=response.get("status")==C.ManagementStatus.Ok and value.get("tab",-1)==tab and rows.size()==snapshot.rows.size()
		for i in mini(rows.size(),snapshot.rows.size()):
			matches=matches and int(rows[i].kind)==int(snapshot.rows[i].kind) and int(rows[i].id)==int(snapshot.rows[i].id)
		check(matches,"Creature list wire differs: tab "+str(tab)+" query "+str(snapshot.query))
		results.append({"tab":tab,"query":snapshot.query,"count":rows.size(),"matches":matches})
	for tab in [0,4]:
		check(world.management_request("creature_list",{"action":C.ManagementAction.CreatureListQuery,"tab":tab,"sort":0,"descending":false,"query_bytes":PackedByteArray()})==0,"Invalid tab admitted")
	for sort in [3,5]:
		check(world.management_request("creature_list",{"action":C.ManagementAction.CreatureListQuery,"tab":2,"sort":sort,"descending":false,"query_bytes":PackedByteArray()})==0,"Invalid Other sort admitted")
	var cleared:=await request("construction",{"action":C.ManagementAction.Catalog})
	check(not cleared.has("creature_list"),"Unrelated reply retained creature list")
	var file:=FileAccess.open(directory+"/creature-list-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"results":results}));file.close()
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)
