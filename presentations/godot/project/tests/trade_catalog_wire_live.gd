extends "res://tests/machinery_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Trade catalog attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-catalog-wire-expected.json"))
	var intent: Dictionary={"action":C.ManagementAction.TradeCatalogRead,"depot_id":int(expected.depot_id)}
	for patch in [{"depot_id":-1},{"depot_id":1.5},{"unexpected":1}]:
		var invalid: Dictionary=intent.duplicate(true);invalid.merge(patch,true)
		check(world.management_request("trade_catalog",invalid)==0,"Malformed catalog reached transport")
	var tokens: Array=[]
	var responses: Array=[]
	for iteration in range(2):
		var response:=await request("trade_catalog",intent)
		if not check(response.get("status")==C.ManagementStatus.Ok and response.has("trade_catalog"),"Catalog transport failed: "+str(response.get("message",""))):break
		var value: Dictionary=response.trade_catalog
		check(value.depot_id==expected.depot_id and value.title==expected.title and value.from_text==expected.from,"Catalog header changed")
		check(value.choices.size()==expected.choices.size(),"Catalog choice count changed")
		for i in range(mini(value.choices.size(),expected.choices.size())):
			var row: Dictionary=value.choices[i];var native: Dictionary=expected.choices[i]
			check(row.entity_id==native.entity and row.race==native.race and row.name==native.name,"Catalog caption/order changed")
			check(typeof(row.token)==TYPE_INT and row.token>0 and not tokens.has(row.token),"Catalog token duplicated or coerced")
			tokens.append(row.token)
		responses.append(value)
	var unavailable:=await request("trade_catalog",{"action":C.ManagementAction.TradeCatalogRead,"depot_id":2147483647})
	check(unavailable.get("status")==C.ManagementStatus.Rejected and not unavailable.has("trade_catalog"),"Missing depot did not reject")
	var file:=FileAccess.open(directory+"/trade-catalog-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"responses":responses}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
