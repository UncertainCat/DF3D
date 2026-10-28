extends "res://tests/farm_body_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Farm assets unavailable");return
	var model:=Model.new()
	var view=preload("res://scripts/farm_sheet_view.gd").new();root.add_child(view);view.configure(world,model)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var reference: Dictionary=fixture.sheet_resize_reference
	for sample in reference.cases:
		root.size=Vector2i(int(sample.viewport[0]),int(sample.viewport[1]));view.layout(Vector2(root.size))
		model.season=int(sample.selected_season);model.snapshot=reference.snapshots[str(model.season)].duplicate(true);model.changed.emit()
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
	model.calls.clear();view.input_allowed=func():return false;click(view.position+view.tab_rect(0).get_center())
	if not model.calls.is_empty():fail("Farm sheet bypassed owner input gate");return
	view.queue_free();world.queue_free();await process_frame
	print("FARM_SHEET_CAPTURE_PASS");quit(0)
