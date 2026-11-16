extends "res://tests/trade_goods_view_capture.gd"
const CounterView=preload("res://scripts/trade_counter_view.gd")
var dismiss_count:=0
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var page: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-counter-page.json")))
	var recorded: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DF3D_COUNTER_ART"))))
	var icons: Dictionary={}
	for row in page.rows:
		var appearance: Dictionary=recorded.appearances.get(str(row.id),{})
		check(not appearance.is_empty(),"Counteroffer artwork missing: "+str(row.id))
		icons[row.id]=world.ammunition_icon(appearance,row.id) if row.type==39 else world.item_sheet_icon(row.type,appearance,row.id)
	var view=CounterView.new();root.add_child(view);view.configure_counter(world);view.position=Vector2(520,148);view.layout(Vector2(448,504));view.set_page(page,icons)
	view.dismissed.connect(func():dismiss_count+=1)
	for i in 5:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-counter-view.png")
		var native:=Image.load_from_file(OS.get_environment("DF3D_COUNTER_NATIVE"));native.convert(Image.FORMAT_RGBA8)
		var rect:=Rect2i(520,148,448,504)
		check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native counteroffer pixels differ")
	await click(Vector2(920,166));check(dismiss_count==1,"Okay did not dispatch once")
	view.input_allowed=func():return false
	await click(Vector2(920,166));check(dismiss_count==1,"Disabled Okay dispatched")
	view.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_COUNTER_VIEW_PASS")
	quit(1 if failed else 0)
