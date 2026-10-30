extends "res://tests/item_carrier_wire_live.gd"
func inspect_render(snapshot: Dictionary) -> void:
	if not check(DisplayServer.get_name()!="headless","Carrier capture requires renderer"):return
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Carrier assets unavailable"):return
	root.size=Vector2i(488,708)
	var view=preload("res://scripts/item_sheet_view.gd").new();root.add_child(view);view.configure(world)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();view.present(snapshot)
		if view.carrier_icon!=null:break
		await create_timer(0.02).timeout
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(directory+"/carrier-"+str(snapshot.carrier.kind)+"-viewer.png")
	var kind: String="container" if snapshot.carrier.kind==1 else "unit"
	var native:=Image.load_from_file(directory+"/farm-item-carrier-"+kind+".png")
	native.convert(Image.FORMAT_RGB8);native=native.get_region(Rect2i(416,52,488,708))
	var matched:=native.get_data()==image.get_data()
	check(matched,"Native carrier panel pixels differ: "+kind)
	var file:=FileAccess.open(directory+"/carrier-art-"+str(snapshot.carrier.kind)+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"icon_available":view.carrier_icon!=null,"full_panel_match":matched}));file.close()
	var calls: Array=[];view.carrier_requested.connect(func(kind,id):calls.append([kind,id]))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=view.holder_rect().get_center();root.push_input(event,true)
	check(calls==[[snapshot.carrier.kind,snapshot.carrier.id]],"Carrier View intent differs")
	view.queue_free();await process_frame
