extends "res://tests/trade_goods_view_capture.gd"
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var after_reference:=OS.get_environment("DF3D_TRADE_AFTER_REFERENCE")
	var saved: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-transfer-wire-result.json")))
	var data: Dictionary=saved.before_view if after_reference.is_empty() else saved.after_view
	var service=CatalogTest.Service.new();root.add_child(service)
	var model=Goods.new();model.configure(service);model.phase=Goods.Phase.Active;model.session=9007199254740993;model.revision=1
	model.pages=data.pages;model.header=data.header;model.footer=data.footer;model.actions=data.actions;model.entry=data.entry;model.conversation=data.get("conversation",{})
	for id in data.appearances:model.appearances[int(id)]=data.appearances[id]
	var view=preload("res://scripts/trade_view.gd").new();root.add_child(view);view.configure_trade(world,model);view.layout(Vector2(1200,800))
	for i in 5:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-composite-view.png")
		var native:=Image.load_from_file(directory+"/trade-transfer-wire.png" if after_reference.is_empty() else after_reference);native.convert(Image.FORMAT_RGBA8)
		var regions: Array=[Rect2i(32,52,944,708),Rect2i(32,52,944,12),Rect2i(32,748,944,12),Rect2i(32,64,8,684),Rect2i(968,64,8,684),Rect2i(40,136,928,12),Rect2i(40,664,928,12),Rect2i(504,148,8,516)]
		if not after_reference.is_empty():regions=[Rect2i(40,64,928,72)]
		for rect in regions:
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native Trade chrome differs: "+str(rect))
	await click(Vector2(508,730));check(service.calls[service.next].intent.action==C.ManagementAction.TradeSessionExchange,"Composite Trade button missed")
	model.phase=Goods.Phase.Active;model.ticket=0
	await click(Vector2(100,166),MOUSE_BUTTON_RIGHT);check(model.phase==Goods.Phase.Closed,"Composite Trade did not close")
	view.queue_free();await process_frame;model.dispose();service.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_COMPOSITE_VIEW_PASS")
	quit(1 if failed else 0)
