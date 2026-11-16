extends "res://tests/trade_goods_view_capture.gd"
const Header=preload("res://scripts/trade_header_view.gd")
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var native_data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-trade-native.json")))
	var view=Header.new();root.add_child(view);view.configure_header(world);view.position=Vector2(40,64);view.layout(Vector2(944,708))
	for sample in native_data.cases:
		if not sample.has("header"):continue
		var header: Dictionary=sample.header.cases[0].header.duplicate(true)
		if header.has("appearance"):
			header.appearance.tile_pages=header.appearance.pages;header.appearance.erase("pages")
		view.set_header(header)
		if int(header.speaker)>=0:check(view.speaker!=null,"Merchant recipe did not resolve")
		for i in 5:await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-header-view-"+sample.label+".png")
			var native:=Image.load_from_file(directory+"/depot-trade-"+sample.label+".png");native.convert(Image.FORMAT_RGBA8)
			var rect:=Rect2i(40,64,928,72)
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native trade header pixels differ: "+sample.label)
	view.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_HEADER_VIEW_PASS")
	quit(1 if failed else 0)
