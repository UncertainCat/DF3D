extends "res://tests/trade_goods_view_capture.gd"
const CounterView=preload("res://scripts/trade_counter_view.gd")
var dismiss_count:=0
func capture_counter(label: String,native_path: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-counter-view-"+label+".png")
	var native:=Image.load_from_file(native_path);native.convert(Image.FORMAT_RGBA8)
	var rect:=Rect2i(520,148,448,504)
	check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native counteroffer pixels differ: "+label)
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
	var view=CounterView.new();root.add_child(view);view.configure_counter(world);view.position=Vector2(520,148);view.layout(Vector2(448,504));view.set_page(page,icons,int(OS.get_environment("DF3D_COUNTER_GOODS_ROWS")) if not OS.get_environment("DF3D_COUNTER_GOODS_ROWS").is_empty() else -1)
	view.dismissed.connect(func():dismiss_count+=1)
	for i in 5:await process_frame
	await capture_counter("initial",OS.get_environment("DF3D_COUNTER_NATIVE"))
	if OS.get_environment("DF3D_COUNTER_LONG")=="1":
		for step in [["down",Vector2(952,646),1],["up",Vector2(952,190),0],["track",Vector2(952,610),6]]:
			await click(step[1]);check(view.scrollbar.first==step[2],"Native counteroffer scroll offset differs: "+step[0])
			var motion:=InputEventMouseMotion.new();motion.position=Vector2.ZERO;Input.parse_input_event(motion)
			for i in 3:await process_frame
			await capture_counter(step[0],directory+"/depot-trade-long-counter-"+step[0]+".png")
		view.input_allowed=func():return false
		await click(Vector2(952,190));check(view.scrollbar.first==6,"Disabled counteroffer scrolled")
		view.input_allowed=Callable()
		var native: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-trade-native.json"))
		var probes: Array=native.exchange.negotiation.long_counter.get("inputs",[])
		for probe in probes:
			view.scrollbar.move_to(0)
			var label: String=probe.label
			if label.begins_with("drag-"):
				var move:=InputEventMouseMotion.new();move.position=Vector2(952,220);root.push_input(move,true);await process_frame
				var press:=InputEventMouseButton.new();press.position=move.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true);await process_frame
				move=InputEventMouseMotion.new();move.position=Vector2(952,int(label.trim_prefix("drag-")));move.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(move,true);await process_frame
				check(view.scrollbar.dragging==probe.held,"Native drag ownership differs: "+label)
				press=InputEventMouseButton.new();press.position=move.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=false;root.push_input(press,true);await process_frame
				check(not view.scrollbar.dragging and probe.released,"Counteroffer drag did not release")
			else:
				var point: Vector2={"body-wheel":Vector2(600,300),"bar-wheel":Vector2(952,300),"heading-wheel":Vector2(600,160),"outside-wheel":Vector2.ZERO,"body-page":Vector2(600,300),"standard":Vector2(600,300)}[label]
				if label=="standard":
					var key:=InputEventKey.new();key.keycode=KEY_DOWN;key.pressed=true;root.push_input(key,true);await process_frame
					key=key.duplicate();key.pressed=false;root.push_input(key,true);await process_frame
				else:
					var move:=InputEventMouseMotion.new();move.position=point;root.push_input(move,true);await process_frame
					var wheel:=InputEventMouseButton.new();wheel.position=point;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.shift_pressed=label=="body-page";root.push_input(wheel,true);await process_frame
					wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true);await process_frame
			check(view.scrollbar.first==int(probe.offset),"Native counteroffer input differs: "+label)
	await click(Vector2(920,166));check(dismiss_count==1,"Okay did not dispatch once")
	view.input_allowed=func():return false
	await click(Vector2(920,166));check(dismiss_count==1,"Disabled Okay dispatched")
	view.set_page({},{});check(view.scrollbar.first==0 and not view.scrollbar.visible,"Closed counteroffer retained scroll")
	view.queue_free();await process_frame
	if OS.get_environment("DF3D_COUNTER_LONG")=="1":
		var service=CatalogTest.Service.new();root.add_child(service)
		var model=Goods.new();model.configure(service);model.pages=recorded.pages;model.phase=Goods.Phase.Active;model.session=9007199254740993;model.revision=1
		model.counter_page=page.duplicate(true);model.counter_page.total=90
		for id in recorded.appearances:model.appearances[int(id)]=recorded.appearances[id]
		var body=View.new();root.add_child(body);body.configure_goods(world,model);body.layout(Vector2(944,708))
		body.counter.scrollbar.move_to(225)
		for i in 3:await process_frame
		check(model.counter_offset==75 and model.counter_limit==13,"Scrolled counteroffer did not fetch the missing page")
		check(model.phase==Goods.Phase.GoodsReading,"Counteroffer paging failed to retain pending ownership")
		model.close();check(body.counter.scrollbar.first==0 and not body.counter.visible,"Closing pending counteroffer did not retire scroll")
		body.queue_free();await process_frame;model.dispose();service.queue_free();await process_frame
	world.queue_free();await process_frame
	if not failed:print("TRADE_COUNTER_VIEW_PASS")
	quit(1 if failed else 0)
