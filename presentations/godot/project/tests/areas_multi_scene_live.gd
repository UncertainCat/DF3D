extends "res://tests/areas_controller_scene_live.gd"
# Protected native effects through actual viewport/controller/action-service input.
func pointer_areas() -> void:
	step = "Multi viewport baseline"
	await native("multi_begin")
	if stopped: return
	var origin := Vector3i(172,57,164)
	world.set_top_z(origin.z)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	var launcher: Button = scene._fortress_hud.navigation.Zones
	for frame in 12:
		launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
	launcher.show(); await click_control(launcher)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"Multi launcher"): return
	await click_control(editor.zone_menu.buttons.Bedroom)
	await click_control(editor.paint_view.multi_button)
	if not check(editor.mode == "multi" and editor.multi_state.ready(),"Multi button did not enter selection"): return
	await capture("multi_initial")
	await partial_gestures(origin)
	if stopped: return
	var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
	var position: Vector2 = editor.camera.unproject_position(target)
	var picked: Vector3i = world.pick_tile(editor.camera.project_ray_origin(position),editor.camera.project_ray_normal(position),world.get_top_z())
	if not check(picked == origin,"Multi rendered picking differs from native seed"): return
	step = "Multi two-corner creation"
	var before := receipts.size()
	await pointer_click(position)
	if not check(editor.dragging and receipts.size() == before and settled(),"first corner submitted a room"): return
	await pointer_click(position)
	if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"Multi creation"): return
	if not check(receipts.size() == before+1 and editor.paint_state.cells.is_empty(),"Multi must create with one request and no Paint draft"): return
	if not check(editor.paint_view.multi_result.text == "Bedroom created." and editor.paint_view.cancel_button.text == "Done"
		and editor.paint_view.accept_button.text == "Undo","Multi result copy differs from native capture"): return
	await native("multi_check",{"count":1})
	await capture("multi_created")
	step = "Multi viewport Undo"
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and not editor.multi_state.has_result(),"Multi Undo"): return
	await native("multi_check",{"count":0})
	await native("multi_cleanup")
	await capture("multi_undone")
	step = "Multi viewport Cancel"
	await click_control(editor.paint_view.cancel_button)
	if not await wait_ui(func(): return editor.mode != "multi" and settled(),"Multi Cancel"): return
	if not check(editor.multi_state.interaction_id == 0,"Cancel retained Multi authority"): return
	await reference_rooms()
	await native("multi_final")

func partial_gestures(origin: Vector3i) -> void:
	step = "Multi native partial-cancel gestures"
	var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
	var position: Vector2 = editor.camera.unproject_position(target)
	for cancel in ["right", "escape"]:
		var before := receipts.size()
		await pointer_click(position)
		if not check(editor.dragging,"partial gesture did not start"): return
		if cancel == "right": await pointer_click(position,MOUSE_BUTTON_RIGHT)
		else:
			for pressed in [true,false]:
				var event := InputEventKey.new(); event.keycode = KEY_ESCAPE; event.pressed = pressed
				root.push_input(event,true)
			await process_frame
		if not check(editor.mode == "multi" and not editor.dragging and receipts.size() == before,"partial cancellation exited Multi or submitted work"): return
		await native("multi_check",{"count":0})
	step = "Multi native cross-elevation corners"
	world.set_top_z(165); editor._process(0)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,166,origin.y+0.5),30)
	var high := Vector3i(origin.x,origin.y,165)
	var high_position: Vector2 = editor.camera.unproject_position(Vector3(high.x+0.5,high.z+float(world.floor_height()),high.y+0.5))
	if not await wait_ui(func(): return world.pick_tile(editor.camera.project_ray_origin(high_position),editor.camera.project_ray_normal(high_position),world.get_top_z()) == high,"upper first corner picking"): return
	await pointer_click(high_position)
	world.set_top_z(origin.z); editor._process(0)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	if not check(editor.dragging and editor.drag_start.z == origin.z,"elevation discarded native first corner"): return
	position = editor.camera.unproject_position(target)
	if not await wait_ui(func(): return world.pick_tile(editor.camera.project_ray_origin(position),editor.camera.project_ray_normal(position),world.get_top_z()) == origin,"ending corner picking"): return
	await pointer_click(position)
	if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"cross-elevation Multi"): return
	await native("multi_check",{"count":1})
	await capture("multi_cross_elevation")
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and not editor.multi_state.has_result(),"cross-elevation Undo"): return
	await native("multi_cleanup")

func reference_rooms() -> void:
	var cases := {"Office-single":"Office","DiningHall-single":"DiningHall","Tomb-single":"Tomb",
		"beds-split-both-unused":"Bedroom","beds-merged-both-unused":"Bedroom","beds-unenclosed-and-used":"Bedroom"}
	for case_name in cases:
		if stopped: return
		step = "viewport " + case_name
		var prepared := await native("multi_case_prepare",{"case":case_name})
		if stopped: return
		var selection: Dictionary = prepared.selection
		var origin := Vector3i(int(selection.x),int(selection.y),int(selection.z))
		world.set_top_z(origin.z)
		scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
		await click_control(editor.zone_menu.buttons[cases[case_name]])
		await click_control(editor.paint_view.multi_button)
		if not check(editor.mode == "multi" and editor.multi_state.ready(),"reference Multi did not open"): return
		await capture("multi_"+case_name+"_initial")
		await select_rectangle(origin,origin+Vector3i(int(selection.width)-1,0,0))
		if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"reference result"): return
		var observed: Dictionary = editor.multi_state.observed
		if not check(int(observed.rooms_created) == int(prepared.count) and int(observed.rooms_dormitories) == int(prepared.dormitories)
			and int(observed.rooms_in_use) == int(prepared.in_use) and int(observed.rooms_unenclosed) == int(prepared.unenclosed),"viewport native counts differ"): return
		await native("multi_case_check")
		await capture("multi_"+case_name+"_result")
		write_json("multi_"+case_name+"_copy.json",{"prompt":editor.paint_view.prompt.text,
			"created":editor.paint_view.multi_result.text,"rejected":editor.paint_view.multi_rejected.text})
		await click_control(editor.paint_view.accept_button)
		if not await wait_ui(func(): return settled() and not editor.multi_state.has_result(),"reference Undo"): return
		await native("multi_case_check",{"removed":true})
		if case_name == "beds-split-both-unused":
			step = "viewport Done retains rooms"
			await select_rectangle(origin,origin+Vector3i(int(selection.width)-1,0,0))
			if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"selection before Done"): return
			await click_control(editor.paint_view.cancel_button)
			if not await wait_ui(func(): return editor.mode != "multi" and settled(),"Done"): return
			if not check(editor.multi_state.interaction_id == 0,"Done retained local Undo authority"): return
			await native("multi_case_check")
			await native("multi_case_cleanup")
		else:
			await click_control(editor.paint_view.cancel_button)
			if not await wait_ui(func(): return editor.mode != "multi" and settled(),"reference Cancel"): return
		await native("multi_case_restore")

func select_rectangle(first: Vector3i, last: Vector3i) -> void:
	for tile in [first,last]:
		var target := Vector3(tile.x+0.5,tile.z+float(world.floor_height()),tile.y+0.5)
		var position: Vector2 = editor.camera.unproject_position(target)
		if not await wait_ui(func(): return world.pick_tile(editor.camera.project_ray_origin(position),editor.camera.project_ray_normal(position),world.get_top_z()) == tile,"reference picking"): return
		await pointer_click(position)
