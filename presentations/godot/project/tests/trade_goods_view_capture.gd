extends "res://tests/trade_goods_art_wire_live.gd"
const View=preload("res://scripts/trade_goods_view.gd")
const Goods=preload("res://scripts/trade_goods_state.gd")
const CatalogTest=preload("res://tests/trade_catalog_state_test.gd")
func click(point: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true);await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;root.push_input(event,true);await process_frame
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade assets missing"):quit(1);return
	var recorded: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-goods-art-wire-result.json")))
	var service=CatalogTest.Service.new();root.add_child(service)
	var model=Goods.new();model.configure(service);model.pages=recorded.pages;model.phase=Goods.Phase.Active;model.session=9007199254740993;model.revision=1
	for id in recorded.appearances:model.appearances[int(id)]=recorded.appearances[id]
	var view=View.new();root.add_child(view);view.configure_goods(world,model);view.position=Vector2(48,148);view.layout(Vector2(944,708))
	for i in 5:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-goods-view.png")
		var native:=Image.load_from_file(directory+"/trade-goods-art-wire.png");native.convert(Image.FORMAT_RGBA8)
		for rect in [Rect2i(48,148,448,504),Rect2i(520,148,440,504)]:
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native trade goods pixels differ: "+str(rect))
	var cases: Array=[{"point":Vector2(468,238),"operation":C.TradeDraftOperation.Item,"item":992},{"point":Vector2(468,202),"operation":C.TradeDraftOperation.Group,"type":4},{"point":Vector2(100,202),"operation":C.TradeDraftOperation.ExpandGroup,"type":4},{"point":Vector2(570,382),"operation":C.TradeDraftOperation.ExpandContainer,"item":3148},{"point":Vector2(916,238),"operation":C.TradeDraftOperation.Item,"item":1180}]
	for sample in cases:
		model.phase=Goods.Phase.Active;model.ticket=0;view.refresh();var before: int=service.next
		await click(sample.point)
		check(service.next==before+1,"Trade row click did not dispatch once")
		var intent: Dictionary=service.calls.get(service.next,{}).get("intent",{})
		for key in sample:
			if key!="point":check(intent.get(key)==sample[key],"Visible row chose wrong native intent: "+str(sample))
	model.phase=Goods.Phase.Active;model.ticket=0;view.refresh();await click(Vector2(100,166))
	for letter in "iron":
		var key:=InputEventKey.new();key.pressed=true;key.unicode=letter.unicode_at(0);root.push_input(key,true);await process_frame
	check(model._queued_filters.get(0)=="IRON","Visible filter lost pending typing")
	await click(Vector2(100,166),MOUSE_BUTTON_RIGHT);check(model.phase==Goods.Phase.Closed,"Trade body did not close")
	view.queue_free();await process_frame;model.dispose();service.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_GOODS_VIEW_PASS")
	quit(1 if failed else 0)
