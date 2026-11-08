extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Kitchen attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var query: Dictionary={"action":C.ManagementAction.KitchenRead,"type_filter":-1,"capability_filter":0,"query":"","sorts":[{"column":0,"reverse":false}]}
	var reply:=await request("kitchen_menu",query)
	if not check(reply.get("status")==C.ManagementStatus.Ok and reply.has("kitchen_menu"),"Kitchen read rejected"):quit(1);return
	var value: Dictionary=reply.kitchen_menu
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/kitchen-native.json"))
	check(value.rows.size()==reference.known.size(),"Kitchen aggregate count differs")
	for row in value.rows:
		var matched:=false
		for native in reference.known:
			var key: Dictionary=row.receipt.key
			if key.item_type==int(native.type) and key.item_subtype==int(native.subtype) and key.mat_type==int(native.mat) and key.mat_index==int(native.matg):
				matched=true;check(row.name==native.name and row.receipt.count==int(native.count) and row.receipt.capabilities==int(native.capabilities),"Kitchen native aggregate differs")
		check(matched,"Kitchen row identity missing")
	var edits: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/kitchen-edits.json"))
	var completed:=0
	for step in edits.steps:
		if failed:break
		var target: Dictionary={}
		for row in value.rows:
			if row.name==step.name:target=row.receipt
		if not check(not target.is_empty(),"Kitchen target missing"):break
		var intent: Dictionary={"action":C.ManagementAction.KitchenApply,"target":target,"permission":int(step.flag),"expected":value.exclusions}
		reply=await request("kitchen_menu",intent)
		if not check(reply.get("status")==C.ManagementStatus.Ok and reply.get("kitchen_menu",{}).get("outcome")==C.KitchenMenuOutcome.Applied,"Kitchen edit failed"):break
		check(reply.kitchen_menu.rows.is_empty() and reply.kitchen_menu.exclusions.is_empty(),"Kitchen edit retained stale authority")
		if completed==0:
			var stale:=await request("kitchen_menu",intent)
			check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("kitchen_menu",{}).get("outcome")==C.KitchenMenuOutcome.Stale,"Kitchen stale receipt accepted")
		completed+=1
		var f:=FileAccess.open(directory+"/kitchen-wire-step",FileAccess.WRITE);f.store_string(str(completed));f.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/kitchen-wire-ack") and FileAccess.get_file_as_string(directory+"/kitchen-wire-ack").strip_edges()==str(completed):break
			await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/kitchen-wire-ack").strip_edges()==str(completed),"Kitchen independent effects not acknowledged")
		reply=await request("kitchen_menu",query)
		if not check(reply.get("status")==C.ManagementStatus.Ok,"Kitchen refresh failed"):break
		value=reply.kitchen_menu
	check(completed==6,"Kitchen effects incomplete")
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"steps":completed}));output.close()
	quit(1 if failed else 0)
