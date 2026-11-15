extends "res://tests/tile_selection_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.tile_selection_reference.vermin
	var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
	var ui=scene._ui;ui.focus_tile(point);ui.open_tile_selection(point)
	var selection=ui.tile_selection;var model=selection.navigation.state
	if not await selection_ready(model):return
	check(ui.host.active==selection and model.snapshot.kind==8,"Vermin destination did not own panel")
	check(model.snapshot.title==sample.descriptions[0].semantic.title and model.snapshot.description==sample.descriptions[0].semantic.description,"Vermin transported text differs")
	check(model.snapshot.has("portrait") and selection.vermin.portrait!=null,"Vermin portrait missing")
	await panel_capture("vermin","workshop-selection-vermin")
	await pointer(Vector2(920,104))
	if not await selection_ready(model):return
	check(model.snapshot.id==int(sample.native.vermin[1]),"Second vermin tab selected wrong caste")
	await pointer(Vector2(920,68))
	if not await selection_ready(model):return
	check(model.snapshot.id==int(sample.native.vermin[0]),"First vermin tab did not restore caste")
	key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and model.snapshot.is_empty(),"Vermin close retained selection")
	ui.open_tile_selection(point);actions.poll(0.01);ui.host.reset_local_views();await drain()
	check(ui.host.active==null and model.snapshot.is_empty(),"Late vermin response reopened panel")
	exercised=true
