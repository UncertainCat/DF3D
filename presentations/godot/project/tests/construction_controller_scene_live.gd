extends "res://tests/construction_controller_live.gd"
var scene

func run() -> void:
	directory = OS.get_environment("DF3D_CONSTRUCTION_ACCEPTANCE")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Use construction_acceptance.ps1 -ControllerScene on an owned clone with GPU")
		quit(77); return
	lane_deadline_ms = Time.get_ticks_msec()+int(FileAccess.get_file_as_string(directory+"/budget-ms.txt"))
	OS.set_environment("DF3D_DF_PATH",FileAccess.get_file_as_string(directory+"/df-path.txt"))
	OS.set_environment("DF3D_FIXTURE","")
	var preferences = preload("res://scripts/presentation_settings.gd")
	preferences.loaded = true; preferences.ui_scale = 1.0; preferences.camera_mode = "df"
	root.size = Vector2i(1200,800)
	scene = load("res://scenes/main.tscn").instantiate(); root.add_child(scene)
	world = scene.world
	var deadline := Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
	if check(scene._loader.entered,"main scene did not enter fortress"):
		await exercise()
		if not stopped: await pointer_wall()
		if not stopped: await pointer_pressure()
	departure_report()
	var status := "failed" if failed else ("incomplete" if not reasons.is_empty() else "passed")
	write_json("result.json",{"status":status,"reasons":reasons,"surface":"main scene GPU; broad controller callbacks plus wall and Pressure Plate lifecycle through viewport input"})
	print("CONSTRUCTION_CONTROLLER_SCENE ",status)
	scene.queue_free(); await process_frame
	quit(1 if failed else (77 if status == "incomplete" else 0))

func setup_controller() -> void:
	interaction = scene._interaction; host = scene._ui.host; actions = scene._ui.actions
	actions.set_process(false)
	actions.completed.connect(func(ticket,result):
		last_receipt = result.duplicate(true)
		print("SCENE_RECEIPT ticket=",ticket," action=",result.get("action",-1)," status=",result.get("status",-1)," message=",result.get("message","")))
	editor = scene._ui.controller("construction"); editor.set_process(false)

func observe_stage(label: String) -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var p := point(fixture.origin)
	scene.camera_rig.focus_on(Vector3(p.x+0.5,world.get_top_z()+1.0,p.y+0.5),30)
	for frame in 12:
		editor._process(0)
		await process_frame
	# Preview the candidate launcher only for capture; product exposure remains
	# governed by ui_availability, which has not been promoted by this test.
	scene._fortress_hud.navigation["Build / construction"].show()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/scene_"+label+".png") == OK,"capture failed")

func pointer_click(position: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = position; motion.global_position = position
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.position = position; event.global_position = position
		event.button_index = button; event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
		root.push_input(event,true)
	await process_frame; await process_frame

func click_control(control: Control) -> void:
	await pointer_click(control.get_global_transform_with_canvas() * (control.size/2))

func pointer_wall() -> void:
	step = "viewport pointer wall"
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var origin := point(fixture.sites.wall)
	world.set_top_z(origin.z)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	var launcher: Button = scene._fortress_hud.navigation["Build / construction"]
	for frame in 8:
		launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
	launcher.show()
	await click_control(launcher)
	if not await wait_for(func(): return editor.panel.visible and editor.request_ticket == 0 and not editor.catalog.is_empty(),"pointer launcher"): return
	await click_control(editor.menu.row_controls[0][3])
	if not check(editor.menu.path == [3],"pointer category did not open Constructions"): return
	await click_control(editor.menu.row_controls[1][0])
	if not check(editor.mode == "place" and editor.selected_label == "Wall","pointer leaf did not choose Wall"): return
	if editor.keep_building.button_pressed: await click_control(editor.keep_building)
	var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
	var position: Vector2 = editor.camera.unproject_position(target)
	var picked: Vector3i = world.pick_tile(editor.camera.project_ray_origin(position),editor.camera.project_ray_normal(position),world.get_top_z())
	if not check(picked == origin,"rendered tile picking disagrees with wall fixture"): return
	await pointer_click(position)
	if not check(editor.corner == origin,"first pointer corner not retained"): return
	await pointer_click(position,MOUSE_BUTTON_RIGHT)
	if not check(editor.corner.z < 0 and editor.mode == "place","right click did not cancel the gesture"): return
	await pointer_click(position); await pointer_click(position)
	if not await wait_for(func(): return editor.mode == "materials" and editor.request_ticket == 0 and editor.pending_read.is_empty(),"pointer material panel"): return
	await observe_stage("pointer_wall_materials")
	if not check(not editor.material_view.row_controls.is_empty(),"pointer materials unavailable"): return
	await click_control(editor.material_view.row_controls[0].pick)
	if not await wait_for(func(): return not editor.panel.visible and not editor.placed_sites.is_empty(),"pointer Place"): return
	var verification := await native("placed",{"definition":"Construction:Wall","origin":native_point(origin),"width":1,"height":1,"depth":1,"direction":0,"retracting":false,"mode":3,"mask":[1],"placed":1,"skipped":0})
	if stopped: return
	var ids := building_ids(verification)
	if not check(ids.size() == 1 and editor.placed_sites.has(ids[0]),"pointer Place native identity mismatch"): return
	await observe_stage("pointer_wall_placed")
	# Inspection/removal already have broader controller readback above.
	editor.open_panel()
	if not await wait_for(func(): return editor.request_ticket == 0,"cleanup catalog"): return
	editor.begin_inspect(); editor.send({"action":3,"building_id":ids[0]})
	if not await wait_for(func(): return editor.request_ticket == 0 and editor.inspected_id == ids[0],"cleanup Inspect"): return
	editor.remove_button.pressed.emit()
	if not await wait_for(func(): return editor.request_ticket == 0 and editor.inspected_id == -1,"cleanup Remove"): return
	await native("removed",{"id":ids[0]}); await native("final")
	editor.close_panel()
	print("CONSTRUCTION_POINTER_WALL_PASS")

func pointer_pressure_choice(kind: String, value: int) -> bool:
	for control in editor.pressure_view.find_children("*","BaseButton",true,false):
		if control.get_meta("pressure_kind","") == kind and control.get_meta("pressure_value",-999) == value:
			await click_control(control)
			return true
	return check(false,"missing pressure pointer control: "+kind)

func pointer_pressure() -> void:
	step = "viewport Pressure Plate lifecycle"
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var origin := point(fixture.sites.pump0)
	world.set_top_z(origin.z)
	# Retain a different family's preference: native plates must still exit.
	editor.keep_building.button_pressed = true
	for outcome in ["escape","right","place","reopen"]:
		var launcher: Button = scene._fortress_hud.navigation["Build / construction"]
		launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size())
		await click_control(launcher)
		if not await wait_for(func(): return editor.panel.visible and editor.request_ticket == 0 and not editor.catalog.is_empty(),"pressure launcher"): return
		await click_control(editor.menu.row_controls[0][6])
		await click_control(editor.menu.row_controls[1][0])
		if not check(editor.mode == "place" and editor.draft.definition.get("key","") == "Trap:PressurePlate","pointer leaf did not choose Pressure Plate"): return
		if not check(editor.draft.pressure_plate == editor.draft.PRESSURE_DEFAULT and not editor.footer.visible,"pressure defaults or native-only controls differ"): return
		if outcome == "reopen":
			editor.close_panel(); break
		for choice in [["resets",0],["water",1],["water_depth",3],["track",1],["track_min",1],["units",1],["citizens",1],["creature",6000]]:
			if not await pointer_pressure_choice(choice[0],choice[1]): return
		var profile: Dictionary = editor.draft.pressure_plate.duplicate(true)
		if not check(not profile.resets and profile.water and profile.water_min == 3 and profile.water_max == 3 and profile.track and profile.track_min == 50 and profile.units and profile.citizens and profile.unit_min == 6000 and profile.unit_max == 6999,"pointer controls did not produce native recorded profile"): return
		await observe_stage("pressure_"+outcome+"_options")
		var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
		var position := Vector2(-1,-1)
		# Choose a presentation camera position with the target outside the option
		# pane. This never changes native DF's camera or construction widgets.
		for offset in [Vector3(10,0,0),Vector3(-10,0,0),Vector3(0,0,10),Vector3(0,0,-10)]:
			scene.camera_rig.focus_on(target+offset,30)
			for frame in 3: await process_frame
			var candidate: Vector2 = editor.camera.unproject_position(target)
			if not Rect2(40,120,490,540).has_point(candidate): continue
			var picked: Vector3i = world.pick_tile(editor.camera.project_ray_origin(candidate),editor.camera.project_ray_normal(candidate),world.get_top_z())
			if picked == origin: position = candidate; break
		if not check(position.x >= 0,"pressure fixture has no unobscured picked tile"): return
		await pointer_click(position)
		if not await wait_for(func(): return editor.mode == "materials" and editor.request_ticket == 0 and editor.pending_read.is_empty(),"pressure materials"): return
		await observe_stage("pressure_"+outcome+"_materials")
		if outcome == "escape":
			for pressed in [true,false]:
				var event := InputEventKey.new(); event.keycode = KEY_ESCAPE; event.pressed = pressed; root.push_input(event,true)
		elif outcome == "right": await pointer_click(Vector2(100,600),MOUSE_BUTTON_RIGHT)
		else:
			if not check(not editor.material_view.row_controls.is_empty(),"pressure mechanisms unavailable"): return
			await click_control(editor.material_view.row_controls[0].pick)
		if not await wait_for(func(): return not editor.panel.visible,"pressure "+outcome+" returns to map"): return
		if not check(editor.draft.definition.is_empty() and editor.pressure_creatures.is_empty(),"pressure exit retained local state"): return
		if outcome == "place":
			var verification := await native("placed",{"definition":"Trap:PressurePlate","origin":native_point(origin),"width":1,"height":1,"depth":1,"direction":0,"retracting":false,"mode":1,"mask":[1],"placed":1,"skipped":0,"pressure_plate":profile})
			if stopped: return
			var ids := building_ids(verification)
			if not check(ids.size() == 1 and editor.placed_sites.has(ids[0]),"pointer pressure native identity mismatch"): return
			write_json("pointer-pressure.json",{"id":ids[0],"profile":profile,"cancel":["escape","right"],"returns_to_map":true})
	print("CONSTRUCTION_POINTER_PRESSURE_PASS")
