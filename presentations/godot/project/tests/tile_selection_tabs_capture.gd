extends "res://tests/farm_body_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var directory:=OS.get_environment("DF3D_SELECTION_REFERENCE")
	if directory.is_empty():quit(77);return
	root.size=Vector2i(320,160)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Selection assets unavailable");return
	var view=preload("res://scripts/tile_selection_tabs.gd").new();root.add_child(view);view.configure(world)
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var calls: Array=[];view.alternative_requested.connect(func(index):calls.append(index));view.enabled=true
	for name in ["tabs-building","item-group","item-member"]:
		var sample: Dictionary=reference.tile_selection_reference[name].state
		var tabs: Array=[]
		for row in sample.tabs:tabs.append({"kind":int(row.kind)+1,"id":int(row.id)})
		view.set_selection({"open":true,"kind":int(sample.active_kind)+1,"id":int(sample.active_id),"alternatives":tabs})
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		actual.save_png(directory+"/viewer-tabs-"+name+".png")
		var native:=Image.load_from_file(directory+"/workshop-selection-"+name+".png");native.convert(Image.FORMAT_RGB8)
		# Group tab has no icon; compare its complete frame and interior. The
		# building uses a separately supplied icon, so compare only its left join.
		for y in 72:
			for x in 40:
				if y<36 and x>=8:continue
				if actual.get_pixel(x,y)!=native.get_pixel(896+x,52+y):fail("Selection frame differs: %s at %d,%d"%[name,x,y]);return
	click(Vector2(20,54))
	if calls!=[1]:fail("Selection tab did not route ordered index");return
	view.enabled=false;click(Vector2(20,18))
	if calls!=[1]:fail("Pending selection accepted tab input");return
	view.queue_free();world.queue_free();await process_frame
	print("TILE_SELECTION_TABS_CAPTURE_PASS");quit(0)
