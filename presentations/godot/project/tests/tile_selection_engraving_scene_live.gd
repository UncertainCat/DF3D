extends "res://tests/tile_selection_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	if OS.get_environment("DF3D_TILE_SELECTION_ENGRAVING_PLANNED_SCENE")=="1":await planned_exercise(expected);return
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

func planned_exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.tile_selection_reference.engraving.planned
	var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
	var ui=scene._ui;ui.focus_tile(point);ui.open_tile_selection(point)
	var selection=ui.tile_selection;var model=selection.navigation.state
	if not await selection_ready(model):return
	if not check(ui.host.active==selection and model.snapshot.kind==5,"Planned engraving did not acquire panel"):return
	await panel_capture("planned-engraving","workshop-selection-engraving-planned")
	await pointer(Vector2(500,120))
	if not await settle(selection.artwork_state):return
	check(selection.artwork.visible and selection.artwork_state.art_page()==-1,"Specify image did not reach root")
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/workshop-selection-engraving-image-picker.png");native.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(72,52,832,672)
	image.get_region(region).save_png(directory+"/planned-art-root-live.png")
	check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Composed artwork root differs")
	await pointer(Vector2(400,200),MOUSE_BUTTON_RIGHT)
	check(not selection.artwork.visible and ui.host.active==selection and model.snapshot.kind==5,"Right-click failed to return to planned sheet")
	await pointer(Vector2(500,120))
	if not await settle(selection.artwork_state):return
	await pointer(Vector2(100,202))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==2,"Site button opened wrong page")
	await pointer(Vector2(100,202));await drain()
	check(not selection.artwork.visible and ui.host.active==selection,"Applying site did not return to sheet")
	await pointer(Vector2(500,120))
	if not await settle(selection.artwork_state):return
	await pointer(Vector2(100,310))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==6,"New image did not open draft")
	await pointer(Vector2(110,166))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==7,"Creature category did not open")
	await pointer(Vector2(320,202))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==6 and selection.artwork_state.snapshot.art.draft_description==sample.image.draft.description,"Composed draft description differs from native")
	await pointer(Vector2(168,430));await drain()
	check(not selection.artwork.visible and ui.host.active==selection,"Draft Done did not return to sheet")
	key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and model.snapshot.is_empty() and not selection.tabs.visible,"Escape retained planned engraving context")
	ui.open_tile_selection(point);actions.poll(0.01);ui.host.reset_local_views();await drain()
	check(ui.host.active==null and model.snapshot.is_empty(),"Late planned reply reopened reset scene")
	exercised=true
