extends "res://tests/trade_goods_view_capture.gd"
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var saved: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-exchange-wire-result.json")))
	var samples: Array=[["counter_view",directory+"/depot-trade-counteroffer.png"],["accepted_view",OS.get_environment("DF3D_COUNTER_ACCEPTED_NATIVE")]]
	if not saved.get("active_okay_view",{}).is_empty():samples.append(["active_okay_view",OS.get_environment("DF3D_COUNTER_ACCEPTED_NATIVE").get_base_dir()+"/depot-trade-active-okay.png"])
	for sample in samples:
		var data: Dictionary=saved[sample[0]]
		var service=CatalogTest.Service.new();root.add_child(service)
		var model=Goods.new();model.configure(service);model.phase=Goods.Phase.Active;model.session=9007199254740993;model.revision=1
		model.pages=data.pages;model.header=data.header;model.footer=data.footer;model.actions=data.actions;model.entry=data.entry;model.conversation=data.conversation;model.counter_page=data.counter_page
		for id in data.appearances:model.appearances[int(id)]=data.appearances[id]
		var view=preload("res://scripts/trade_view.gd").new();root.add_child(view);view.configure_trade(world,model);view.layout(Vector2(1200,800))
		for i in 5:await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-composite-"+sample[0]+".png")
			var native:=Image.load_from_file(sample[1]);native.convert(Image.FORMAT_RGBA8)
			var rect:=Rect2i(32,52,944,708)
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native composite counteroffer differs: "+sample[0])
		await click(view.frame.position+view.actions.position+view.actions.buttons[1].get_center())
		check(service.calls[service.next].intent.action==C.ManagementAction.TradeSessionExchange,"Counteroffer action missed")
		model.phase=Goods.Phase.Active;model.ticket=0;model.changed.emit()
		if not data.counter_page.is_empty():await click(Vector2(920,166));check(service.calls[service.next].intent.action==C.ManagementAction.TradeSessionDismiss,"Counteroffer Okay missed")
		view.queue_free();await process_frame;model.dispose();service.queue_free();await process_frame
	world.queue_free();await process_frame
	if not failed:print("TRADE_COUNTER_COMPOSITE_PASS")
	quit(1 if failed else 0)
