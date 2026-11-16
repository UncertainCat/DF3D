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
	if not check(world.attach(),"Trade artwork attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=preload("res://scripts/trade_goods_state.gd").new();model.configure(service)
	var pages: Array=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-goods-art-expected.json")))
	var ids: Array=[]
	for side in range(2):
		pages[side].side=side;pages[side].offset=0;pages[side].query=""
		for row in pages[side].rows:
			if not row.group:ids.append(row.id)
	model.pages=pages;model.phase=model.Phase.Active;model.request_appearances(ids)
	deadline=Time.get_ticks_msec()+10000
	while model.appearance_pending() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(not model.appearance_pending(),"Trade artwork read timed out")
	for id in ids:
		var appearance: Dictionary=model.appearances.get(id,{})
		check(not appearance.is_empty(),"Trade artwork absent for "+str(id))
		if model.item_type(id)==57 and int(appearance.get("flags",0))&64:
			check(appearance.has("web") and int(appearance.web.pattern)>=0 and int(appearance.web.pattern)<=3,"Native web facts absent")
	var file:=FileAccess.open(directory+"/trade-goods-art-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"count":ids.size(),"pages":pages,"appearances":model.appearances}));file.close()
	model.dispose();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)
