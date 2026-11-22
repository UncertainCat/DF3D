extends "res://tests/workshop_order_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	Engine.max_fps=30;OS.set_environment("DF3D_FIXTURE","")
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	root.size=Vector2i(1200,800)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+60000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if not check(scene._loader.entered,"Residents main scene did not enter fortress"):quit(1);return
	var service=scene._ui.actions;service.set_process(false)
	var owner=scene._ui.controller("residents");var host=scene._ui.host
	click(scene._fortress_hud.launcher_rect("Citizens").get_center())
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Residents HUD did not load"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-list-reference.json"))
	check(owner.state.ids==PackedInt32Array(expected.snapshots[0].ids),"Public resident order differs from native")
	check(host.active==owner and owner.panel.visible,"Residents lost input owner")
	for frame in 3:await process_frame
	click(owner.panel.position+Vector2(64,owner.panel.list_top()-18))
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Resident name sort failed"):quit(1);return
	check(owner.state.ids==PackedInt32Array(expected.snapshots[1].ids),"Name sort differs from native")
	var original: PackedInt32Array=owner.state.ids.duplicate()
	click(owner.panel.position+owner.panel.search.position+Vector2(24,18))
	for character in "ABAN":number_key(KEY_A,character.unicode_at(0))
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Resident search failed"):quit(1);return
	check(owner.state.query.get_string_from_utf8()=="ABAN" and not owner.state.ids.is_empty() and owner.state.ids.size()<original.size(),"Search did not filter residents")
	for index in 4:number_key(KEY_BACKSPACE)
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Resident search clear failed"):quit(1);return
	check(owner.state.ids==original,"Clearing search did not restore roster")
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
	wheel.position=owner.panel.position+Vector2(400,owner.panel.list_top()+18);root.push_input(wheel,true)
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Resident scroll failed"):quit(1);return
	check(owner.state.first==1,"Wheel did not scroll residents")
	wheel.button_index=MOUSE_BUTTON_WHEEL_UP;root.push_input(wheel,true)
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Resident scroll return failed"):quit(1);return
	check(owner.state.first==0,"Wheel did not restore first row")
	var activity_row:=-1
	for index in owner.state.capacity:
		if owner.state.row_at(index).has("activity_target"):activity_row=index;break
	check(activity_row>=0,"Activity fixture absent")
	if activity_row>=0:
		click(owner.panel.position+Vector2(636,owner.panel.list_top()+activity_row*36+18))
		if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.ActivityReady),"Activity description failed"):quit(1);return
		check(not owner.state.activity_page.get("words",[]).is_empty(),"Activity description empty")
		click(owner.panel.position+owner.panel.activity_close_rect().get_center())
		check(owner.state.phase==owner.state.Phase.Ready and not owner.state.activity_open(),"Activity Close did not restore residents")
	for dimensions in [Vector2i(1600,900),Vector2i(912,552),Vector2i(1200,800)]:
		root.size=dimensions
		for frame in 3:await process_frame
		if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Resident resize failed"):quit(1);return
		check(host.active==owner and owner.state.ids==original,"Resize changed roster or ownership")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/residents-public.png")
	var target: Dictionary=owner.state.row_at(owner.state.first)
	check(not target.is_empty(),"Resident navigation needs a row")
	click(owner.panel.position+Vector2(348,owner.panel.list_top()+18))
	var inspector=scene._ui.controller("inspector")
	if not check(await settle(service,func():return host.active==inspector),"Resident creature sheet handoff failed"):quit(1);return
	check(inspector.selected.get("id",-1)==int(target.id),"Creature sheet opened wrong resident")
	host.close_active();await process_frame
	click(scene._fortress_hud.launcher_rect("Citizens").get_center())
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Residents HUD reopen failed"):quit(1);return
	number_key(KEY_ESCAPE);await process_frame
	check(host.active==null and not owner.panel.visible,"Residents Escape retained input")
	var file:=FileAccess.open(directory+"/residents-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed}));file.close()
	scene.queue_free();await process_frame
	quit(1 if failed else 0)

