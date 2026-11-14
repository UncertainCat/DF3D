extends "res://tests/tile_selection_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.tile_selection_reference.unit_group
	var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
	var ui=scene._ui
	ui.focus_tile(point)
	var deadline:=Time.get_ticks_msec()+10000
	while world.inspect_entity(1,int(sample.member.id)).is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	ui.open_tile_selection(point)
	var selection=ui.tile_selection
	var model=selection.navigation.state
	if not await selection_ready(model):return
	check(ui.host.active==selection and model.snapshot.kind==6,"Default unit group did not acquire panel")
	await panel_capture("unit-group","workshop-selection-unit-group")
	await pointer(Vector2(600,118))
	if not await selection_ready(model):return
	owner=ui.controller("inspector")
	if not check(ui.host.active==owner and owner.selected.get("id")==int(sample.member.id),"Unit group opened wrong creature"):return
	deadline=Time.get_ticks_msec()+10000
	while owner.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.05).timeout
	check(not owner.creature_display.get("detail",{}).is_empty(),"Creature detail did not arrive")
	check(selection.tabs.visible and selection.tabs.selected==-1,"Creature member lost selection tabs")
	var facts_file:=FileAccess.open(directory+"/selection-unit-detail.json",FileAccess.WRITE)
	facts_file.store_string(JSON.stringify(owner.creature_display));facts_file.close()
	# Creature facts trigger an asynchronous control rebuild and font shaping.
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/workshop-selection-unit-group-member.png");native.convert(Image.FORMAT_RGB8)
	actual.get_region(Rect2i(416,52,488,708)).save_png(directory+"/selection-unit-member-live.png")
	# Compare header and Overview summaries, including all divider cells.
	# Cached randomized quote text retains its separate fidelity limitation.
	var header:=Rect2i(416,52,488,492)
	check(actual.get_region(header).get_data()==native.get_region(header).get_data(),"Creature header or Overview grid differs from native")
	var has_history: bool=sample.member.report_counts.any(func(count):return count>0)
	check(is_instance_valid(owner.history_button)==has_history,"History visibility differs from native report vectors")
	await pointer(Vector2(920,68))
	if not await selection_ready(model):return
	check(ui.host.active==selection and not owner.panel.visible,"Creature-to-group return retained detail owner")
	await panel_capture("unit-group-return","workshop-selection-unit-group")
	key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and model.snapshot.is_empty() and not selection.tabs.visible,"Escape retained unit-group context")
	ui.open_tile_selection(point);actions.poll(0.01);ui.host.reset_local_views()
	await drain()
	check(ui.host.active==null and model.snapshot.is_empty(),"Late unit-group reply reopened reset scene")
	exercised=true
