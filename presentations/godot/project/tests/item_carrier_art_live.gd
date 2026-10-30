extends "res://tests/item_carrier_wire_live.gd"
func inspect_render(snapshot: Dictionary) -> void:
	if not check(DisplayServer.get_name()!="headless","Carrier capture requires renderer"):return
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Carrier assets unavailable"):return
	var box: bool=snapshot.item_type in [13,30]
	var kind: String=("box" if snapshot.item_type==30 else "instrument-"+str(snapshot.id)) if box else "container" if snapshot.carrier.kind==1 else "unit"
	var label: String=kind if box else str(snapshot.carrier.kind)
	if box and snapshot.has("holder"):
		snapshot=snapshot.duplicate(true);snapshot.holder_id=snapshot.holder.id
		snapshot.holder_name="In "+snapshot.holder.name;snapshot.holder_art="BUILDING_ICON_BOX"
	root.size=Vector2i(488,708)
	var view=preload("res://scripts/item_sheet_view.gd").new();root.add_child(view);view.configure(world)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();view.present(snapshot)
		if (view.icon if box else view.carrier_icon)!=null:break
		await create_timer(0.02).timeout
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(directory+"/carrier-"+label+"-viewer.png")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/carrier-expected.json"))
	var reference: String=expected.get("native_reference","farm-item-carrier-container-view" if box else "farm-item-carrier-"+kind)
	var native:=Image.load_from_file(directory+"/"+reference+".png")
	native.convert(Image.FORMAT_RGB8);native=native.get_region(Rect2i(416,52,488,708))
	var matched:=native.get_data()==image.get_data()
	check(matched,"Native carrier panel pixels differ: "+kind)
	var file:=FileAccess.open(directory+"/carrier-art-"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"icon_available":(view.icon if box else view.carrier_icon)!=null,"full_panel_match":matched}));file.close()
	var calls: Array=[]
	if box:view.holder_requested.connect(func(id):calls.append([id]))
	else:view.carrier_requested.connect(func(kind,id):calls.append([kind,id]))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=view.holder_rect().get_center();root.push_input(event,true)
	check(calls==([[snapshot.holder.id]] if box else [[snapshot.carrier.kind,snapshot.carrier.id]]),"View intent differs")
	view.queue_free();await process_frame
