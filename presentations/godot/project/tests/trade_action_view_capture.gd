extends "res://tests/trade_goods_view_capture.gd"
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-buttons-result.json")))
	var extra:=directory+"/trade-buttons-extra-cases.json"
	if FileAccess.file_exists(extra):data.cases.append_array(integers(JSON.parse_string(FileAccess.get_file_as_string(extra))))
	var service=CatalogTest.Service.new();root.add_child(service)
	var model=Goods.new();model.configure(service);model.session=9007199254740993;model.revision=1;model.phase=Goods.Phase.Active
	model.pages=[{"rows":[],"total":0},{"rows":[],"total":0}]
	var view=preload("res://scripts/trade_action_view.gd").new();root.add_child(view);view.configure_actions(world,model);view.position=Vector2(48,712);view.layout(Vector2(944,708))
	for row in data.cases:
		view.set_actions(row.actions)
		for i in 3:await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-buttons-view-"+row.label+".png")
			var native:=Image.load_from_file(row.get("native_image",directory+"/trade-buttons-"+row.label+".png"));native.convert(Image.FORMAT_RGBA8)
			for button in view.buttons:
				var rect:=Rect2i(button.position+view.position,button.size)
				check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native action pixels differ: "+row.label+" "+str(rect))
		for index in view.buttons.size():
			model.phase=Goods.Phase.Active;model.ticket=0;var before: int=service.next
			await click(view.position+view.buttons[index].get_center())
			check(service.next==before+(1 if row.actions[index].enabled else 0),"Action enablement mismatch")
			if row.actions[index].enabled:check(service.calls[service.next].intent.action==[C.ManagementAction.TradeSessionSeize,C.ManagementAction.TradeSessionExchange,C.ManagementAction.TradeSessionGift][index],"Wrong native action dispatched")
	view.queue_free();await process_frame;model.dispose();service.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_ACTION_VIEW_PASS")
	quit(1 if failed else 0)
