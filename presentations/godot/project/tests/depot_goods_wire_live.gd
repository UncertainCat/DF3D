extends "res://tests/machinery_wire_live.gd"
func integers(value):
	if value is float:return int(value)
	if value is Array:
		var result: Array=[]
		for entry in value:result.append(integers(entry))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=integers(value[key])
		return result
	return value
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Depot goods attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Depot goods catalog failed"):quit(1);return
	var expected: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-goods-wire-expected.json")))
	var intent: Dictionary=expected.request;intent.action=C.ManagementAction.DepotGoodsRead
	var response:=await request("depot_goods",intent)
	var snapshot: Dictionary=response.get("depot_goods",{})
	if check(response.get("status")==C.ManagementStatus.Ok and not snapshot.is_empty(),"Depot goods snapshot unavailable: "+str(response)):
		check(snapshot.depot_id==intent.depot_id and snapshot.category==intent.category and snapshot.revision>0,"Depot goods identity differs")
		for key in ["categories","groups","items"]:check(snapshot[key]==expected[key],"Depot goods "+key+" differs: "+str(snapshot[key]))
		var again:=await request("depot_goods",intent)
		check(again.get("depot_goods",{})==snapshot,"Repeated paused read changed source revision")
		var categories: Dictionary=intent.duplicate(true);categories.category=-1;categories.item_ids=[]
		var overview:=await request("depot_goods",categories)
		var value: Dictionary=overview.get("depot_goods",{})
		check(value.get("categories")==snapshot.categories and value.get("revision")==snapshot.revision and value.get("groups")==[] and value.get("items")==[],"Depot category-only read differs")
	for patch in [{"depot_id":2147483647},{"item_ids":[2147483647]}]:
		var invalid: Dictionary=intent.duplicate(true);invalid.merge(patch,true)
		var rejection:=await request("depot_goods",invalid)
		check(rejection.get("status")==C.ManagementStatus.Rejected and not rejection.has("depot_goods"),"Invalid depot target retained a snapshot")
	var file:=FileAccess.open(directory+"/depot-goods-wire-"+str(expected.label)+"-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"label":expected.label,"snapshot":snapshot}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
