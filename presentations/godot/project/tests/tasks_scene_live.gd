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
	owner=scene._ui.controller("tasks");await pointer(scene._fortress_hud.launcher_rect("Tasks").get_center())
	if not await ready_tasks():return
	check(owner.state.rows.size()==expected.rows.size(),"Main Tasks list differs")
	if OS.get_environment("DF3D_TASKS_LAYOUT")=="1":
		for sample in [["minimum",Vector2i(912,552)],["small",Vector2i(960,600)],["wide",Vector2i(1600,900)],["default",Vector2i(1200,800)]]:
			root.size=sample[1];await process_frame;await process_frame
			owner.state.seek(0,owner.panel.capacity());await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/tasks-main-layout-"+sample[0]+".png")
			if sample[0]=="minimum":
				var camera: Vector3=scene.camera_rig.position;var z: int=world.get_top_z()
				for x in [708,732]:
					await pointer(Vector2(x,142));await drain()
					check(owner.state.phase==owner.state.Phase.Ready and scene._ui.host.active==owner and owner.panel.visible,"Overflow worker control changed Tasks owner")
					check(scene.camera_rig.position==camera and world.get_top_z()==z,"Overflow worker control moved camera")
			for page in 5:
				var wheel:=InputEventMouseButton.new();wheel.position=Vector2(500,200);wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.shift_pressed=true;wheel.pressed=true
				root.push_input(wheel,true);wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true);await process_frame
			check(owner.state.first==maxi(0,owner.state.rows.size()-owner.panel.capacity()),"Tasks resize wheel did not reach last page")
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/tasks-main-layout-"+sample[0]+"-last.png")
		owner.state.seek(0,owner.panel.capacity());await process_frame
	var scrollbar=owner.panel.scrollbar
	await pointer(scrollbar.get_global_transform_with_canvas()*Vector2(8,scrollbar.size.y-6))
	var expected_first: int=mini(1,maxi(0,expected.rows.size()-17))
	check(owner.state.first==expected_first,"Tasks scrollbar down did not advance one row")
	for sample in [[Vector2(468,248),MOUSE_BUTTON_WHEEL_DOWN,false,1],[Vector2(468,248),MOUSE_BUTTON_WHEEL_UP,false,-1],[Vector2(920,248),MOUSE_BUTTON_WHEEL_DOWN,true,17],[Vector2(920,248),MOUSE_BUTTON_WHEEL_UP,true,-17],[Vector2(468,38),MOUSE_BUTTON_WHEEL_DOWN,false,0],[Vector2(-12,-32),MOUSE_BUTTON_WHEEL_DOWN,false,0]]:
		var wheel:=InputEventMouseButton.new();wheel.position=owner.panel.get_global_transform_with_canvas()*sample[0];wheel.button_index=sample[1];wheel.shift_pressed=sample[2];wheel.pressed=true
		root.push_input(wheel,true);wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true);await process_frame
		expected_first=clampi(expected_first+int(sample[3]),0,maxi(0,expected.rows.size()-17))
		check(owner.state.first==expected_first,"Tasks contextual scrolling differs")
	key(KEY_DOWN);key(KEY_PAGEDOWN);await process_frame
	check(owner.state.first==expected_first,"Tasks accepted inactive standard scrolling keys")
	owner.state.seek(1048576,owner.panel.capacity());await process_frame
	var hover_index: int=-1
	for i in owner.state.rows.size():
		if owner.state.rows[i].job_id==68196:hover_index=i-owner.panel.visible_first()
	var motion:=InputEventMouseMotion.new();motion.position=owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(hover_index,3).get_center();root.push_input(motion,true)
	var hover_deadline:=Time.get_ticks_msec()+700
	while Time.get_ticks_msec()<hover_deadline:
		root.push_input(motion.duplicate(),true);await process_frame
	check(scene._fortress_hud.native_help.displayed=="tasks_suspend","Main Tasks hover differs: "+scene._fortress_hud.native_help.displayed+" target="+owner.panel.hover_target(owner.panel.pointer_position)+" known="+str(owner.panel.pointer_known)+" allowed="+str(owner.panel.allowed())+" help="+str(is_instance_valid(owner.panel.hover_help))+" key="+scene._fortress_hud.native_help.state.key)
	scene._fortress_hud.toggle_game_menu();await process_frame
	check(scene._ui.host.overlay_blocked,"Tasks overlay did not block input")
	await pointer(motion.position);await drain()
	check(owner.state.phase==owner.state.Phase.Ready and owner.state.rows.any(func(row):return row.job_id==68196 and row.suspended),"Overlay allowed Tasks mutation")
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
	if OS.get_environment("DF3D_TASKS_CREATE")=="1":
		var target: int=-1
		for i in owner.state.rows.size():
			if owner.state.rows[i].can_view_job and owner.state.rows[i].job_id==int(expected.details_job):target=i;break
		if not check(target>=0,"Created Tasks Details target missing"):return
		var job: int=owner.state.rows[target].job_id
		owner.state.seek(target,owner.panel.capacity());await process_frame
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(target-owner.panel.visible_first(),0).get_center())
		if not await settle(owner.job_state):return
		check(owner.job_state.job_id==job and owner.job_panel.visible and not owner.panel.visible and scene._ui.host.active==owner,"View task did not open owned Details")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/tasks-main-details.png")
		key(KEY_ESCAPE);await process_frame
		check(not owner.job_open() and owner.panel.visible and scene._ui.host.active==owner,"Details Back did not return to Tasks")
		for step in [1,2]:
			var index: int=-1
			for i in owner.state.rows.size():
				if owner.state.rows[i].job_id==job:index=i-owner.panel.visible_first()
			if not check(index>=0 and index<owner.panel.capacity(),"Repeat target not visible"):return
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(index,1).get_center())
			if not await ready_tasks():return
			var file=FileAccess.open(directory+"/tasks-repeat-step",FileAccess.WRITE);file.store_string(str(step));file.close()
			var deadline:=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-repeat-ack")!=str(step):await create_timer(0.01).timeout
			if not check(FileAccess.get_file_as_string(directory+"/tasks-repeat-ack")==str(step),"Native Repeat effect unconfirmed"):return
		if OS.get_environment("DF3D_TASKS_MATERIAL")=="1":
			var index: int=-1
			for i in owner.state.rows.size():
				if owner.state.rows[i].job_id==job:index=i
			owner.state.seek(index,owner.panel.capacity());await process_frame
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(index-owner.panel.visible_first(),0).get_center())
			if not await settle(owner.job_state):return
			await pointer(owner.job_panel.get_global_transform_with_canvas()*Vector2(120,66))
			if not await settle(owner.job_state):return
			var choice: int=-1
			for i in owner.job_state.rows.size():
				if owner.job_state.rows[i].caption==expected.get("execution_material",{}).get("caption","Dolomite"):choice=i;break
			if not check(choice>=0,"Native Dolomite material choice missing"):return
			owner.job_state.seek(choice);await process_frame
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/tasks-main-materials.png")
			await pointer(owner.job_panel.get_global_transform_with_canvas()*Vector2(120,owner.job_panel.list_top()+18));await drain()
			if not await ready_tasks():return
			check(not owner.job_open() and owner.panel.visible,"Material edit did not return to Tasks")
			var file=FileAccess.open(directory+"/tasks-material-step",FileAccess.WRITE);file.store_string("1");file.close()
			var deadline:=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-material-ack")!="1":await create_timer(0.01).timeout
			if not check(FileAccess.get_file_as_string(directory+"/tasks-material-ack")=="1","Native Tasks material effect unconfirmed"):return
			for i in owner.state.rows.size():
				if owner.state.rows[i].job_id==job:index=i
			owner.state.seek(index,owner.panel.capacity());await process_frame
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(index-owner.panel.visible_first(),0).get_center())
			if not await settle(owner.job_state):return
			await pointer(owner.job_panel.get_global_transform_with_canvas()*Vector2(120,102))
			if not await settle(owner.job_state):return
			await pointer(owner.job_panel.get_global_transform_with_canvas()*Vector2(120,114))
			if not await settle(owner.job_state):return
			if not check(owner.job_state.art_page()==1 and not owner.job_state.rows.is_empty(),"Tasks figure choices missing"):return
			var figure: int=owner.job_state.rows[0].id
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/tasks-main-figures.png")
			await pointer(owner.job_panel.get_global_transform_with_canvas()*Vector2(120,owner.job_panel.list_top()+18));await drain()
			if not await ready_tasks():return
			check(not owner.job_open(),"Artwork edit did not close Tasks Details")
			file=FileAccess.open(directory+"/tasks-art-step",FileAccess.WRITE);file.store_string(str(figure));file.close()
			deadline=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-art-ack")!="1":await create_timer(0.01).timeout
			if not check(FileAccess.get_file_as_string(directory+"/tasks-art-ack")=="1","Native Tasks artwork effect unconfirmed"):return
		owner.state.seek(1048576,owner.panel.capacity());await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/tasks-main-scene.png")
	# Building Recenter leaves Tasks and focuses its current native work location.
	var row: Dictionary=owner.state.rows.back();var tile: Vector3i=row.building_position
	var index: int=owner.state.rows.size()-1-owner.panel.visible_first()
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(220,owner.panel.list_top()+index*36+18));await drain();await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible and scene._ui.host.active==null,"Tasks Recenter retained panel ownership")
	check(world.get_top_z()==tile.z and is_equal_approx(scene.camera_rig.position.x,tile.x+0.5) and is_equal_approx(scene.camera_rig.position.z,tile.y+0.5),"Tasks Recenter focused wrong destination")
	await pointer(scene._fortress_hud.launcher_rect("Tasks").get_center());if not await ready_tasks():return
	var worker: int=owner.state.rows[0].worker_id
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(700,owner.panel.list_top()+18));await drain();await process_frame
	check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible,"Worker View did not close Tasks")
	var inspector=scene._ui.controller("inspector")
	check(scene._ui.host.active==inspector and inspector.selected.get("kind")==1 and inspector.selected.get("id")==worker,"Worker View failed to activate exact creature")
	check(worker>=0,"Worker View fixture missing")
	scene._ui.host.close_active();await process_frame
	await pointer(scene._fortress_hud.launcher_rect("Tasks").get_center());if not await ready_tasks():return
	if OS.get_environment("DF3D_TASKS_DESTRUCTIVE")=="1":
		for step in [1,2]:
			var target_id: int=382763 if step==1 else 372039
			var target: int=-1
			for i in owner.state.rows.size():
				if owner.state.rows[i].job_id==target_id:target=i;break
			if not check(target>=0,"Tasks action target missing"):return
			owner.state.seek(target,owner.panel.capacity());await process_frame
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(target-owner.panel.visible_first(),2 if step==1 else 4).get_center())
			if not await ready_tasks():return
			if step==1:
				check(owner.state.rows.any(func(entry):return entry.job_id==target_id and entry.worker_id==-1 and not entry.can_remove_worker),"Remove worker did not refresh assignment")
			else:
				check(not owner.state.rows.any(func(entry):return entry.job_id==target_id),"Cancelled task remains visible")
			var file=FileAccess.open(directory+"/tasks-destructive-step",FileAccess.WRITE);file.store_string(str(step));file.close()
			var deadline:=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-destructive-ack")!=str(step):await create_timer(0.01).timeout
			if not check(FileAccess.get_file_as_string(directory+"/tasks-destructive-ack")==str(step),"Native Tasks action effect unconfirmed"):return
	if OS.get_environment("DF3D_TASKS_CANCEL_WORKSHOP")=="1" or OS.get_environment("DF3D_TASKS_CANCEL_DEMOLITION")=="1" or OS.get_environment("DF3D_TASKS_CANCEL_ASSIGNED")=="1" or OS.get_environment("DF3D_TASKS_CANCEL_STARTED")=="1":
		var target: int=-1
		for i in owner.state.rows.size():
			if owner.state.rows[i].job_id==int(expected.cancel_job):target=i;break
		if not check(target>=0 and owner.state.rows[target].can_cancel,"Workshop cancel target missing"):return
		owner.state.seek(target,owner.panel.capacity());await process_frame
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.button_rect(target-owner.panel.visible_first(),4).get_center())
		if not await ready_tasks():return
		check(not owner.state.rows.any(func(row):return row.job_id==int(expected.cancel_job)),"Cancelled workshop job retained in Tasks")
		var file=FileAccess.open(directory+"/tasks-workshop-cancel-step",FileAccess.WRITE);file.store_string("1");file.close()
		var deadline:=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-workshop-cancel-ack")!="1":await create_timer(0.01).timeout
		if not check(FileAccess.get_file_as_string(directory+"/tasks-workshop-cancel-ack")=="1","Native workshop cancellation effect unconfirmed"):return
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,100),MOUSE_BUTTON_RIGHT)
	check(not owner.panel.visible and scene._ui.host.active==null,"Tasks back did not release owner")
	if OS.get_environment("DF3D_TASKS_LIFECYCLE")=="1":
		# Queued requests must be cancelled; sent requests must drain without
		# giving their retired panel a new receipt or reopening its child view.
		owner.open_panel();var queued: int=owner.state.ticket
		owner.close_panel();await drain()
		check(actions.result(queued).get("outcome")=="not_sent" and owner.state.rows.is_empty() and not owner.panel.visible,"Closed queued Tasks request retained authority")
		owner.open_panel();actions.poll(0.0);var sent: int=owner.state.ticket
		if not check(actions._requests.has(sent) and actions._requests[sent].sequence>0,"Tasks lifecycle read was not sent"):return
		owner.close_panel();owner.open_panel();var replacement: int=owner.state.ticket
		if not await ready_tasks():return
		check(replacement!=sent and owner.state.ticket==0 and actions.result(sent).get("status")==C.ManagementStatus.Ok,"Late Tasks read was not drained independently")
		if OS.get_environment("DF3D_TASKS_CREATE")=="1":
			var detail_row: Dictionary={}
			for entry in owner.state.rows:
				if entry.can_view_job:detail_row=entry;break
			if not check(not detail_row.is_empty(),"Tasks lifecycle Details fixture missing"):return
			owner._navigate(detail_row,false,true);actions.poll(0.0)
			owner.close_panel();await drain()
			check(not owner.job_open() and not owner.job_panel.visible and scene._ui.host.active==null,"Late Details reply reopened retired Tasks")
			owner.open_panel();if not await ready_tasks():return
			for step in [1,2]:
				owner.state.apply(detail_row.job_id,C.TasksOperation.Repeat);actions.poll(0.0)
				var mutation: int=owner.state.ticket
				if not check(actions._requests.has(mutation) and actions._requests[mutation].sequence>0,"Tasks lifecycle mutation was not sent"):return
				owner.close_panel();owner.open_panel()
				if not await ready_tasks():return
				check(actions.result(mutation).get("tasks",{}).get("outcome")==C.TasksOutcome.Applied,"Detached Tasks mutation receipt missing")
				var file=FileAccess.open(directory+"/tasks-lifecycle-step",FileAccess.WRITE);file.store_string(str(step));file.close()
				var deadline:=Time.get_ticks_msec()+5000
				while Time.get_ticks_msec()<deadline and FileAccess.get_file_as_string(directory+"/tasks-lifecycle-ack")!=str(step):await create_timer(0.01).timeout
				if not check(FileAccess.get_file_as_string(directory+"/tasks-lifecycle-ack")==str(step),"Detached Tasks mutation effect unconfirmed"):return
		owner.open_panel();if not await ready_tasks():return
		owner.state.refresh();actions.poll(0.0);var detached: int=owner.state.ticket
		if not check(actions._requests.has(detached) and actions._requests[detached].sequence>0,"Tasks disconnect read was not sent"):return
		world.detach_live();actions.poll(0.0);await process_frame
		check(owner.state.rows.is_empty() and not owner.panel.visible and not owner.job_panel.visible and scene._ui.host.active==null,"Detached world retained Tasks authority")
		check(actions.result(detached).get("outcome")=="unknown","Sent Tasks read did not retire on detach")
	exercised=true
