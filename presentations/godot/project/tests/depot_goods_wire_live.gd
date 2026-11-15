extends "res://tests/machinery_wire_live.gd"
const GoodsModel=preload("res://scripts/depot_goods_state.gd")
func settle_goods(model,service) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and model.phase==GoodsModel.Phase.Reading:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==GoodsModel.Phase.Ready,"Depot controller did not settle: "+str(model.last_result))
func verify_controller(intent: Dictionary,snapshot: Dictionary) -> Dictionary:
	var service=preload("res://scripts/semantic_action_service.gd").new()
	root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=GoodsModel.new();model.configure(service);model.open(intent.depot_id)
	if await settle_goods(model,service):
		model.select_category(intent.category)
		if await settle_goods(model,service):
			model.set_query(intent.query)
			if await settle_goods(model,service):
				model.set_options(intent.sort_by_distance,intent.pending_on_top,intent.exclude_prohibited)
				if await settle_goods(model,service):
					model.request_items(intent.item_ids)
					if await settle_goods(model,service):
						check(model.category==snapshot.category and model.revision==snapshot.revision,"Controller source identity differs")
						check(model.categories==snapshot.categories and model.groups==snapshot.groups,"Controller projection differs from native")
						check(model.items.size()==snapshot.items.size(),"Controller detail count differs")
						for row in snapshot.items:check(model.items.get(row.id)==row,"Controller detail differs")
						if intent.exclude_prohibited and snapshot.groups.all(func(row):return row.item_ids.is_empty()):check(model.row_count()==0,"Controller exposed native empty-list groups")
	model.request_appearances(intent.item_ids.slice(0,2))
	var artwork_deadline:=Time.get_ticks_msec()+5000
	while model.appearance_pending() and Time.get_ticks_msec()<artwork_deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(not model.appearance_pending(),"Depot artwork inspection timed out")
	var appearances: Dictionary=model.appearances.duplicate(true)
	for id in intent.item_ids.slice(0,2):check(not appearances.get(id,{}).is_empty(),"Depot native appearance unavailable: "+str(id))
	model.close();model.open(intent.depot_id);var retired: int=model.ticket;service.poll(0.01);model.close()
	var deadline:=Time.get_ticks_msec()+5000
	while service.result(retired).is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(service.result(retired).get("status")==C.ManagementStatus.Ok,"Detached depot read did not finish")
	check(model.phase==GoodsModel.Phase.Closed and model.groups.is_empty(),"Late depot reply revived closed picker")
	model.dispose();service.queue_free();await process_frame
	return appearances
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
	var appearances: Dictionary={}
	if check(response.get("status")==C.ManagementStatus.Ok and not snapshot.is_empty(),"Depot goods snapshot unavailable: "+str(response)):
		check(snapshot.depot_id==intent.depot_id and snapshot.category==intent.category and snapshot.revision>0,"Depot goods identity differs")
		for key in ["categories","groups","items"]:check(snapshot[key]==expected[key],"Depot goods "+key+" differs: "+str(snapshot[key]))
		var again:=await request("depot_goods",intent)
		check(again.get("depot_goods",{})==snapshot,"Repeated paused read changed source revision")
		var categories: Dictionary=intent.duplicate(true);categories.category=-1;categories.item_ids=[]
		var overview:=await request("depot_goods",categories)
		var value: Dictionary=overview.get("depot_goods",{})
		check(value.get("categories")==snapshot.categories and value.get("revision")==snapshot.revision and value.get("groups")==[] and value.get("items")==[],"Depot category-only read differs")
		appearances=await verify_controller(intent,snapshot)
	for patch in [{"depot_id":2147483647},{"item_ids":[2147483647]}]:
		var invalid: Dictionary=intent.duplicate(true);invalid.merge(patch,true)
		var rejection:=await request("depot_goods",invalid)
		check(rejection.get("status")==C.ManagementStatus.Rejected and not rejection.has("depot_goods"),"Invalid depot target retained a snapshot")
	var file:=FileAccess.open(directory+"/depot-goods-wire-"+str(expected.label)+"-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"label":expected.label,"snapshot":snapshot,"appearances":appearances}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
