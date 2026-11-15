extends "res://tests/building_links_wire_live.gd"
func inspect_render(snapshot: Dictionary) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Link row assets unavailable"):return
	root.size=Vector2i(472,216)
	var model=preload("res://scripts/building_links_state.gd").new()
	model.building_id=snapshot.building_id;model.snapshot=snapshot;model.phase=model.Phase.Ready
	var view=preload("res://scripts/building_links_view.gd").new();root.add_child(view);view.configure(world,model)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();view.refresh()
		var ready:=true
		for index in snapshot.rows.size():ready=ready and view.icons.get(index)!=null
		if ready:break
		await create_timer(0.02).timeout
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(0,0,472,snapshot.rows.size()*36)
	image=image.get_region(region);image.save_png(directory+"/building-links-"+str(snapshot.building_id)+"-rows-viewer.png")
	var native:=Image.load_from_file(directory+"/building-links-"+str(snapshot.building_id)+"-left-tab.png");native.convert(Image.FORMAT_RGB8)
	check(image.get_data()==native.get_region(Rect2i(424,544,472,region.size.y)).get_data(),"Native linked row pixels differ")
	var calls: Array=[];view.recenter_requested.connect(func(tile):calls.append(tile))
	for point in [Vector2(100,18),view.recenter_rect(0).get_center()]:
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true)
		await process_frame
	var first: Dictionary=snapshot.rows[0]
	check(calls==[Vector3i(first.x,first.y,first.z)],"Linked row recenter intent differs")
	view.queue_free();await process_frame
