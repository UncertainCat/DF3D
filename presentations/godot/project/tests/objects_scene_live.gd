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
		owner.open_panel();if not await settle(owner.state):return
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
	owner.open_panel();if not await settle(owner.state):return
	key(KEY_ESCAPE);await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and scene._ui.host.active==null,"Escape retained Objects")
	owner.open_panel();scene._ui.host.set_play_enabled(false);await drain()
	check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible and scene._ui.host.active==null,"Play disable or late read reopened Objects")
	scene._ui.host.set_play_enabled(true)
	exercised=true
