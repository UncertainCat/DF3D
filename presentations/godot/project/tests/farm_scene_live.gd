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
	await contents_disconnect_cases()
	if stopped:return
	await disconnect_cases(id,seasons)
	if stopped:return
	await replacement_case(id,seasons)
	if stopped:return
	await contents_replacement_case()
	if stopped:return
	await item_lifecycle_cases()
	if stopped:return
	await follow_lifecycle_cases()

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
		var expected: String="contents_"+probe[1] if probe[1]!="" else ""
		var help_deadline:=Time.get_ticks_msec()+2000
		await process_frame
		while scene._fortress_hud.native_help.displayed!=expected and Time.get_ticks_msec()<help_deadline:await process_frame
		if not check(scene._fortress_hud.native_help.displayed==expected,"contents hover differs: "+probe[1]):return
		if probe[1]!="":await capture("contents_hover_"+probe[1])

	for control in [2,3,5]:
		for toggle in 2:
			# The second row forces receipt-offset recovery to the same viewport.
			await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,control).get_center())
			if not await contents_ready():return
			if not check(owner.contents.snapshot.cursor==0,"contents edit moved viewport"):return
			await native("contents-verify",{"rows":owner.contents.rows(),"cursor":owner.contents.snapshot.cursor})
			if stopped:return
			await capture("contents_"+str(control)+"_"+str(toggle))
	if not check(owner.contents.snapshot==initial,"rendered item controls did not restore contents"):return
	await pointer(view.get_global_transform_with_canvas()*Vector2(464,210))
	if not await contents_ready():return
	if not check(owner.contents.snapshot.cursor==0 and view.cell_first==1 and view.rows[0].id==initial.rows[0].id,"contents down arrow did not move one cell"):return
	await capture("contents_scrolled")
	await pointer(view.get_global_transform_with_canvas()*Vector2(464,6))
	if not await contents_ready():return
	if not check(owner.contents.snapshot==initial,"contents up arrow did not restore viewport"):return
	for x in [150,464]:
		for cell in [1,2,3,2,1,0]:
			var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN if cell>view.cell_first else MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
			wheel.position=view.get_global_transform_with_canvas()*Vector2(x,54);root.push_input(wheel,true)
			var wheel_release=wheel.duplicate();wheel_release.pressed=false;root.push_input(wheel_release,true)
			if not await contents_ready():return
			var cursor:=floori(cell/3.0)
			if not check(view.cell_first==cell and owner.contents.snapshot.cursor==cursor and view.rows[0].id==initial.rows[cursor].id,"contents cell wheel order differs"):return
			await native("contents-verify",{"rows":owner.contents.rows(),"cursor":cursor})
			if stopped:return
			await capture("contents_cell_"+str(x)+"_"+str(cell))
	if not check(owner.contents.snapshot==initial and view.cell_first==0,"contents wheel did not restore viewport"):return
	for probe in [[-8,0],[12,0],[42,12],[92,38],[192,102],[232,102]]:
		var grip: Vector2i=view.scrollbar.thumb()
		var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.button_mask=MOUSE_BUTTON_MASK_LEFT
		press.position=view.get_global_transform_with_canvas()*Vector2(464,(grip.x+0.5)*12);press.global_position=press.position;root.push_input(press,true)
		var motion:=InputEventMouseMotion.new();motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		motion.position=view.get_global_transform_with_canvas()*Vector2(464,probe[0]);root.push_input(motion,true)
		var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=motion.position;release.global_position=release.position;root.push_input(release,true)
		if not await contents_ready():return
		var cursor:=floori(float(probe[1])/3)
		if not check(view.cell_first==probe[1] and not view.scrollbar.dragging and owner.contents.snapshot.cursor==cursor and view.rows[0].id==initial.rows[cursor].id,"contents live drag mapping differs"):return
		await native("contents-verify",{"rows":owner.contents.rows(),"cursor":cursor})
		if stopped:return
		await capture("contents_drag_"+str(probe[0]))
	for size_case in [[1600,900,9],[960,600,0],[1200,800,6]]:
		root.size=Vector2i(size_case[0],size_case[1])
		for frame in 5:await process_frame
		if not await contents_ready():return
		if not check(view.cell_first==102 and owner.contents.snapshot.cursor==34 and view.page==size_case[2] and view.visible==(size_case[2]>0),"resizing contents changed retained endpoint"):return
		await capture("contents_endpoint_resize_"+str(size_case[0]))
	await item_sheet_scene(initial)
	if stopped:return
	owner.close_panel();await process_frame
	if not check(owner.contents.snapshot.is_empty() and view.rows.is_empty() and not view.scrollbar.dragging,"closed farm retained contents"):return
	if not check(not scene._fortress_hud.native_help.visible,"closed contents retained hover"):return

func item_ready() -> bool:
	var model=owner.item_owner.state
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if model.phase==model.Phase.Ready:return true
		if model.phase not in [model.Phase.Reading,model.Phase.Applying]:return check(false,"item sheet failed: "+str(model.phase))
		await create_timer(0.01).timeout
	incomplete("item sheet did not settle",true);return false

func item_lifecycle_cases() -> void:
	var evidence: Array=[]
	var item_owner=owner.item_owner;var model=item_owner.state;var sheet=item_owner.panel
	var observed: Array=[];model.applied.connect(func():observed.append(true))
	for mode in ["queued","sent","restart"]:
		step="item sheet lifecycle "+mode
		await lifecycle_open(int(fixture.contents.building_id))
		if not await contents_ready():return
		var view=owner.panel.contents
		await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,1).get_center())
		if not await item_ready():return
		var baseline: Dictionary=model.view_snapshot()
		var original_epoch: int=actions._epoch
		var generation: int=model.generation
		var observations:=observed.size()
		await pointer(sheet.get_global_transform_with_canvas()*sheet.flag_rect(3).get_center())
		var pending: int=model.ticket
		if not check(model.phase==model.Phase.Applying and pending>0 and actions._requests[pending].sequence==0,"item lifecycle edit not queued by viewport"):return
		if mode!="queued":
			actions.poll()
			if not check(actions._requests.has(pending) and actions._requests[pending].sequence>0,"item lifecycle edit not sent"):return
			var sequence: int=actions._requests[pending].sequence
			var deadline:=Time.get_ticks_msec()+30000
			var receipt: Dictionary={}
			while Time.get_ticks_msec()<deadline:
				world.poll();var candidate: Dictionary=world.poll_management()
				if candidate.get("request_seq")==sequence and candidate.get("status")==S.Ok:receipt=candidate;break
				await create_timer(0.01).timeout
			if not check(not receipt.is_empty() and actions.result(pending).is_empty() and observed.size()==observations,"item lifecycle receipt missing or delivered early"):return
			if not check(receipt.production.contents_edit.item_id==baseline.id and receipt.production.contents.rows[0].hidden!=baseline.hidden,"item lifecycle effect target differs"):return
			await native("contents-verify",{"rows":receipt.production.contents.rows,"cursor":receipt.production.contents.cursor})
			if stopped:return
			write_json("item-"+mode+"-unobserved.json",receipt)
		if mode=="restart":
			var ack: Dictionary=await replace_producer(original_epoch)
			if stopped or ack.is_empty():return
		else:
			world.detach_live();actions.poll()
		var outcome: Dictionary=actions.result(pending)
		if not check(outcome.get("outcome")==("not_sent" if mode=="queued" else "unknown"),"item lifecycle outcome differs"):return
		if not check(model.generation>generation and model.item_id==-1 and model.ticket==0 and model.snapshot.is_empty() and not sheet.visible and scene._ui.host.active==null,"item lifecycle retained sheet authority/input"):return
		if not check(actions._requests.is_empty() and actions._queue.is_empty() and actions._active==0,"item lifecycle retained pending intent"):return
		if mode!="restart":
			if not check(world.attach(),"item reconnect failed"):return
			var deadline:=Time.get_ticks_msec()+60000
			while Time.get_ticks_msec()<deadline:
				world.poll();actions.poll(0.02)
				if world.terrain_loaded() and not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0 and actions._queue.is_empty():break
				await create_timer(0.02).timeout
			if not check(not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0,"item reconnect not ready"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:
			world.poll();actions.poll();await process_frame
		if not check(no_farm_requests_since(next_ticket) and observed.size()==observations and model.snapshot.is_empty() and not sheet.visible,"item reconnect replayed edit/read or revived old observer"):return
		await lifecycle_open(baseline.building_id)
		if not await contents_ready():return
		await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,1).get_center())
		if not await item_ready():return
		if not check(model.item_id==baseline.id and model.snapshot.hidden==(not baseline.hidden if mode=="sent" else baseline.hidden),"fresh item observation after lifecycle differs"):return
		await capture("item_"+mode+"_fresh")
		if mode=="sent":
			await pointer(sheet.get_global_transform_with_canvas()*sheet.flag_rect(3).get_center())
			if not await item_ready():return
		if not check(model.snapshot.hidden==baseline.hidden,"item lifecycle restoration differs"):return
		await native("item-inspect",{"item":model.view_snapshot(),"revision_text":str(model.snapshot.revision)})
		if stopped:return
		evidence.append({"mode":mode,"item_id":baseline.id,"outcome":outcome.get("outcome"),"old_epoch":str(original_epoch),"fresh_epoch":str(actions._epoch),"no_replay":true,"fresh_read_and_restore":true})
		item_owner.close_panel()
	write_json("item-lifecycle-results.json",evidence)

func item_sheet_scene(initial: Dictionary) -> void:
	step="main item sheet navigation and edits"
	var item_owner=owner.item_owner;var view=owner.panel.contents
	await pointer(view.get_global_transform_with_canvas()*view.control_rect(5,1).get_center())
	if not await item_ready():return
	var model=item_owner.state;var sheet=item_owner.panel
	if not check(model.item_id==initial.rows[39].id and not owner.panel.visible and scene._ui.host.active==item_owner,"View did not transfer target and input ownership"):return
	var baseline: Dictionary=model.view_snapshot()
	await native("item-inspect",{"item":baseline,"revision_text":str(baseline.revision)})
	if stopped:return
	await capture("item_baseline")
	for index in [0,1,3]:
		for toggle in 2:
			await pointer(sheet.get_global_transform_with_canvas()*sheet.flag_rect(index).get_center())
			if not await item_ready():return
			await native("item-inspect",{"item":model.view_snapshot(),"revision_text":str(model.snapshot.revision)})
			if stopped:return
			await capture("item_flag_"+str(index)+"_"+str(toggle))
	if not check(model.snapshot==baseline,"item sheet flags not restored"):return
	await item_camera_scene()
	if stopped:return
	scene._fortress_hud.toggle_game_menu();await process_frame
	var next_ticket: int=actions._next_ticket
	await pointer(sheet.get_global_transform_with_canvas()*sheet.flag_rect(0).get_center())
	if not check(actions._next_ticket==next_ticket,"overlay allowed item edit through"):return
	scene._fortress_hud.close_menus();await process_frame
	await pointer(sheet.get_global_transform_with_canvas()*sheet.holder_rect().get_center())
	if not await contents_ready():return
	if not check(scene._ui.host.active==owner and not sheet.visible and model.snapshot.is_empty() and farm.building_id==initial.building_id,"holder View did not return to farm"):return
	for ending in ["escape","right","reset"]:
		await pointer(view.get_global_transform_with_canvas()*view.control_rect(0,1).get_center())
		if not await item_ready():return
		if ending=="right":await pointer(Vector2(400,400),MOUSE_BUTTON_RIGHT)
		else:key(KEY_ESCAPE if ending=="escape" else KEY_F10)
		await process_frame
		if not check(not sheet.visible and model.snapshot.is_empty() and scene._ui.host.active==null,"item close retained authority/input"):return
		owner.open_target(initial.building_id)
		if not await contents_ready():return
	write_json("item-scene-results.json",{"target":baseline.id,"flags_restored":true,"holder_roundtrip":true,"overlay_blocks_edit":true,"close":["escape","right","reset"]})

func follow_ready(expected: Variant=null) -> bool:
	var follow=scene._ui.item_follow
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		actions.poll(0.02);await create_timer(0.02).timeout
		if follow.last_position!=null and (expected==null or follow.last_position==expected):return true
	return check(false,"item follow did not receive expected position")

func follow_lifecycle_cases() -> void:
	var evidence: Array=[];var observed: Array=[]
	var follow=scene._ui.item_follow;var item_owner=owner.item_owner;var sheet=item_owner.panel
	follow.position_changed.connect(func(tile):observed.append(tile))
	follow.set_process(false)
	for mode in ["queued","sent","restart"]:
		step="item follow lifecycle "+mode
		await lifecycle_open(int(fixture.contents.building_id))
		if not await contents_ready():return
		var contents=owner.panel.contents
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(1,1).get_center())
		if not await item_ready():return
		var target: int=item_owner.state.item_id;var original_epoch: int=actions._epoch
		await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
		if not await follow_ready():return
		var count:=observed.size();var generation: int=follow.generation
		follow._process(1)
		var pending: int=follow.ticket
		if not check(pending>0 and actions._requests[pending].sequence==0,"follow lifecycle read not queued"):return
		if mode!="queued":
			await pointer(Vector2(400,400),MOUSE_BUTTON_RIGHT)
			if not check(not sheet.visible and follow.item_id==target and follow.last_position!=null,"follow did not survive sheet closure before lifecycle"):return
		if mode!="queued":
			actions.poll()
			var sequence: int=actions._requests[pending].sequence
			var receipt: Dictionary={};var deadline:=Time.get_ticks_msec()+30000
			while Time.get_ticks_msec()<deadline:
				world.poll();var candidate: Dictionary=world.poll_management()
				if candidate.get("request_seq")==sequence and candidate.get("status")==S.Ok:receipt=candidate;break
				await create_timer(0.01).timeout
			if not check(not receipt.is_empty() and receipt.production.item_position.id==target and observed.size()==count,"follow late receipt missing or delivered early"):return
			write_json("follow-"+mode+"-unobserved.json",receipt)
		if mode=="restart":
			var ack: Dictionary=await replace_producer(original_epoch)
			if stopped or ack.is_empty():return
		else:world.detach_live();actions.poll()
		var outcome: Dictionary=actions.result(pending)
		if not check(outcome.get("outcome")==("not_sent" if mode=="queued" else "unknown") and follow.generation>generation and follow.item_id==-1 and follow.ticket==0 and follow.last_position==null and not sheet.following,"follow lifecycle retained old identity/artwork"):return
		if mode!="restart":
			if not check(world.attach(),"follow reconnect failed"):return
			var deadline:=Time.get_ticks_msec()+60000
			while Time.get_ticks_msec()<deadline:
				world.poll();actions.poll(0.02)
				if world.terrain_loaded() and not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0 and actions._queue.is_empty():break
				await create_timer(0.02).timeout
			if not check(not actions._transport_lost and not actions._needs_claim and actions._active==0,"follow reconnect not ready"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:
			world.poll();actions.poll();follow._process(1);await process_frame
		if not check(no_farm_requests_since(next_ticket) and observed.size()==count and follow.item_id==-1,"follow lifecycle replayed or focused a late position"):return
		await lifecycle_open(int(fixture.contents.building_id))
		if not await contents_ready():return
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(1,1).get_center())
		if not await item_ready():return
		await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
		if not await follow_ready():return
		if not check(follow.item_id==target and sheet.following and observed.size()==count+1,"fresh explicit follow did not recover"):return
		evidence.append({"mode":mode,"item_id":target,"outcome":outcome.outcome,"old_epoch":str(original_epoch),"fresh_epoch":str(actions._epoch),"late_focus_suppressed":true,"explicit_recovery":true})
		follow.stop();item_owner.close_panel()
	follow.set_process(true)
	write_json("item-follow-lifecycle-results.json",evidence)

func item_camera_scene() -> void:
	var item_owner=owner.item_owner;var sheet=item_owner.panel
	var follow=scene._ui.item_follow;var rig=scene.camera_rig
	var target: int=item_owner.state.item_id
	var building: int=item_owner.state.building_id
	await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
	if not await follow_ready():return
	var original: Vector3i=follow.last_position
	await native("item-position",{"item_id":target,"x":original.x,"y":original.y,"z":original.z})
	if stopped:return
	if not check(sheet.following and follow.item_id==target,"camera click did not activate follow artwork"):return
	await capture("item_follow_active")
	var point:=Vector3(original.x+0.5,original.z+1.0,original.y+0.5)
	var projection=rig.get_node("Camera3D")
	for extent in [Vector2i(1280,720),Vector2i(960,640),Vector2i(1200,800)]:
		root.size=extent;await process_frame;await process_frame;await process_frame
		var anchor: Vector2=rig.native_follow_anchor(Vector2(extent),Vector2.ONE,32)
		if not check(projection.unproject_position(point).distance_to(anchor)<0.1 and anchor.x<sheet.get_global_transform_with_canvas().origin.x,"resize left followed target behind sheet"):return
	for button in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		await pointer(Vector2(200,400),button);await process_frame;await process_frame
		var anchor: Vector2=rig.native_follow_anchor(Vector2(root.size),Vector2.ONE,rig._df_pixels_per_tile)
		if not check(follow.item_id==target and projection.unproject_position(point).distance_to(anchor)<0.1,"zoom lost native follow framing"):return
	for mode in ["isometric","free"]:
		rig.set_mode(mode);await process_frame;await process_frame
		if not check(follow.item_id==target and projection.unproject_position(point).distance_to(Vector2(232,400))<0.1,"3D camera lost follow screen anchor"):return
		await capture("item_follow_"+mode)
	rig.set_mode("df");await process_frame;await process_frame
	await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
	if not check(follow.item_id==-1 and not sheet.following,"second camera click did not stop following"):return
	await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
	if not await follow_ready():return
	await pointer(Vector2(400,400),MOUSE_BUTTON_RIGHT)
	if not check(not sheet.visible and follow.item_id==target,"closing item sheet stopped following"):return
	await native("item-position-state",{"item_id":target,"state":"moved"})
	if stopped:return
	var moved:=original+Vector3i(1,-1,0)
	if not await follow_ready(moved):return
	var camera=rig.get_node("Camera3D")
	var projected: Vector2=camera.unproject_position(Vector3(moved.x+0.5,moved.z+1.0,moved.y+0.5))
	if not check(projected.distance_to(Vector2(272,400))<0.1,"camera did not frame native coordinates beside sheet"):return
	await capture("item_follow_moved_closed")
	await native("item-position-state",{"item_id":target,"state":"restored"})
	if stopped or not await follow_ready(original):return
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,300);motion.relative=Vector2(32,0);motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion,true);await process_frame
	if not check(follow.item_id==-1,"manual viewport pan retained follow identity"):return
	item_owner.open_target(building,target)
	if not await item_ready():return
	if not check(not sheet.following,"reopened sheet retained active camera artwork"):return
	write_json("item-follow-results.json",{"item_id":target,"toggle":true,"survives_close":true,"controlled_move":true,"restored":true,"manual_pan_stops":true,"native_anchor":true,"resize_zoom":true,"three_projections":true})

# Exercise actual item writes; farm rename/removal lifecycle does not establish
# the separate contents controller's retirement or its receipt-offset recovery.
func contents_disconnect_cases() -> void:
	var evidence: Array=[]
	var applied: Array=[]
	owner.contents.applied.connect(func():applied.append(true))
	for sent in [false,true]:
		step="contents disconnect sent="+str(sent)
		await lifecycle_open(int(fixture.contents.building_id))
		if not await contents_ready():return
		var initial: Dictionary=owner.contents.snapshot.duplicate(true)
		var expected: Array=initial.rows.duplicate(true)
		var observers: int=applied.size()
		var view=owner.panel.contents
		await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,5).get_center())
		var pending: int=owner.contents.ticket
		if not check(owner.contents.phase==owner.contents.Phase.Applying and pending>0 and actions._requests[pending].sequence==0,"item edit not queued by viewport click"):return
		if sent:
			actions.poll()
			if not check(actions._requests.has(pending) and actions._requests[pending].sequence>0,"item edit not sent"):return
			var sequence: int=actions._requests[pending].sequence
			var deadline:=Time.get_ticks_msec()+30000
			var receipt: Dictionary={}
			while Time.get_ticks_msec()<deadline:
				world.poll();var candidate: Dictionary=world.poll_management()
				if candidate.get("request_seq")==sequence and candidate.get("status")==S.Ok:receipt=candidate;break
				await create_timer(0.01).timeout
			if not check(not receipt.is_empty() and actions.result(pending).is_empty(),"missing unobserved item receipt"):return
			if not check(receipt.production.contents_edit.item_id==initial.rows[1].id and receipt.production.contents.cursor==1,"unobserved item receipt does not identify second row"):return
			write_json("contents-unobserved-receipt.json",receipt)
			expected[1].hidden=not expected[1].hidden
		await native("contents-verify",{"rows":expected,"cursor":0})
		if stopped:return
		world.detach_live();actions.poll()
		var outcome: Dictionary=actions.result(pending)
		if not check(outcome.get("outcome")==("unknown" if sent else "not_sent"),"item disconnect outcome differs"):return
		if not check(owner.contents.phase==owner.contents.Phase.Unavailable and owner.contents.building_id==-1 and owner.contents.ticket==0 and owner.contents.snapshot.is_empty(),"item disconnect retained authority"):return
		if not check(actions._requests.is_empty() and actions._queue.is_empty() and actions._active==0,"item disconnect retained pending intent"):return
		await lifecycle_retired("contents_disconnect_"+str(sent))
		if stopped:return
		if not check(world.attach(),"contents reconnect failed"):return
		var deadline:=Time.get_ticks_msec()+60000
		while Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.02)
			if world.terrain_loaded() and not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0 and actions._queue.is_empty():break
			await create_timer(0.02).timeout
		if not check(not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0,"contents reconnect not ready"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:
			world.poll();actions.poll();await process_frame
		if not check(no_farm_requests_since(next_ticket) and applied.size()==observers and owner.contents.snapshot.is_empty(),"reconnect replayed item edit or revived receipt observer"):return
		await native("contents-verify",{"rows":expected,"cursor":0})
		if stopped:return
		await lifecycle_open(int(fixture.contents.building_id))
		if not await contents_ready():return
		if not check(owner.contents.rows()==expected and owner.panel.contents.cell_first==0,"fresh contents read differs after disconnect"):return
		await capture("contents_disconnect_"+str(sent)+"_fresh")
		if sent:
			await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,5).get_center())
			if not await contents_ready():return
		if not check(owner.contents.snapshot==initial,"fresh item restoration differs"):return
		await native("contents-verify",{"rows":owner.contents.rows(),"cursor":0})
		if stopped:return
		evidence.append({"sent":sent,"item_id":initial.rows[1].id,"outcome":outcome.get("outcome"),"unobserved_receipt_retired":sent,"no_replay":true,"fresh_read_and_restore":true})
		owner.close_panel()
	write_json("contents-disconnect-results.json",evidence)

func contents_replacement_case() -> void:
	step="contents producer replacement"
	await lifecycle_open(int(fixture.contents.building_id))
	if not await contents_ready():return
	var initial: Dictionary=owner.contents.snapshot.duplicate(true)
	var old_epoch: int=actions._epoch
	var old_generation: int=owner.contents.generation
	var observed: Array=[]
	owner.contents.applied.connect(func():observed.append(true))
	var view=owner.panel.contents
	await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,5).get_center())
	var pending: int=owner.contents.ticket
	if not check(owner.contents.phase==owner.contents.Phase.Applying and pending>0,"replacement item edit not queued"):return
	actions.poll()
	if not check(actions._requests.has(pending) and actions._requests[pending].sequence>0,"replacement item edit not sent"):return
	var sequence: int=actions._requests[pending].sequence
	var deadline:=Time.get_ticks_msec()+30000
	var receipt: Dictionary={}
	while Time.get_ticks_msec()<deadline:
		world.poll();var candidate: Dictionary=world.poll_management()
		if candidate.get("request_seq")==sequence and candidate.get("status")==S.Ok:receipt=candidate;break
		await create_timer(0.01).timeout
	if not check(not receipt.is_empty() and actions.result(pending).is_empty() and observed.is_empty(),"replacement item receipt was missing or delivered early"):return
	if not check(receipt.production.contents_edit.item_id==initial.rows[1].id and receipt.production.contents.cursor==1,"replacement receipt target differs"):return
	write_json("contents-replacement-unobserved.json",receipt)
	var expected: Array=initial.rows.duplicate(true);expected[1].hidden=not expected[1].hidden
	await native("contents-verify",{"rows":expected,"cursor":0})
	if stopped:return
	await capture("contents_replacement_pending")
	var ack: Dictionary=await replace_producer(old_epoch)
	if stopped or ack.is_empty():return
	if not check(actions.result(pending).get("outcome")=="unknown" and not actions._requests.has(pending),"replacement confirmed or replayed the old item edit"):return
	if not check(owner.contents.generation>old_generation and owner.contents.building_id==-1 and owner.contents.ticket==0 and owner.contents.snapshot.is_empty() and observed.is_empty(),"old item observer survived replacement"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();await process_frame
	if not check(no_farm_requests_since(next_ticket) and observed.is_empty(),"replacement revived an item edit or receipt-offset recovery"):return
	await lifecycle_retired("contents_replacement")
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	await lifecycle_open(int(fixture.contents.building_id))
	if not await contents_ready():return
	var fresh: Dictionary=owner.contents.snapshot.duplicate(true)
	# The reloaded clone deliberately reuses the IDs; the new epoch must prevent
	# the previous receipt from changing the new fortress's same-numbered item.
	if not check(fresh.rows[1].id==initial.rows[1].id and fresh.rows[1].hidden==initial.rows[1].hidden and observed.is_empty(),"replacement item inherited the old edit"):return
	await native("contents-verify",{"rows":owner.contents.rows(),"cursor":0})
	if stopped:return
	await capture("contents_replacement_fresh")
	for toggle in 2:
		await pointer(view.get_global_transform_with_canvas()*view.control_rect(1,5).get_center())
		if not await contents_ready():return
		await native("contents-verify",{"rows":owner.contents.rows(),"cursor":0})
		if stopped:return
	if not check(observed.size()==2 and owner.contents.snapshot==fresh,"replacement fresh item edits did not restore contents"):return
	write_json("contents-replacement-results.json",{"old_epoch":str(old_epoch),"new_epoch":str(ack.epoch),"pid":ack.pid,"reused_item_id":fresh.rows[1].id,"old_outcome":actions.result(pending).get("outcome"),"old_observer_retired":true,"no_edit_or_recovery_replay":true,"fresh_edits_verified":true})
	owner.close_panel()
