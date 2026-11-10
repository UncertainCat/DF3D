extends "res://tests/item_carrier_wire_live.gd"
class OwnerHost extends RefCounted:
	var active
	func activate(owner) -> bool:
		if is_instance_valid(active) and active!=owner:active.close_panel()
		active=owner;return true
	func allows_panel_input(owner) -> bool:return active==owner
	func release(owner) -> void:
		if active==owner:active=null
func settle_places(model) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
func page(tab: int,offset:=0,revision:=0) -> Dictionary:
	return await request("places",{"action":C.ManagementAction.PlacesRead,"tab":tab,"offset":offset,"limit":16,"expected_list_revision":revision})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/places-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Places attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var counts: Array=[]
	for tab in 6:
		var rows: Array=[];var revision:=0;var first:=true
		while first or rows.size()<reference[tab].size():
			first=false;var reply:=await page(tab,rows.size(),revision)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Places page rejected"):quit(1);return
			var state: Dictionary=reply.get("places",{})
			check(state.get("tab")==tab and state.get("offset")==rows.size() and state.get("total")==reference[tab].size(),"Places page bounds differ")
			revision=state.get("list_revision",0)
			if not check(not state.get("rows",[]).is_empty() or rows.size()==reference[tab].size(),"Places pagination stalled"):quit(1);return
			rows.append_array(state.rows)
		for i in rows.size():
			var row: Dictionary=rows[i];var expected: Dictionary=reference[tab][i]
			check(row.building_id==int(expected.id),"Places identity differs")
			for key in ["name","subtitle","job_caption","status_caption","secondary_status","status_overlay","operator_caption","additional_jobs","siege_action"]:
				check(row.get(key)==expected.get(key),"Places field differs: "+key)
			var p: Array=expected.position
			check(row.get("position")==Vector3i(int(p[0]),int(p[1]),int(p[2])),"Places position differs")
			check(row.has("appearance")==expected.has("appearance"),"Places artwork presence differs")
			if row.has("appearance"):
				check(row.appearance.tile_pages==expected.appearance.pages,"Places artwork pages differ")
				check(row.appearance.layers==expected.appearance.layers.map(func(layer):return layer.map(func(n):return int(n))),"Places artwork layers differ")
		var stale:=await page(tab,0,revision ^ 1)
		check(stale.get("places",{}).get("outcome")==C.PlacesOutcome.Stale,"Places stale list accepted")
		counts.append(rows.size())
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/places_state.gd").new();controller.configure(actions);controller.open()
	var view
	if OS.get_environment("DF3D_PLACES_RENDER")=="1":
		root.size=Vector2i(1200,800)
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Places assets unavailable")
		view=preload("res://scripts/places_view.gd").new();root.add_child(view);view.configure_places(world,controller);view.layout(Vector2(1200,800))
	for tab in 6:
		if tab>0:controller.select_tab(tab)
		deadline=Time.get_ticks_msec()+5000
		while controller.phase==controller.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		check(controller.phase==controller.Phase.Ready and controller.rows.size()==reference[tab].size(),"Places controller failed tab %d"%tab)
		for i in controller.rows.size():check(controller.rows[i].building_id==int(reference[tab][i].id),"Controller row order differs")
		if view!=null:
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/places-view-%d.png"%tab)
	if view!=null:view.queue_free();await process_frame
	controller.refresh();controller.close()
	for i in 5:world.poll();await create_timer(0.01).timeout
	check(controller.phase==controller.Phase.Closed and controller.rows.is_empty(),"Late live reply reopened Places")
	controller.dispose()
	var owner=preload("res://scripts/places_panel.gd").new();root.add_child(owner)
	var host:=OwnerHost.new();owner.ui_host=host;owner.state.configure(actions)
	var inspected: Array=[];var focused: Array=[]
	owner.inspect_requested.connect(func(tab,id,tile):inspected.append([tab,id,tile]))
	owner.focus_requested.connect(func(tile):focused.append(tile))
	for tab in 6:
		owner.open_panel();if tab>0:owner.state.select_tab(tab)
		await settle_places(owner.state)
		if not check(owner.state.phase==owner.state.Phase.Ready and not owner.state.rows.is_empty(),"Live owner unavailable"):quit(1);return
		var target: Dictionary=owner.state.rows[0].duplicate(true)
		owner._navigate(target,true);await settle_places(owner.state)
		check(inspected.size()==tab+1 and inspected[-1]==[tab,target.building_id,target.position],"Live inspector handoff differs")
		check(host.active==null and owner.state.phase==owner.state.Phase.Closed,"Live inspector handoff retained Places ownership")
	owner.open_panel();await settle_places(owner.state)
	var target: Dictionary=owner.state.rows[0].duplicate(true);owner._navigate(target,false);await settle_places(owner.state)
	check(focused==[target.position] and host.active==null,"Live recenter handoff differs")
	owner.queue_free();await process_frame;actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"counts":counts,"stale_tabs":6,"controller_tabs":6,"closed_read_retired":true,"owner_inspect_tabs":6,"owner_recenter":true}));result.close()
	quit(1 if failed else 0)
