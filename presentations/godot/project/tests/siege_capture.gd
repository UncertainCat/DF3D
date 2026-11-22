extends "res://tests/cage_picker_capture.gd"
func run() -> void:
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_SIEGE_CAPTURE")
	if directory.is_empty():quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/siege-building-wire-result.json")))
	var model=preload("res://scripts/building_header_state.gd").new()
	var panel=preload("res://scripts/siege_sheet_view.gd").new();root.add_child(panel)
	panel.configure(world,model);panel.layout(Vector2(1200,800))
	var error:=0;var checked:=0
	for receipt in data.receipts:
		if receipt.siege.action!=0:continue
		if receipt.siege.type==2 and receipt.siege.resting!=0:continue
		for action in 5:
			model.snapshot=receipt.duplicate(true);model.snapshot.siege.action=action
			model.building_id=model.snapshot.id;model.phase=model.Phase.Ready;model.changed.emit()
			for i in 3:await process_frame;await RenderingServer.frame_post_draw
			var rendered:=root.get_texture().get_image()
			var name: String="siege-"+str(receipt.siege.type)+"-action-"+str(action)
			rendered.save_png(directory+"/"+name+"-view.png")
			var reference: String="siege-"+str(receipt.siege.type)+"-practice-reopened" if action==4 and receipt.siege.type!=2 else name
			var native:=Image.load_from_file(directory+"/"+reference+".png")
			var bounds:=Rect2i(432,136,456,364)
			var actual:=rendered.get_region(bounds);actual.convert(Image.FORMAT_RGB8)
			var expected:=native.get_region(bounds);expected.convert(Image.FORMAT_RGB8)
			if actual.get_data()!=expected.get_data():push_error("Native siege body differs: "+name);error=1
			checked+=1
	print("SIEGE_BODY_CAPTURE ",error," cases ",checked)
	panel.queue_free();world.queue_free();await process_frame;quit(error)
