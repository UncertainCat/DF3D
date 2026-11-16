extends "res://tests/trade_goods_view_capture.gd"
const Footer=preload("res://scripts/trade_footer_view.gd")
func caption(bytes: Array) -> String:
	var result:=""
	for byte in bytes:
		var code: int=int(byte)
		if byte>0 and byte<32:code=preload("res://scripts/original_ui.gd").CP437_SYMBOLS[int(byte)-1]
		elif byte>=128:code=preload("res://scripts/original_ui.gd").CP437_HIGH[int(byte)-128]
		result+=String.chr(code)
	return result
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var native_data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-trade-native.json")))
	var row: Dictionary={}
	for value in native_data.cases:
		if value.label=="speaker":row=value;break
	var totals: Dictionary=row.value_totals;var capacity: Dictionary=row.capacity
	var service=CatalogTest.Service.new();root.add_child(service)
	var model=Goods.new();model.configure(service);model.session=9007199254740993;model.revision=1;model.phase=Goods.Phase.Active
	model.pages=[{"rows":[],"total":0},{"rows":[],"total":0}];model.entry={"title":row.title,"fortress":row.fortname}
	model.footer={"merchant_value":caption(totals.value_captions[0]),"fortress_value":caption(totals.value_captions[1]),"profit":caption(totals.profit_caption),"profit_color":totals.profit_color,"capacity":caption(capacity.caption),"capacity_color":capacity.color}
	var view=Footer.new();root.add_child(view);view.configure_footer(world,model);view.position=Vector2(48,676);view.layout(Vector2(944,708))
	for i in 5:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-footer-view.png")
		var native:=Image.load_from_file(directory+"/depot-trade-speaker.png");native.convert(Image.FORMAT_RGBA8)
		for rect in [Rect2i(48,676,448,36),Rect2i(520,676,440,36),Rect2i(48,712,216,12)]:
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native trade footer pixels differ: "+str(rect))
	for index in 4:
		model.phase=Goods.Phase.Active;model.ticket=0;var before: int=service.next
		await click(view.position+view.buttons[index].get_center())
		check(service.next==before+1,"Footer bulk action did not dispatch once")
		var intent: Dictionary=service.calls.get(service.next,{}).get("intent",{})
		check(intent.get("side")==int(index/2) and intent.get("operation")== (C.TradeDraftOperation.MarkAll if index%2==0 else C.TradeDraftOperation.UnmarkAll),"Footer bulk action chose wrong native intent")
	view.queue_free();await process_frame;model.dispose();service.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_FOOTER_VIEW_PASS")
	quit(1 if failed else 0)
