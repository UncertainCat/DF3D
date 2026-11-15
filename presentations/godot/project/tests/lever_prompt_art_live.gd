extends "res://tests/lever_wire_live.gd"
func inspect_prompt(snapshot: Dictionary,_expected: Dictionary) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Lever prompt assets unavailable"):return
	root.size=Vector2i(1200,800)
	var items: Array=[]
	for id in [snapshot.source_mechanism,snapshot.target_mechanism]:
		var response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":id})
		var item: Dictionary=response.get("production",{}).get("independent_item",{}).get("snapshot",{})
		if not check(item.get("id",-1)==id and item.has("appearance"),"Mechanism item artwork unavailable"):return
		items.append(item)
	var model=preload("res://scripts/lever_state.gd").new();model.building_id=55;model.snapshot=snapshot;model.phase=model.Phase.Targeting
	var view=preload("res://scripts/lever_link_view.gd").new();root.add_child(view)
	view.position=Vector2(32,52);view.configure(world,model,"Main Water Control");view.set_items(items)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();view.refresh()
		if view.ready_art():break
		await create_timer(0.02).timeout
	check(view.ready_art(),"Lever mechanism textures did not arrive")
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var crop:=Rect2i(32,52,456,156);var actual:=image.get_region(crop)
	actual.save_png(directory+"/lever-prompt-viewer.png")
	var native:=Image.load_from_file(directory+"/lever-link-reopened.png");native.convert(Image.FORMAT_RGB8)
	check(actual.get_data()==native.get_region(crop).get_data(),"Native lever prompt pixels differ")
	view.queue_free();await process_frame
