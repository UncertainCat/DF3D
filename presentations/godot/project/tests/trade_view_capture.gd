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
		if not after_reference.is_empty():regions=[Rect2i(40,64,928,72+view.header.extra_rows()*12),Rect2i(40,136+view.header.extra_rows()*12,928,12)]
		for rect in regions:
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native Trade chrome differs: "+str(rect))
	if not after_reference.is_empty() and data.header.lines.size()>8:
		check(view.goods.position.y==156 and view.goods.size.y==444,"Announcement did not move and shorten goods area")
		var reference_dir:=after_reference.get_base_dir()
		await click(Vector2(700,178));check(view.header.scrollbar.first==5,"Announcement track did not page to the end")
		await announcement_capture(reference_dir+"/depot-trade-announcement-down.png","down")
		await click(Vector2(700,94));check(view.header.scrollbar.first==0,"Announcement track did not page to the start")
		await announcement_capture(reference_dir+"/depot-trade-announcement-up.png","up")
		await click(Vector2(700,190));check(view.header.scrollbar.first==1,"Announcement arrow did not move one line")
		await announcement_capture(reference_dir+"/depot-trade-announcement-arrow.png","arrow")
		await click(Vector2(700,82));check(view.header.scrollbar.first==0,"Announcement arrow did not return to the start")
	await click(Vector2(508,730));check(service.calls[service.next].intent.action==C.ManagementAction.TradeSessionExchange,"Composite Trade button missed")
	model.phase=Goods.Phase.Active;model.ticket=0
	await click(Vector2(100,166),MOUSE_BUTTON_RIGHT);check(model.phase==Goods.Phase.Closed,"Composite Trade did not close")
	check(view.goods.position.y==96 and not view.header.scrollbar.visible and view.header.scrollbar.first==0,"Closing retained announcement layout or scrolling")
	view.queue_free();await process_frame;model.dispose();service.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_COMPOSITE_VIEW_PASS")
	quit(1 if failed else 0)

func announcement_capture(reference: String,label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	# Protected native captures have no pointer over this scrollbar.
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8)
	rendered.save_png(directory+"/trade-announcement-"+label+".png")
	var native:=Image.load_from_file(reference);native.convert(Image.FORMAT_RGBA8)
	var rect:=Rect2i(40,64,928,132)
	check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native announcement scroll pixels differ: "+label)
