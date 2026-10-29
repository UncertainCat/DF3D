extends "res://tests/farm_body_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Farm assets unavailable");return
	var model:=Model.new()
	var view=preload("res://scripts/farm_sheet_view.gd").new();root.add_child(view);view.configure(world,model)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var reference: Dictionary=fixture.sheet_resize_reference
	# Older resize captures precede management85; use the independently captured
	# unchanged default header, not a runtime fallback or synthetic caption.
	var default_header: Dictionary=fixture.header_reference.semantic_reference.records[-1].semantic
	for sample in reference.cases:
		root.size=Vector2i(int(sample.viewport[0]),int(sample.viewport[1]));view.layout(Vector2(root.size))
		model.season=int(sample.selected_season);model.snapshot=reference.snapshots[str(model.season)].duplicate(true)
		set_header(model,default_header);model.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		if view.position!=Vector2(sample.position[0],sample.position[1]) or view.size!=Vector2(sample.size[0],sample.size[1]):fail("Farm resized geometry differs");return
		var image:=root.get_texture().get_image()
		var region:=Rect2i(int(view.position.x)+4,int(view.position.y)+4,int(sample.crop[2]),int(sample.crop[3]))
		var crop:=image.get_region(region);crop.convert(Image.FORMAT_RGB8)
		crop.save_png(ProjectSettings.globalize_path("res://../../../build/"+str(sample.name)+"-viewer.png"))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:fail("Farm sheet pixels differ: "+str(sample.name));return
		model.calls.clear()
		for season in 4:click(view.position+view.tab_rect(season).get_center())
		if model.calls!=[["season",0],["season",1],["season",2],["season",3]]:fail("Resized season tab routing differs");return
	model.calls.clear();model.phase=Model.Phase.Applying;click(view.position+view.tab_rect(0).get_center())
	if model.calls!=[["season",0]]:fail("Pending farm request blocked local tab retirement");return
	model.calls.clear();view.input_allowed=func():return false
	click(view.position+view.tab_rect(0).get_center())
	if not model.calls.is_empty():fail("Farm sheet bypassed owner input gate");return
	view.input_allowed=Callable();model.phase=Model.Phase.Ready
	view.rename_requested.connect(func():model.calls.append(["rename"]))
	view.removal_requested.connect(func():model.calls.append(["remove"]))
	view.cancel_removal_requested.connect(func():model.calls.append(["cancel"]))
	root.size=Vector2i(1200,800);view.layout(Vector2(root.size));model.season=1
	for sample in fixture.header_pixel_reference.cases:
		model.snapshot=reference.snapshots["1"].duplicate(true);set_header(model,sample.semantic);model.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		var crop:=root.get_texture().get_image().get_region(Rect2i(420,56,478,700));crop.convert(Image.FORMAT_RGB8)
		crop.save_png(ProjectSettings.globalize_path("res://../../../build/"+str(sample.name)+"-viewer.png"))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:fail("Farm header pixels differ: "+str(sample.name));return
		model.calls.clear()
		click(view.position+Vector2(384,30));click(view.position+Vector2(416,30))
		click(view.position+view.tab_rect(0).get_center())
		if sample.semantic.removing:
			if view.body.visible or view.body.available() or not model.calls.is_empty():fail("Removing farm exposed crop/header controls");return
			click(view.position+view.cancel_rect().get_center())
			if model.calls!=[["cancel"]]:fail("Cancel removal routing differs: "+str(model.calls));return
			model.calls.clear();model.ticket=1;click(view.position+view.cancel_rect().get_center());model.ticket=0
			model.phase=Model.Phase.Applying;click(view.position+view.cancel_rect().get_center());model.phase=Model.Phase.Ready
			view.input_allowed=func():return false
			click(view.position+view.cancel_rect().get_center());view.input_allowed=Callable()
			if not model.calls.is_empty():fail("Cancel removal bypassed pending/owner gate");return
		else:
			if not view.body.visible or model.calls!=[["rename"],["remove"],["season",0]]:fail("Normal farm header routing differs");return
	for sample in fixture.rename_caption_reference.cases:
		model.snapshot=reference.snapshots["1"].duplicate(true);set_header(model,sample.semantic);model.changed.emit()
		if not view.begin_rename():fail("Ready farm rename did not begin");return
		view.name_entry.set_process(false);view.name_entry.cursor_visible=sample.cursor_visible;view.name_entry._refresh()
		if view.name_entry.value!=sample.draft or view.name_entry.text!=sample.caption:fail("Native editing caption differs: "+sample.name);return
		await process_frame;await RenderingServer.frame_post_draw
		var crop:=root.get_texture().get_image().get_region(Rect2i(420,56,478,700));crop.convert(Image.FORMAT_RGB8)
		crop.save_png(ProjectSettings.globalize_path("res://../../../build/"+str(sample.name)+"-viewer.png"))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:fail("Farm editing pixels differ: "+str(sample.name));return
		view.finish_rename()
	view.queue_free();world.queue_free();await process_frame
	print("FARM_SHEET_CAPTURE_PASS");quit(0)

func set_header(model,header: Dictionary) -> void:
	model.snapshot.custom_name=header.custom_name;model.snapshot.header_name=header.header_name
	model.snapshot.removing=header.removing;model.snapshot.removal_suspended=header.suspended;model.snapshot.removal_has_worker=header.has_worker
