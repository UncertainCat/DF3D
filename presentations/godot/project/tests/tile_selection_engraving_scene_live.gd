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
	if OS.get_environment("DF3D_TILE_SELECTION_ENGRAVING_NAME")=="1":
		await pointer(Vector2(112,430))
		if not await settle(selection.artwork_state):return
		var naming=selection.artwork.name_state
		if not check(naming.active and naming.phase==naming.Phase.Ready,"Engraving name did not open"):return
		for i in 7:
			await pointer(Vector2(372,142+i*36))
			if not await settle(selection.artwork_state):return
		check(naming.rows.size()==sample.image.draft.naming.words.size(),"Naming word count differs")
		var same_words: bool=naming.rows.size()==sample.image.draft.naming.words.size()
		for i in mini(naming.rows.size(),sample.image.draft.naming.words.size()):
			same_words=same_words and naming.rows[i].word==sample.image.draft.naming.words[i] and naming.rows[i].part==sample.image.draft.naming.parts[i]
		check(same_words,"Naming word order differs")
		await name_capture("cleared")
		await pointer(Vector2(450,178))
		if not await settle(selection.artwork_state):return
		check(selection.artwork_state.draft_value.name.words[0]==sample.image.draft.naming.selected_word,"Name word selection differs")
		await name_capture("selected")
		await pointer(Vector2(840,82))
		if not await settle(selection.artwork_state):return
		check(not naming.active and selection.artwork_state.art_page()==6,"Name Done did not restore draft")
	if OS.get_environment("DF3D_TILE_SELECTION_ENGRAVING_CATEGORIES")=="1":
		var points: Array[Vector2]=[Vector2(110,166),Vector2(150,202),Vector2(110,238),Vector2(170,238),Vector2(110,274),Vector2(170,274),Vector2(110,310)]
		for index in points.size():
			await pointer(points[index])
			if not await settle(selection.artwork_state):return
			var expected_page: Dictionary=sample.image.draft.categories[index]
			var current=selection.artwork_state
			if not check(current.art_page()==int(expected_page.page),"Wrong image category"):return
			var equal: bool=current.snapshot.art.total==expected_page.total and current.rows.size()==expected_page.rows.size()
			for row in mini(current.rows.size(),expected_page.rows.size()):
				equal=equal and current.rows[row].id==expected_page.rows[row].id and current.rows[row].secondary==expected_page.rows[row].secondary
			check(equal,"Image category choices differ: "+str(expected_page.page))
			await process_frame;await RenderingServer.frame_post_draw
			image=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
			native=Image.load_from_file(directory+"/workshop-selection-engraving-category-"+str(int(expected_page.page))+".png");native.convert(Image.FORMAT_RGB8)
			image.get_region(region).save_png(directory+"/planned-category-"+str(int(expected_page.page))+"-live.png")
			check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Image category pixels differ: "+str(expected_page.page))
			await pointer(Vector2(110,430))
			if not await settle(current):return
			check(current.art_page()==6,"Category Cancel did not restore draft")
	await pointer(Vector2(110,166))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==7,"Creature category did not open")
	await pointer(Vector2(320,202))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==6 and selection.artwork_state.snapshot.art.draft_description==sample.image.draft.description,"Composed draft description differs from native")
	await pointer(Vector2(400,200),MOUSE_BUTTON_RIGHT)
	check(selection.artwork_state.draft_discard,"Dirty draft did not ask to discard")
	await process_frame;await RenderingServer.frame_post_draw
	image=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	native=Image.load_from_file(directory+"/workshop-selection-engraving-draft-discard.png");native.convert(Image.FORMAT_RGB8)
	image.get_region(region).save_png(directory+"/planned-art-discard-live.png")
	check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Composed discard warning differs")
	await pointer(Vector2(150,202))
	check(not selection.artwork_state.draft_discard and selection.artwork_state.draft_value.elements.size()==1,"Keep working lost engraving draft")
	await pointer(Vector2(400,200),MOUSE_BUTTON_RIGHT)
	await pointer(Vector2(150,154))
	if not await settle(selection.artwork_state):return
	check(selection.artwork_state.art_page()==-1 and selection.artwork_state.draft_value.elements.is_empty(),"Discard did not return empty draft to root")
	await pointer(Vector2(100,310))
	if not await settle(selection.artwork_state):return
	await pointer(Vector2(110,166))
	if not await settle(selection.artwork_state):return
	await pointer(Vector2(320,202))
	if not await settle(selection.artwork_state):return
	if OS.get_environment("DF3D_TILE_SELECTION_ENGRAVING_RELATIONS")=="1":
		var current=selection.artwork_state
		await pointer(Vector2(110,274))
		if not await settle(current):return
		await pointer(Vector2(320,202))
		if not await settle(current):return
		check(current.draft_value.elements.size()==2,"Shape did not enter draft")
		await pointer(Vector2(150,346))
		if not await settle(current):return
		check(current.art_page()==14 and current.snapshot.art.total==sample.image.draft.relationship.total and current.rows[0].id==sample.image.draft.relationship.verb,"Relationship choices differ")
		await editor_capture("relations")
		await pointer(Vector2(320,202))
		if not await settle(current):return
		check(current.art_page()==15,"Relationship actor did not open")
		await pointer(Vector2(320,202))
		if not await settle(current):return
		if sample.image.draft.relationship.transitive:
			check(current.art_page()==16,"Relationship target did not open")
			await pointer(Vector2(320,202))
			if not await settle(current):return
		check(current.art_page()==6 and current.draft_value.relationships.size()==1 and current.snapshot.art.draft_description==sample.image.draft.relationship.description,"Relationship description differs")
		await pointer(Vector2(150,382))
		if not await settle(current):return
		await editor_capture("delete")
		await pointer(Vector2(872,166))
		if not await settle(current):return
		check(current.draft_value.elements.size()==1 and current.draft_value.relationships.is_empty() and current.snapshot.art.draft_description==sample.image.draft.relationship.deleted_description,"Deleting actor retained relationship or wrong text")
		await pointer(Vector2(110,430))
		if not await settle(current):return
	await pointer(Vector2(168,430));await drain()
	check(not selection.artwork.visible and ui.host.active==selection,"Draft Done did not return to sheet")
	key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and model.snapshot.is_empty() and not selection.tabs.visible,"Escape retained planned engraving context")
	ui.open_tile_selection(point);actions.poll(0.01);ui.host.reset_local_views();await drain()
	check(ui.host.active==null and model.snapshot.is_empty(),"Late planned reply reopened reset scene")
	exercised=true

func name_capture(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/workshop-selection-engraving-name-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(72,52,832,672)
	image.get_region(region).save_png(directory+"/planned-name-"+label+"-live.png")
	check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Engraving name pixels differ: "+label)

func editor_capture(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/workshop-selection-engraving-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(72,52,832,672)
	image.get_region(region).save_png(directory+"/planned-"+label+"-live.png")
	check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Engraving editor pixels differ: "+label)
