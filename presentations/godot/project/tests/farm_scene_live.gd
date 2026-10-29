extends "res://tests/farm_controller_live.gd"
var scene
var owner
func run() -> void:
	directory=OS.get_environment("DF3D_AREAS_ACCEPTANCE")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	OS.set_environment("DF3D_DF_PATH",FileAccess.get_file_as_string(directory+"/df-path.txt"));OS.set_environment("DF3D_FIXTURE","")
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	root.size=Vector2i(1200,800)
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if check(scene._loader.entered,"main scene did not enter fortress"):
		actions=scene._ui.actions;actions.set_process(false)
		owner=scene._ui.controller("farm");farm=owner.state
		farm.applied.connect(func():applied_count+=1)
		await exercise_scene()
	var status:="failed" if failed else "incomplete" if not reasons.is_empty() else "passed"
	write_json("result.json",{"status":status,"reasons":reasons,"native_checks":handshake,"surface":"staged farm owner in actual main scene; viewport keyboard and mouse input"})
	scene.queue_free();await process_frame;print("FARM_SCENE ",status);quit(1 if failed else 77 if status=="incomplete" else 0)
func pointer(point: Vector2,button:=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func key(code: int,unicode:=0) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=pressed;root.push_input(event,true)
func capture(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/farm_scene_"+label+".png")==OK,"capture failed")
func rename_click() -> void:
	await process_frame
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(384,30))
	check(owner.panel.name_entry.editing and farm.name_session!=null,"rename click did not begin owned typing")
func exercise_scene() -> void:
	await contents_scene()
	if stopped:return
	var id:=int(fixture.id);var seasons: Array=[]
	for crop in fixture.seasons:seasons.append(int(crop))
	owner.open_target(id,1)
	if not await settled(Farm.Phase.Ready):return
	for probe in [["rename",Vector2(384,30)],["remove",Vector2(416,30)],["",Vector2(184,30)],["",Vector2(64,72)]]:
		step="farm header hover "+probe[0]
		var motion:=InputEventMouseMotion.new();motion.position=owner.panel.get_global_transform_with_canvas()*probe[1];root.push_input(motion,true)
		await create_timer(0.6).timeout
		var expected: String="building_"+probe[0] if probe[0]!="" else ""
		if not check(scene._fortress_hud.native_help.displayed==expected,"farm header help differs"):return
		if probe[0]!="":await capture("hover_"+probe[0])
	owner.close_panel();await process_frame
	if not check(not scene._fortress_hud.native_help.visible,"closed farm retained help"):return
	for ending in ["enter","escape","right","tab","reset"]:
		step="main farm typing "+ending
		owner.open_target(id,1)
		if not await settled(Farm.Phase.Ready):return
		await rename_click()
		if stopped:return
		for byte in "typed farm".to_utf8_buffer():
			key(0,byte)
			if byte==116:actions.poll()
		if not check(owner.panel.name_entry.value=="typed farm","viewport keys did not reach farm draft"):return
		scene._fortress_hud.toggle_game_menu();await process_frame
		key(0,122)
		if not check(owner.panel.name_entry.value=="typed farm","overlay allowed typing through"):return
		scene._fortress_hud.close_menus();await process_frame
		await capture(ending+"_typing")
		if ending=="enter":key(KEY_ENTER)
		elif ending=="escape":key(KEY_ESCAPE)
		elif ending=="reset":key(KEY_F10)
		elif ending=="right":await pointer(Vector2(400,400),MOUSE_BUTTON_RIGHT)
		else:await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(2).get_center())
		if ending in ["escape","right","reset"]:
			if not check(not owner.panel.visible and scene._ui.host.active==null,"closing did not retire farm owner"):return
			owner.open_target(id,1)
		if not await settled(Farm.Phase.Ready):return
		if not check(farm.snapshot.custom_name=="typed farm" and not owner.panel.name_entry.editing,"final draft lost or editing revived"):return
		await native("verify",{"seasons":seasons,"name":"typed farm"})
		if stopped:return
		await capture(ending+"_confirmed")
		await rename_click()
		for index in 30:key(KEY_BACKSPACE)
		key(KEY_ENTER)
		if not await settled(Farm.Phase.Ready):return
		await native("verify",{"seasons":seasons,"name":""})
		if stopped:return
		owner.close_panel()
	step="main farm remove and cancel"
	owner.open_target(id,1)
	if not await settled(Farm.Phase.Ready):return
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(416,30))
	if not await settled(Farm.Phase.Ready):return
	if not check(farm.snapshot.removing and not owner.panel.body.visible,"remove icon did not show removal state"):return
	await native("verify",{"seasons":seasons,"removing":true})
	await capture("removing")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await settled(Farm.Phase.Ready):return
	if not check(not farm.snapshot.removing and owner.panel.body.visible,"cancel control did not restore farm body"):return
	await native("verify",{"seasons":seasons,"removing":false})
	await capture("cancelled")
	await disconnect_cases(id,seasons)
	if stopped:return
	await replacement_case(id,seasons)

func lifecycle_open(id: int) -> void:
	var deadline:=Time.get_ticks_msec()+120000
	while (not scene._loader.entered or not owner.play_enabled) and Time.get_ticks_msec()<deadline:
		actions.poll(0.02);await create_timer(0.02).timeout
	if not check(scene._loader.entered and owner.play_enabled,"replacement scene did not finish loading"):return
	owner.open_target(id,1)

func lifecycle_intent(operation: String) -> void:
	if not check(owner.panel.visible and scene._ui.host.active==owner,"lifecycle farm owner not active"):return
	if operation=="remove":await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(416,30))
	else:
		await rename_click()
		if stopped:return
		key(0,65);key(0,66)
		if not check(owner.panel.name_entry.value=="AB","lifecycle viewport typing differs"):return
	await capture("lifecycle_"+operation+"_pending")

func lifecycle_retired(label: String) -> void:
	await process_frame
	if not check(not owner.panel.visible and not owner.panel.name_entry.editing and scene._ui.host.active==null,"retired farm retained visible panel, draft or input ownership"):return
	var next_ticket: int=actions._next_ticket
	key(0,90);key(KEY_ENTER)
	await process_frame
	if not check(no_farm_requests_since(next_ticket) and farm.name_session==null and farm.snapshot.is_empty() and owner.contents.snapshot.is_empty() and owner.panel.contents.rows.is_empty() and not owner.panel.contents.scrollbar.dragging,"retired farm retained input or contents authority"):return
	await capture(label+"_retired")

func contents_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if owner.contents.phase==owner.contents.Phase.Ready and farm.phase==Farm.Phase.Ready:return true
		if owner.contents.phase in [owner.contents.Phase.Rejected,owner.contents.Phase.Stale,owner.contents.Phase.Unknown]:
			return check(false,"rendered contents lost authority: "+str(owner.contents.phase))
		await create_timer(0.01).timeout
	incomplete("rendered contents did not settle",true);return false

func contents_scene() -> void:
	step="main farm contents"
	owner.open_target(int(fixture.contents.building_id),1)
	if not await contents_ready():return
	var initial: Dictionary=owner.contents.snapshot.duplicate(true)
	var view=owner.panel.contents
	if not check(view.visible and view.rows.size()==40 and view.page==6,"contents not connected to staged sheet"):return
	await capture("contents_baseline")
	for probe in [[0,"permanent"],[1,"view"],[2,"forbid"],[3,"dump"],[4,""],[5,"visibility"]]:
		var motion:=InputEventMouseMotion.new()
		motion.position=view.get_global_transform_with_canvas()*view.control_rect(0,probe[0]).get_center();root.push_input(motion,true)
		await create_timer(0.6).timeout
		var expected: String="contents_"+probe[1] if probe[1]!="" else ""
		if not check(scene._fortress_hud.native_help.displayed==expected,"contents hover differs: "+probe[1]):return
		if probe[1]!="":await capture("contents_hover_"+probe[1])

	for control in [2,3,5]:
		for toggle in 2:
			# The second row forces receipt-offset recovery to the same viewport.
			await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,control).get_center())
			if not await contents_ready():return
			if not check(owner.contents.snapshot.cursor==0,"contents edit moved viewport"):return
			await native("contents-verify",{"rows":owner.contents.rows()})
			if stopped:return
			await capture("contents_"+str(control)+"_"+str(toggle))
	if not check(owner.contents.snapshot==initial,"rendered item controls did not restore contents"):return
	await pointer(view.get_global_transform_with_canvas()*Vector2(464,210))
	if not await contents_ready():return
	if not check(owner.contents.snapshot.cursor==1 and view.rows[0].id==initial.rows[1].id,"contents down arrow did not page native order"):return
	await capture("contents_scrolled")
	await pointer(view.get_global_transform_with_canvas()*Vector2(464,6))
	if not await contents_ready():return
	if not check(owner.contents.snapshot==initial,"contents up arrow did not restore viewport"):return
	owner.close_panel();await process_frame
	if not check(owner.contents.snapshot.is_empty() and view.rows.is_empty() and not view.scrollbar.dragging,"closed farm retained contents"):return
	if not check(not scene._fortress_hud.native_help.visible,"closed contents retained hover"):return
