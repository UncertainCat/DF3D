extends "res://tests/item_carrier_wire_live.gd"
func read_stocks(category: int,query: String="",ids: Array=[]) -> Dictionary:
	var reply:=await request("stocks_menu",{"action":C.ManagementAction.StocksMenuRead,"category":category,"query":query,"item_ids":ids})
	check(reply.get("status")==C.ManagementStatus.Ok,"Stocks read failed")
	return reply.get("stocks_menu",{})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/stocks-wire-reference.json"))
	reference.matches=reference.matches.map(func(id):return int(id))
	for group in reference.selection.groups:group.ids=group.ids.map(func(id):return int(id))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Stocks attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var value:=await read_stocks(-1,"iron")
	if not check(value.get("categories",[]).size()==93,"Stocks catalog missing"):quit(1);return
	for i in 93:
		var row: Dictionary=value.categories[i];var type: int=int(reference.order[i])
		check(row.type==type and row.matches==reference.matches.has(type),"Stocks category order/filter differs")
		var native: Dictionary=reference.display[type]
		for key in ["caption","stored","unavailable"]:check(row[key]==native[key],"Stocks category caption differs")
	var ids: Array=reference.selection.groups[0].ids
	value=await read_stocks(39,"",ids)
	if not check(value.get("groups",[]).size()==reference.selection.groups.size(),"Stocks groups missing"):quit(1);return
	for i in value.groups.size():
		var row: Dictionary=value.groups[i];var native: Dictionary=reference.selection.groups[i]
		for key in ["subtype","subcat1","subcat2","amount","caption","flags","expanded"]:check(row[key]==native[key],"Stocks group differs: "+key)
		check(str(row.revision)==native.revision and row.item_ids==native.ids and row.matches==native.on,"Stocks group membership/revision differs")
	check(value.items.size()==ids.size(),"Stocks visible items missing")
	for i in ids.size():check(value.items[i].id==int(ids[i]) and not value.items[i].caption.is_empty(),"Stocks item row differs")
	for step in [1,2]:
		if failed:break
		var group: Dictionary=value.groups[0]
		var desired: bool=not reference.original_hidden if step==1 else reference.original_hidden
		var intent: Dictionary={"action":C.ManagementAction.StocksGroupApply,"category":39,"subtype":group.subtype,"subcat1":group.subcat1,"subcat2":group.subcat2,"expected_revision":group.revision,"operation":C.StocksFlagAction.Hidden,"value":int(desired)}
		var reply:=await request("stocks_menu",intent)
		if not check(reply.get("status")==C.ManagementStatus.Ok and reply.get("stocks_menu",{}).get("outcome")==C.StocksMenuOutcome.Applied,"Stocks edit failed"):break
		value=reply.stocks_menu
		var stale:=await request("stocks_menu",intent)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("stocks_menu",{}).get("outcome")==C.StocksMenuOutcome.Stale,"Stocks stale replay accepted")
		var f:=FileAccess.open(directory+"/stocks-wire-step",FileAccess.WRITE);f.store_string(str(step));f.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/stocks-wire-ack") and FileAccess.get_file_as_string(directory+"/stocks-wire-ack").strip_edges()==str(step):break
			await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/stocks-wire-ack").strip_edges()==str(step),"Stocks effects not independently verified")
	var f:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"success":not failed,"categories":93,"groups":reference.selection.groups.size(),"items":ids.size(),"edits":2}));f.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
