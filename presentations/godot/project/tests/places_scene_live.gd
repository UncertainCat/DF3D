extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "places-scene-reference.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func settle(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while model.phase in [model.Phase.Reading,model.Phase.Applying] and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Places did not become ready")
func observe_siege(step: int,engines: Array) -> void:
	var file=FileAccess.open(directory+"/places-siege-step.tmp",FileAccess.WRITE);file.store_string(JSON.stringify({"step":step,"engines":engines}));file.close()
	DirAccess.rename_absolute(directory+"/places-siege-step.tmp",directory+"/places-siege-step")
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/places-siege-ack")!=str(step):await create_timer(0.01).timeout
	check(FileAccess.get_file_as_string(directory+"/places-siege-ack")==str(step),"Native siege action observation missing")
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
	var extents: Array=[[Vector2i(912,552),288,9],[Vector2i(1600,900),752,20]] if OS.get_environment("DF3D_PLACES_LAYOUT")=="1" else [[Vector2i(1200,800),480,15]]
	for extent in extents:
		root.size=extent[0];await process_frame;await process_frame
		for tab in 6:
			owner.open_panel()
			if tab>0:await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(tab).get_center())
			if not await settle(owner.state):return
			check(owner.state.tab==tab,"Resized tab click selected wrong tab")
			check(owner.panel.navigation_x()==extent[1],"Navigation column differs from native resized capture")
			check(owner.state.rows.size()==expected.rows[tab].size(),"Main Places membership differs")
			if tab==0 and OS.get_environment("DF3D_PLACES_LAYOUT")=="1":
				var scrollbar=owner.panel.scrollbar
				await pointer(scrollbar.get_global_transform_with_canvas()*Vector2(8,scrollbar.size.y-6))
				check(owner.state.first==1,"Resized scrollbar arrow did not step one row")
				var wheel:=InputEventMouseButton.new();wheel.position=owner.panel.get_global_transform_with_canvas()*Vector2(200,owner.panel.list_top()+18);wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.shift_pressed=true;wheel.pressed=true
				root.push_input(wheel,true);wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true);await process_frame
				check(owner.state.first==1+extent[2],"Resized page wheel differs from native capacity")
				owner.state.seek(0,owner.panel.capacity());await process_frame
			if tab==5 and extent[0].x==912:
				var before: Array=owner.state.rows.duplicate(true)
				await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(84,owner.panel.list_top()-30));await drain()
				check(owner.state.phase==owner.state.Phase.Ready and owner.state.rows==before,"Hidden siege control accepted input")
			for slot in 2:
				var motion:=InputEventMouseMotion.new();motion.position=owner.panel.get_global_transform_with_canvas()*Vector2(extent[1]+12+24*slot,owner.panel.list_top()+18)
				var deadline:=Time.get_ticks_msec()+650
				while Time.get_ticks_msec()<deadline:
					root.push_input(motion.duplicate(),true);await process_frame
				check(scene._fortress_hud.native_help.displayed==["places_recenter","places_view"][slot],"Places hover missing on tab %d"%tab)
			var row: Dictionary=owner.state.rows[0].duplicate(true)
			await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(extent[1]+36,owner.panel.list_top()+18))
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
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	if OS.get_environment("DF3D_PLACES_APPLY")=="1":
		owner.open_panel();owner.state.select_tab(5);if not await settle(owner.state):return
		var engines: Array=[]
		for engine in owner.state.rows:engines.append({"id":engine.building_id,"action":engine.siege_action})
		var step:=0
		for target_index in range(engines.size()+1):
			for slot in 5:
				var y: int=owner.panel.list_top()-30 if target_index==engines.size() else owner.panel.list_top()+target_index*36+18
				await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(owner.panel.status_x()+slot*24+12,y))
				if not await settle(owner.state):return
				for index in engines.size():
					if target_index==engines.size() or index==target_index:engines[index].action=owner.panel.SIEGE_ACTIONS[slot]
				for engine in owner.state.rows:
					check(engines.any(func(value):return value.id==engine.building_id and value.action==engine.siege_action),"Siege click refresh differs")
				step+=1;await observe_siege(step,engines)
		owner.close_panel()
	owner.open_panel();if not await settle(owner.state):return
	var row: Dictionary=owner.state.rows[0].duplicate(true)
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(492,owner.panel.list_top()+18));await drain()
	check(owner.state.phase==owner.state.Phase.Closed and scene._ui.host.active==null,"Recenter retained modal owner")
	check(world.get_top_z()==row.position.z,"Recenter selected wrong elevation")
	owner.open_panel();if not await settle(owner.state):return
	key(KEY_ESCAPE);await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and scene._ui.host.active==null,"Escape retained Places")
	if OS.get_environment("DF3D_PLACES_INFORMATION")=="1":
		for extent in [Vector2i(912,552),Vector2i(1600,900)]:
			root.size=extent;await process_frame;await process_frame
			for target in [[24,"residents"],[136,"tasks"],[280,"work_details"],[352,"workshop"]]:
				owner.open_panel();if not await settle(owner.state):return
				await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(target[0],48 if extent.x<1240 else 24))
				var destination=scene._ui.controller(target[1]);await drain()
				check(scene._ui.host.active==destination and not owner.panel.visible,"Live information handoff failed: "+target[1])
				var target_view=destination.global_orders_view if target[1]=="workshop" else destination.panel
				await pointer(target_view.get_global_transform_with_canvas()*Vector2(200,48 if extent.x<1240 else 24))
				if not await settle(owner.state):return
				check(scene._ui.host.active==owner and not target_view.visible,"Live return to Places failed: "+target[1])
				owner.close_panel()
	if OS.get_environment("DF3D_PLACES_INFORMATION")=="1":
		var standing=scene._ui.controller("standing_orders")
		for extent in [Vector2i(912,552),Vector2i(1600,900)]:
			root.size=extent;await process_frame;await process_frame
			for page in ["standing","chores","kitchen","stone"]:
				standing.open_panel()
				if not await settle(standing.state):return
				match page:
					"chores":await pointer(standing.panel.get_global_transform_with_canvas()*standing.panel.category_rect(5).get_center())
					"kitchen":await pointer(standing.panel.get_global_transform_with_canvas()*standing.panel.kitchen_rect().get_center())
					"stone":await pointer(standing.panel.get_global_transform_with_canvas()*standing.panel.stone_use_rect().get_center())
				if not await settle(standing.current_state()):return
				var labor_view=standing.panel if page=="standing" else standing.chores_panel if page=="chores" else standing.kitchen_panel if page=="kitchen" else standing.stone_panel
				await pointer(labor_view.get_global_transform_with_canvas()*Vector2(280,48 if extent.x<1240 else 24))
				check(scene._ui.host.active==standing and labor_view.visible,"Selected Labor header lost subpage")
				await pointer(labor_view.get_global_transform_with_canvas()*Vector2(200,48 if extent.x<1240 else 24))
				if not await settle(owner.state):return
				check(scene._ui.host.active==owner and not labor_view.visible,"Labor page did not return to Places: "+page)
				owner.close_panel()
	exercised=true
