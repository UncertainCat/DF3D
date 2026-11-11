extends "res://tests/item_carrier_wire_live.gd"
class OwnerHost extends RefCounted:
	var active
	func activate(owner) -> bool:active=owner;return true
	func allows_panel_input(owner) -> bool:return active==owner
	func release(owner) -> void:
		if active==owner:active=null
func settle_objects(model) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while model.phase in [model.Phase.Reading,model.Phase.Locating] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
func page(tab: int, offset: int, revision: int) -> Dictionary:
	return await request("objects",{"action":C.ManagementAction.ObjectsRead,"tab":tab,"offset":offset,"limit":4,"expected_list_revision":revision})
func locate(tab: int, artifact: int, revision: int) -> Dictionary:
	return await request("objects",{"action":C.ManagementAction.ObjectsLocate,"tab":tab,"artifact_id":artifact,"expected_list_revision":revision})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/objects-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Objects attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var counts: Array=[];var lookups:=0
	for tab in 4:
		var expected: Array=reference.ownership[tab];var rows: Array=[];var revision:=0;var first:=true
		while first or rows.size()<expected.size():
			first=false;var reply:=await page(tab,rows.size(),revision)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Objects page rejected"):quit(1);return
			var state: Dictionary=reply.get("objects",{})
			check(state.get("tab")==tab and state.get("offset")==rows.size() and state.get("total")==expected.size(),"Objects page identity differs")
			revision=state.get("list_revision",0)
			if not check(not state.get("rows",[]).is_empty() or rows.size()==expected.size(),"Objects page stalled"):quit(1);return
			rows.append_array(state.rows)
		for i in rows.size():
			for key in ["artifact_id","item_id","native_name","translated_name","ownership"]:
				check(rows[i].get(key)==expected[i][key],"Objects row differs: "+key)
			var facts: Dictionary=reference.appearances[tab][i]
			check(rows[i].item_type==facts.item_type,"Objects item type differs")
			if rows[i].item_type==21:
				check(rows[i].get("appearance",{}).get("coffin_unused")==bool(facts.holder_type==3 and facts.holder_count<=1),"Objects coffin state differs")
			if rows[i].item_type==24:
				check(rows[i].get("appearance",{}).get("artifact_mood")==facts.artifact_mood,"Objects weapon mood differs")
			var target: Dictionary=reference.destinations[tab][i]
			check(rows[i].has("position")==target.available,"Objects availability differs")
			if target.available:
				check(rows[i].position==Vector3i(int(target.position[0]),int(target.position[1]),int(target.position[2])),"Objects position differs")
			if i==0 or (target.available and lookups==1):
				var reply:=await locate(tab,int(rows[i].artifact_id),revision)
				check(reply.get("status")==C.ManagementStatus.Ok,"Objects lookup rejected")
				var d: Dictionary=reply.get("objects",{}).get("destination",{})
				check(d.get("artifact_id")==rows[i].artifact_id and d.get("item_id")==rows[i].item_id,"Objects lookup target differs")
				check(d.get("position")==rows[i].get("position"),"Objects fresh position differs");lookups+=1
		var stale:=await page(tab,0,revision+1)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("objects",{}).get("outcome")==C.ObjectsOutcome.Stale,"Objects stale revision accepted")
		var missing:=await locate(tab,2147483647,revision)
		check(missing.get("status")==C.ManagementStatus.Rejected and missing.get("objects",{}).get("outcome")==C.ObjectsOutcome.Stale,"Objects foreign target accepted")
		counts.append(rows.size())
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/objects_state.gd").new();controller.configure(actions);controller.open()
	var view
	var hover
	if OS.get_environment("DF3D_OBJECTS_RENDER")=="1":
		root.size=Vector2i(1200,800)
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Objects assets unavailable")
		view=preload("res://scripts/objects_view.gd").new();root.add_child(view);view.configure_objects(world,controller);view.layout(Vector2(1200,800))
		hover=preload("res://scripts/native_hover_view.gd").new();root.add_child(hover);hover.configure(world);hover.layout(Vector2(1200,800));view.hover_help=hover
	for tab in 4:
		if tab>0:controller.select_tab(tab)
		await settle_objects(controller)
		check(controller.phase==controller.Phase.Ready and controller.rows.size()==reference.ownership[tab].size(),"Objects controller page failed")
		if view!=null:
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/objects-view-%d.png"%tab)
			if tab==0:
				var available: int=-1;var unavailable: int=-1
				for index in controller.rows.size():
					if controller.rows[index].has("position") and available<0:available=index
					elif not controller.rows[index].has("position") and unavailable<0:unavailable=index
				check(available>=0 and unavailable>=0,"Objects hover fixture missing rows")
				for slot in 2:
					var motion:=InputEventMouseMotion.new();motion.position=view.position+Vector2(view.navigation_x()+slot*24+12,view.list_top()+available*36+18)
					Input.parse_input_event(motion);await create_timer(0.6).timeout
					check(hover.displayed==["objects_recenter","objects_view"][slot],"Objects pointer hover missing")
					await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/objects-hover-%d.png"%slot)
				var motion:=InputEventMouseMotion.new();motion.position=view.position+Vector2(view.navigation_x()+12,view.list_top()+unavailable*36+18)
				Input.parse_input_event(motion);Input.flush_buffered_events();await create_timer(0.1).timeout
				check(hover.displayed.is_empty(),"Unavailable Objects row retained hover: "+str(view.pointer_position)+" / "+str(unavailable)+" / "+hover.displayed)
	controller.close();controller.open();controller.close()
	for i in 5:world.poll();await create_timer(0.01).timeout
	check(controller.phase==controller.Phase.Closed and controller.rows.is_empty(),"Objects late read reopened closed panel")
	if view!=null:view.queue_free();hover.queue_free();await process_frame
	controller.dispose()
	var owner=preload("res://scripts/objects_panel.gd").new();root.add_child(owner)
	var host:=OwnerHost.new();owner.ui_host=host;owner.state.configure(actions)
	var inspected: Array=[];var focused: Array=[]
	owner.inspect_requested.connect(func(id,tile):inspected.append([id,tile]))
	owner.focus_requested.connect(func(tile):focused.append(tile))
	for inspect in [true,false]:
		owner.open_panel();await settle_objects(owner.state)
		var available: Array=owner.state.rows.filter(func(row):return row.has("position"))
		if not check(not available.is_empty(),"Objects owner has no target"):quit(1);return
		var target: Dictionary=available[0].duplicate(true)
		owner._navigate(target,inspect);await settle_objects(owner.state)
		check(owner.state.phase==owner.state.Phase.Closed and host.active==null,"Objects navigation retained panel")
		check(inspected==[[target.item_id,target.position]] if inspect else focused==[target.position],"Objects navigation destination differs")
	owner.queue_free();await process_frame;actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"counts":counts,"lookups":lookups,"stale_tabs":4,"controller_tabs":4,"late_read_closed":true,"owner_navigation":true}));result.close()
	quit(1 if failed else 0)
