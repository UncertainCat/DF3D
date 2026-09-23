extends "res://tests/mesh_batch_motion_live.gd"

func capture_roster(suffix: String):
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"-"+suffix+".png")

func run():
	root.size=Vector2i(1200,792)
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	var deadline=Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	assert(scene._loader.entered,"Fixture loaded")
	if not await set_paused(true): quit(1);return
	await go_level(128);await settle()
	var view=scene._ui.controller("readouts")
	await scene._ui.open_destination("Residents")
	deadline=Time.get_ticks_msec()+30000
	while (not view.complete or view.loading) and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	assert(view.complete and not view.people.is_empty(),"Resident publication complete")
	view.inspect_requested.emit(-1)
	assert(view.panel.visible and not scene._ui.controller("inspector").panel.visible,"Invalid resident does not steal ownership")
	view.read_resident_state()
	await capture_roster("1200")
	var evidence={"residents":view.people.size(),"epoch":view.epoch}
	evidence["residents_with_icon_recipes"]=view.people.filter(func(r):return int(r.get("sheet_icon_layers",0))>0).size()
	evidence["residents_with_work_details"]=view.people.filter(func(r):return not r.get("assigned_details",[]).is_empty()).size()
	evidence["social_activities"]=view.people.filter(func(r):return r.get("social_activity",false)).size()
	var row_evidence: Array=[]
	for background in view.rows.get_children().slice(0,3):
		var controls: Array=[]
		var name_label: Label=background.get_child(0).get_child(1)
		assert(not name_label.text.is_empty() and name_label.size.y>=12,"Resident name has a visible text area")
		for control in background.get_child(0).get_children():
			controls.append({"type":control.get_class(),"position":[control.position.x,control.position.y],"size":[control.size.x,control.size.y],"minimum":[control.get_combined_minimum_size().x,control.get_combined_minimum_size().y],"text":control.text if control is Label else "","lines":control.get_line_count() if control is Label else 0,"visible_lines":control.get_visible_line_count() if control is Label else 0})
		row_evidence.append(controls)
	evidence["rows"]=row_evidence
	for size in [Vector2i(1920,1080),Vector2i(960,640)]:
		root.size=size
		await capture_roster(str(size.x))
		assert(view.panel.get_global_rect().end.x<=size.x+1,"Panel inside viewport")
		assert(view.panel.size.x<=size.x/view.panel.get_parent().scale.x-256+1,"Roster respects reserved HUD width after resize")
	root.size=Vector2i(1200,792)
	view.search.text="Oddom";view.render_rows()
	await capture_roster("native-match")
	var native_icon: Texture2D=scene.world.resident_icon(1153)
	assert(native_icon!=null,"Reference miner has resident icon independent of camera")
	native_icon.get_image().save_png(output+"-reference-icon.png")
	var social_rows: Array=view.people.filter(func(r):return r.get("social_activity",false))
	if not social_rows.is_empty():
		view.search.text=str(social_rows[0].name);view.render_rows()
		await capture_roster("social")
	view.search.text="cerol"
	view.render_rows()
	await capture_roster("search")
	assert(view.rows.get_child_count()>0,"Search shows target")
	view.inspect_requested.emit(86)
	deadline=Time.get_ticks_msec()+30000
	while not scene.world.creature_info_state(86).get("complete",false) and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	assert(scene._ui.controller("inspector").panel.visible and not view.panel.visible,"Inspector takes ownership")
	assert(int(scene._ui.controller("inspector").selected.get("id",-1))==86,"Correct resident selected")
	assert(scene.world.creature_info_state(86).get("complete",false),"Creature detail loaded through resident service")
	await capture_roster("inspect")
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	Input.parse_input_event(escape)
	await process_frame
	assert(not scene._ui.controller("inspector").panel.visible,"Escape closes creature sheet")
	await scene._ui.open_destination("Residents")
	assert(view.complete and view.search.text=="cerol","Cached roster retains local search")
	view.search.clear();view.render_rows()
	var icon_a: Texture2D=scene.world.resident_icon(86)
	var icon_b: Texture2D=scene.world.resident_icon(1153)
	var publication: int=scene.world.resident_info_state().get("generation",0)
	scene.world.refresh_resident_info()
	deadline=Time.get_ticks_msec()+30000
	while int(scene.world.resident_info_state().get("generation",0))==publication and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	assert(int(scene.world.resident_info_state().get("generation",0))!=publication,"Resident refresh completed")
	assert(scene.world.resident_icon(86)==icon_a and scene.world.resident_icon(1153)==icon_b,"Unchanged recipes retain GPU textures across refresh")
	Input.parse_input_event(escape)
	await process_frame
	assert(not view.panel.visible,"Escape closes roster")
	assert(not scene._interaction.construction_active,"Roster releases input")
	var file=FileAccess.open(output+"-data.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	print("FLOOR_PROFILE_PASS");quit()
