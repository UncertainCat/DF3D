extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "depot-goods-scene-expected.json"
func result_filename() -> String:return "depot-goods-scene-result.json"
func goods_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.goods.phase==owner.goods.Phase.Ready and not owner.goods.appearance_pending() and not owner.goods_view.requested:
			return check(owner.goods_mode and owner.goods_view.visible and not owner.panel.visible and scene._ui.host.active==owner,"Goods picker lost exclusive ownership")
		await create_timer(0.01).timeout
	return check(false,"Goods did not settle: "+str(owner.goods.phase))
func open_goods() -> bool:
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,114))
	return await goods_ready()
func close_goods() -> bool:
	key(KEY_ESCAPE)
	var deadline:=Time.get_ticks_msec()+10000
	while owner.goods_mode and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	if not check(not owner.goods_mode and owner.goods.phase==owner.goods.Phase.Closed,"Escape did not finish and return from goods"):return false
	return check(scene._ui.host.active==null and owner.state.building_id<0 and not owner.panel.visible,"Goods close retained parent selection")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture");owner.open_target(int(expected.id))
	if not await chest_ready() or not await open_goods():return
	check(owner.goods.category==45 and owner.goods.groups.size()==1,"Initial native Anvils category differs")
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(500,500);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(directory+"/depot-goods-scene-initial.png")
	var native:=Image.load_from_file(directory+"/depot-goods-initial.png");native.convert(Image.FORMAT_RGBA8);image.convert(Image.FORMAT_RGBA8)
	var rect:=Rect2i(32,52,944,708)
	check(image.get_region(rect).get_data()==native.get_region(rect).get_data(),"Main-scene goods panel pixels differ")
	for desired in [true,false]:
		await pointer(owner.goods_view.get_global_transform_with_canvas()*Vector2(896,78))
		if not await goods_ready():return
		check(owner.goods.groups[0].flags==(1 if desired else 2),"Group checkbox did not stage native choices")
		if not await close_goods():return
		owner.open_target(int(expected.id))
		if not await chest_ready():return
		check(owner.state.snapshot.depot.awaiting_items==(2 if desired else 0),"Reopened depot awaiting count differs")
		if desired and not await open_goods():return
	# Host teardown retires a pending read without committing or replaying it.
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,114))
	owner.close_panel();await drain()
	check(owner.goods.phase==owner.goods.Phase.Closed and not owner.goods_view.visible and scene._ui.host.active==null,"Teardown retained goods ownership")
	exercised=true
