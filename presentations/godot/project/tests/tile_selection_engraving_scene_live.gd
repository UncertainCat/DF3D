extends "res://tests/tile_selection_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.tile_selection_reference.engraving
	var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
	var ui=scene._ui;ui.focus_tile(point);ui.open_tile_selection(point)
	var selection=ui.tile_selection;var model=selection.navigation.state
	if not await selection_ready(model):return
	if model.snapshot.kind!=4:
		for index in model.snapshot.alternatives.size():
			if model.snapshot.alternatives[index].kind==4:
				model.choose_alternative(index)
				if not await selection_ready(model):return
				break
	check(ui.host.active==selection and model.snapshot.kind==4,"Engraving did not acquire the selection panel")
	check(model.snapshot.title==sample.title and model.snapshot.description==sample.description,"Main-scene engraving text differs")
	await panel_capture("engraving","workshop-selection-engraving")
	key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and model.snapshot.is_empty() and not selection.tabs.visible,"Escape retained engraving context")
	ui.open_tile_selection(point);actions.poll(0.01);ui.host.reset_local_views();await drain()
	check(ui.host.active==null and model.snapshot.is_empty(),"Late engraving reply reopened reset scene")
	exercised=true
