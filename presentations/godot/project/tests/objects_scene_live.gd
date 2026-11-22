extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "objects-wire-reference.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func settle(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while model.phase in [model.Phase.Reading,model.Phase.Locating] and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Objects did not become ready: phase %d"%model.phase)
func lifecycle_handshake(step: int) -> bool:
	var file=FileAccess.open(directory+"/objects-lifecycle-request",FileAccess.WRITE)
	file.store_string(str(step));file.close()
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		if FileAccess.file_exists(directory+"/objects-lifecycle-ack") and FileAccess.get_file_as_string(directory+"/objects-lifecycle-ack")==str(step):return true
		await create_timer(0.01).timeout
	return check(false,"Objects lifecycle handshake timed out")
func lifecycle_recovery() -> bool:
	owner.open_panel();if not await settle(owner.state):return false
	var rows: Array=owner.state.rows.duplicate(true)
	var index: int=rows.find_custom(func(row):return row.has("position"))
	if not check(index>=0,"Lifecycle needs local artifact"):return false
	var generation: int=owner.state.generation
	var epoch: int=actions._epoch
	var previous_connection: int=actions._generation
	var navigation: Array=[]
	var on_focus=func(tile):navigation.append({"kind":"focus","tile":tile})
	var on_inspect=func(id,tile):navigation.append({"kind":"inspect","id":id,"tile":tile})
	owner.focus_requested.connect(on_focus);owner.inspect_requested.connect(on_inspect)
	owner._navigate(rows[index],true)
	var ticket: int=owner.state.ticket
	var deadline:=Time.get_ticks_msec()+10000
	while actions._requests.has(ticket) and int(actions._requests[ticket].sequence)==0 and Time.get_ticks_msec()<deadline:
		actions.poll(0.01)
		if int(actions._requests.get(ticket,{}).get("sequence",0))>0:break
		await create_timer(0.01).timeout
	if not check(ticket>0 and int(actions._requests.get(ticket,{}).get("sequence",0))>0,"Locate was not sent before loss"):return false
	if not await lifecycle_handshake(1):return false
	actions.set_process(true);deadline=Time.get_ticks_msec()+10000
	while owner.panel.visible and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
	check(not owner.panel.visible and scene._ui.host.active==null,"Objects loss retained input ownership")
	check(owner.state.generation>generation and owner.state.ticket==0 and owner.state.rows.is_empty() and owner.destination.is_empty(),"Objects loss retained navigation authority")
	check(actions.result(ticket).get("outcome")=="unknown","Lost locate did not retire as unknown")
	if not await lifecycle_handshake(2):return false
	deadline=Time.get_ticks_msec()+60000
	var stable_since:=0;var last_epoch: int=-1;var connection_generation: int=-1
	while Time.get_ticks_msec()<deadline:
		var ready: bool=scene._loader.entered and scene._ui.host.play_enabled and not actions._transport_lost and not actions._needs_claim and actions._epoch>0 and actions._generation==world.session_generation()
		if not ready or last_epoch!=actions._epoch or connection_generation!=actions._generation:stable_since=0
		last_epoch=actions._epoch;connection_generation=actions._generation
		if ready:
			if stable_since==0:stable_since=Time.get_ticks_msec()
			elif Time.get_ticks_msec()-stable_since>=500:break
		await create_timer(0.02).timeout
	if not check(stable_since>0 and Time.get_ticks_msec()-stable_since>=500,"Objects replacement connection unavailable"):return false
	check(actions._generation!=previous_connection,"Objects did not observe a replacement connection")
	check(not owner.panel.visible and scene._ui.host.active==null and navigation.is_empty(),"Reconnect replayed Objects navigation")
	owner.focus_requested.disconnect(on_focus);owner.inspect_requested.disconnect(on_inspect)
	actions.set_process(false);owner.open_panel()
	if not await settle(owner.state):return false
	check(owner.state.rows==rows,"Fresh Objects read differs from unchanged native state")
	owner.close_panel()
	var file=FileAccess.open(directory+"/objects-lifecycle-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"sent_locate_retired":true,"fresh_read":true,"old_epoch":epoch,"new_epoch":actions._epoch,"old_connection":previous_connection,"new_connection":actions._generation,"navigation":navigation}));file.close()
	return not failed
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("objects")
	var places=scene._ui.controller("places")
	var item=scene._ui.controller("farm").item_owner
	for extent in [Vector2i(912,552),Vector2i(1600,900)]:
		root.size=extent;await process_frame;await process_frame
		places.open_panel()
		await drain();await process_frame;await process_frame
		await pointer(places.panel.get_global_transform_with_canvas()*Vector2(256 if extent.x<1240 else 688,24))
		if not await settle(owner.state):return
		check(scene._ui.host.active==owner and not places.panel.visible,"Information header did not hand off to Objects")
		for tab in 4:
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(tab).get_center())
			if not await settle(owner.state):return
			check(owner.state.rows.size()==expected.ownership[tab].size(),"Composed Objects membership differs")
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(200,24))
		await drain()
		check(scene._ui.host.active==places and not owner.panel.visible,"Objects did not return to Places")
		places.close_panel()
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	for inspect in [false,true]:
		await pointer(scene._fortress_hud.launcher_rect("Objects").get_center());if not await settle(owner.state):return
		var index: int=owner.state.rows.find_custom(func(row):return row.has("position"))
		if not check(index>=0 and index<owner.panel.capacity(),"No visible local artifact for scene handoff"):return
		var row: Dictionary=owner.state.rows[index].duplicate(true)
		var point: Vector2=owner.panel.get_global_transform_with_canvas()*Vector2(owner.panel.navigation_x()+(36 if inspect else 12),owner.panel.list_top()+index*36+18)
		scene._fortress_hud.toggle_game_menu();await process_frame
		await pointer(point);await drain()
		check(scene._ui.host.active==owner and owner.state.phase==owner.state.Phase.Ready,"Overlay allowed Objects navigation")
		scene._fortress_hud.close_menus();await process_frame
		await pointer(point);await drain()
		check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible,"Navigation retained Objects")
		var tile: Vector3i=row.position
		var rig=scene.camera_rig
		check(world.get_top_z()==tile.z and is_equal_approx(rig.position.x,tile.x+0.5) and is_equal_approx(rig.position.z,tile.y+0.5),"Objects camera focused wrong tile")
		check(scene._ui.item_follow.item_id==-1 and scene._ui.creature_follow.unit_id==-1,"Objects unexpectedly enabled follow")
		if inspect:
			check(item.state.phase==item.state.Phase.Ready and item.state.item_id==row.item_id and scene._ui.host.active==item,"View did not open the selected item sheet")
			key(KEY_ESCAPE);await process_frame
			check(not item.panel.visible and scene._ui.host.active==null,"Escape retained item sheet")
		else:check(scene._ui.host.active==null,"Recenter retained modal input")
	await pointer(scene._fortress_hud.launcher_rect("Objects").get_center());if not await settle(owner.state):return
	key(KEY_ESCAPE);await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and scene._ui.host.active==null,"Escape retained Objects")
	owner.open_panel();scene._ui.host.set_play_enabled(false);await drain()
	check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible and scene._ui.host.active==null,"Play disable or late read reopened Objects")
	scene._ui.host.set_play_enabled(true)
	if OS.get_environment("DF3D_OBJECTS_LIFECYCLE")=="1" and not await lifecycle_recovery():return
	exercised=true
