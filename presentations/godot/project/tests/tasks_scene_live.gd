extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "tasks-scene-reference.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func ready_tasks() -> bool:
	if not await settle(owner.state):return false
	await process_frame
	return check(scene._ui.host.active==owner and owner.panel.visible,"Tasks lost modal ownership")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("tasks");owner.open_panel()
	if not await ready_tasks():return
	check(owner.state.rows.size()==expected.rows.size(),"Main Tasks list differs")
	var scrollbar=owner.panel.scrollbar
	await pointer(scrollbar.get_global_transform_with_canvas()*Vector2(8,scrollbar.size.y-6))
	check(owner.state.first==1,"Tasks scrollbar down did not advance one row")
	owner.state.seek(24,owner.panel.capacity());await process_frame
	var motion:=InputEventMouseMotion.new();motion.position=owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(15,3).get_center();root.push_input(motion,true)
	await create_timer(0.65).timeout
	check(scene._fortress_hud.native_help.displayed=="tasks_suspend","Main Tasks hover service did not show native instruction")
	scene._fortress_hud.toggle_game_menu();await process_frame
	check(scene._ui.host.overlay_blocked,"Tasks overlay did not block input")
	await pointer(motion.position);await drain()
	check(owner.state.phase==owner.state.Phase.Ready and owner.state.rows[39].suspended,"Overlay allowed Tasks mutation")
	scene._fortress_hud.close_menus();await process_frame
	for step in [1,2]:
		var index: int=-1
		for i in owner.state.rows.size():
			if owner.state.rows[i].job_id==68196:index=i-owner.panel.visible_first()
		if not check(index>=0 and index<owner.panel.capacity(),"Suspension target not visible"):return
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(index,3).get_center())
		if not await ready_tasks():return
		var file=FileAccess.open(directory+"/tasks-wire-step",FileAccess.WRITE);file.store_string(str(step));file.close()
		var deadline:=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-wire-ack")!=str(step):await create_timer(0.01).timeout
		if not check(FileAccess.get_file_as_string(directory+"/tasks-wire-ack")==str(step),"Native suspension effect unconfirmed"):return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/tasks-main-scene.png")
	# Building Recenter leaves Tasks and focuses its current native work location.
	var row: Dictionary=owner.state.rows.back();var tile: Vector3i=row.building_position
	var index: int=owner.state.rows.size()-1-owner.panel.visible_first()
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(220,owner.panel.list_top()+index*36+18));await drain();await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible and scene._ui.host.active==null,"Tasks Recenter retained panel ownership")
	check(world.get_top_z()==tile.z and is_equal_approx(scene.camera_rig.position.x,tile.x+0.5) and is_equal_approx(scene.camera_rig.position.z,tile.y+0.5),"Tasks Recenter focused wrong destination")
	owner.open_panel();if not await ready_tasks():return
	var worker: int=owner.state.rows[0].worker_id
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(700,owner.panel.list_top()+18));await drain();await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible,"Worker View did not close Tasks")
	var inspector=scene._ui.controller("inspector")
	check(scene._ui.host.active==inspector and inspector.selected.get("kind")==1 and inspector.selected.get("id")==worker,"Worker View failed to activate exact creature")
	check(worker>=0,"Worker View fixture missing")
	scene._ui.host.close_active();await process_frame
	owner.open_panel();if not await ready_tasks():return
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,100),MOUSE_BUTTON_RIGHT)
	check(not owner.panel.visible and scene._ui.host.active==null,"Tasks back did not release owner")
	exercised=true
