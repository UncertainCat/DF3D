extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "unit-expel-wire-expected.json"
func result_filename() -> String:return "unit-expel-wire-apply.json"
func exercise(expected: Dictionary) -> void:
	var inspector=scene._ui.controller("inspector")
	var target:=int(expected.unit_id)
	inspector.open_target(Vector3i.ZERO,1,target)
	var deadline:=Time.get_ticks_msec()+10000
	while not is_instance_valid(inspector.expel_button) and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	if not check(is_instance_valid(inspector.expel_button),"Main-scene Expel button unavailable"):return
	var model=inspector.expel
	await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18));await drain()
	if not check(model.phase in [model.Phase.Choosing,model.Phase.Confirming],"Expel preview unavailable"):return
	var preview:Dictionary=model.snapshot()
	check(preview.units.size()==expected.units.size(),"Main-scene affected group length differs")
	for index in mini(preview.units.size(),expected.units.size()):
		check(preview.units[index].id==int(expected.units[index].id) and preview.units[index].name==expected.units[index].name,"Main-scene affected creature differs")
	if model.phase==model.Phase.Choosing:
		var choice=inspector.expel_view.get_node_or_null("Destination_"+str(int(expected.destination)))
		if not check(is_instance_valid(choice),"Native destination missing from visible chooser"):return
		await pointer(choice.get_global_transform_with_canvas()*(choice.size/2))
	if not check(model.phase==model.Phase.Confirming and model.destination_id==int(expected.destination),"Destination click did not select native site"):return
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	actual.save_png(directory+"/unit-expel-confirm-scene.png")
	var mode:="expel" if int(expected.destination)==-1 else "send"
	var native:=Image.load_from_file(directory+"/unit-expel-effect-"+mode+"-before.png");native.convert(Image.FORMAT_RGB8)
	check(actual.get_region(Rect2i(424,160,472,588)).get_data()==native.get_region(Rect2i(424,160,472,588)).get_data(),"Main-scene confirmation pixels differ")
	if failed:return
	var completed:Array=[]
	model.applied.connect(func(id):completed.append(id))
	var confirm=inspector.expel_view.get_node("ConfirmExpel")
	await pointer(confirm.get_global_transform_with_canvas()*(confirm.size/2))
	check(model.phase==model.Phase.Applying,"Final button did not submit departure")
	await drain();await process_frame
	check(completed==[target] and model.phase==model.Phase.Closed,"Final departure did not complete once and retire preview")
	check(inspector.is_open() and scene._ui.host.active==inspector,"Successful departure lost native sheet navigation")
	deadline=Time.get_ticks_msec()+5000
	while is_instance_valid(inspector.expel_button) and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	check(not is_instance_valid(inspector.expel_button),"Departing creature retained Expel control")
	exercised=true
