extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "places-scene-reference.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func settle(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Places did not become ready")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("places")
	owner.open_panel();if not await settle(owner.state):return
	for sample in [[Vector2(468,248),MOUSE_BUTTON_WHEEL_DOWN,false,11],[Vector2(468,248),MOUSE_BUTTON_WHEEL_UP,false,9],[Vector2(468,248),MOUSE_BUTTON_WHEEL_DOWN,true,25],[Vector2(468,248),MOUSE_BUTTON_WHEEL_UP,true,0],[Vector2(-12,-32),MOUSE_BUTTON_WHEEL_DOWN,false,10],[Vector2(468,88),MOUSE_BUTTON_WHEEL_DOWN,false,10],[Vector2(468,108),MOUSE_BUTTON_WHEEL_DOWN,false,11],[Vector2(920,248),MOUSE_BUTTON_WHEEL_DOWN,false,11],[Vector2(920,248),MOUSE_BUTTON_WHEEL_DOWN,true,25]]:
		owner.state.seek(10,owner.panel.capacity());await process_frame
		var wheel:=InputEventMouseButton.new();wheel.position=owner.panel.get_global_transform_with_canvas()*sample[0];wheel.button_index=sample[1];wheel.shift_pressed=sample[2];wheel.pressed=true
		root.push_input(wheel,true);wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true);await process_frame
		check(owner.state.first==sample[3],"Places contextual scrolling differs")
	owner.state.seek(10,owner.panel.capacity());key(KEY_DOWN);key(KEY_PAGEDOWN);await process_frame
	check(owner.state.first==10,"Places accepted inactive standard scrolling keys")
	owner.close_panel()
	for tab in 6:
		owner.open_panel()
		if tab>0:owner.state.select_tab(tab)
		if not await settle(owner.state):return
		check(owner.state.rows.size()==expected.rows[tab].size(),"Main Places membership differs")
		for slot in 2:
			var motion:=InputEventMouseMotion.new();motion.position=owner.panel.get_global_transform_with_canvas()*Vector2(492+24*slot,owner.panel.list_top()+18)
			var deadline:=Time.get_ticks_msec()+650
			while Time.get_ticks_msec()<deadline:
				root.push_input(motion.duplicate(),true);await process_frame
			check(scene._fortress_hud.native_help.displayed==["places_recenter","places_view"][slot],"Places hover missing on tab %d"%tab)
		var row: Dictionary=owner.state.rows[0].duplicate(true)
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(516,owner.panel.list_top()+18))
		await drain()
		check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible,"View retained Places")
		var target=scene._ui.controller("areas" if tab<3 else "inspector")
		var deadline:=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01)
			if target.selected.get("id",-1)==row.building_id:break
			await create_timer(0.01).timeout
		check(scene._ui.host.active==target and target.selected.get("id",-1)==row.building_id,"Places View opened wrong inspector: tab %d"%tab)
		check(not scene._fortress_hud.native_help.displayed.begins_with("places_"),"Places hover survived navigation")
		target.close_panel();await process_frame
	owner.open_panel();if not await settle(owner.state):return
	var row: Dictionary=owner.state.rows[0].duplicate(true)
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(492,owner.panel.list_top()+18));await drain()
	check(owner.state.phase==owner.state.Phase.Closed and scene._ui.host.active==null,"Recenter retained modal owner")
	check(world.get_top_z()==row.position.z,"Recenter selected wrong elevation")
	owner.open_panel();if not await settle(owner.state):return
	key(KEY_ESCAPE);await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and scene._ui.host.active==null,"Escape retained Places")
	exercised=true
