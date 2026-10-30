extends "res://tests/farm_item_progress_live.gd"
var scene
var owner
var captures: Array=[]

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
		var actions=scene._ui.actions;actions.set_process(false)
		owner=scene._ui.controller("farm")
		await progress_cases(owner.item_owner.state,scene._ui.item_follow,actions)
	var status:="failed" if failed else "incomplete" if not reasons.is_empty() else "passed"
	write_json("result.json",{"status":status,"reasons":reasons,"native_checks":handshake,"captures":captures,"surface":"staged farm owner in actual main scene; viewport mouse input"})
	scene.queue_free();await process_frame;print("FARM_ITEM_PROGRESS_SCENE ",status);quit(1 if failed else 77 if status=="incomplete" else 0)

func pointer(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame

func open_item(model,follow,actions) -> void:
	owner.open_target(int(fixture.building_id))
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready:break
		await create_timer(0.01).timeout
	if not check(owner.panel.contents_allowed() and owner.contents.phase==owner.contents.Phase.Ready,"farm contents unavailable"):return
	var rows: Array=owner.contents.rows()
	if not check(rows.size()==1 and rows[0].id==int(fixture.item_id),"delivered potash not sole farm content"):return
	await process_frame
	var view=owner.panel.contents
	await pointer(view.get_global_transform_with_canvas()*view.control_rect(0,1).get_center())
	if not await settle(model,follow,actions):return
	check(model.item_id==int(fixture.item_id) and scene._ui.host.active==owner.item_owner and not owner.panel.visible,"View did not transfer input ownership to potash")

func edit_item(model,follow,actions,operation: int,value: bool) -> void:
	var index: int={Contract.FarmOperation.ItemForbid:0,Contract.FarmOperation.ItemDump:1,Contract.FarmOperation.ItemHidden:3}[operation]
	var key: String={0:"forbid",1:"dump",3:"hidden"}[index]
	if not check(model.snapshot[key]!=value,"viewport toggle already at desired value"):return
	var sheet=owner.item_owner.panel
	await pointer(sheet.get_global_transform_with_canvas()*sheet.flag_rect(index).get_center())
	await settle(model,follow,actions)

func start_follow(model,follow,actions) -> void:
	var sheet=owner.item_owner.panel
	await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
	if not await settle(model,follow,actions):return
	check(sheet.following and follow.item_id==int(fixture.item_id),"viewport camera click did not activate follow")

func observe_item(label: String) -> void:
	# Move off controls so captures compare the sheet rather than transient help.
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	check(image.save_png(directory+"/potash_scene_"+label+".png")==OK,"scene capture failed")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var expected: String=reference.potash_item_reference.panel_rgb_sha256
	if label!="baseline":
		expected=""
		for state in reference.potash_actions_reference.states:
			if state.name=="farm-potash-"+label.replace("_","-"):expected=state.rgb_sha256
	var sheet=owner.item_owner.panel
	var crop:=image.get_region(Rect2i(Vector2i(sheet.get_global_transform_with_canvas().origin),Vector2i(sheet.size)))
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
	var digest:=hash.finish().hex_encode()
	captures.append({"name":label,"rgb_sha256":digest})
	check(digest==expected,"rendered potash sheet differs from native: "+label)

func observe_retirement() -> void:
	await process_frame
	var host=scene._ui.host
	if not check(not owner.item_owner.panel.visible and host.active==null and not host.interaction.construction_active and host.allows_minimap_input() and host.allows_elevation_input(),"consumption retained sheet or input ownership"):return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/potash_scene_consumed.png")==OK,"consumed scene capture failed")
	write_json("potash-scene-retirement.json",{"sheet_hidden":true,"owner_released":true,"minimap_released":true,"elevation_released":true})

func request_pause(want_paused: bool) -> bool:
	# Interaction owns receipt draining in the actual main scene.
	var receipts: Array=[]
	var receive:=func(results: Array):receipts.append_array(results)
	var interaction=scene._ui.host.interaction
	interaction.command_results_received.connect(receive)
	var sequence: int=world.send_set_pause(want_paused)
	if not check(sequence>0,"scene pause command not sent"):
		interaction.command_results_received.disconnect(receive);return false
	var deadline:=Time.get_ticks_msec()+30000
	var accepted:=false
	while Time.get_ticks_msec()<deadline:
		for receipt in receipts:
			if int(receipt.seq)==sequence:
				if not check(int(receipt.status)==0 and receipt.message==("paused" if want_paused else "unpaused"),"scene pause command refused"):
					interaction.command_results_received.disconnect(receive);return false
				accepted=true
		receipts.clear()
		var session: Dictionary=world.poll_session()
		if accepted and session.get("fortress_valid",false) and session.get("paused",not want_paused)==want_paused:
			interaction.command_results_received.disconnect(receive);return true
		await create_timer(0.02).timeout
	interaction.command_results_received.disconnect(receive)
	incomplete("scene pause receipt/readback wait cap hit; no replay",true);return false

func observe_retained() -> void:
	await process_frame
	if not check(owner.item_owner.panel.visible and scene._ui.host.active==owner.item_owner and owner.item_owner.panel.following,"surviving post-Forbid potash lost sheet ownership or follow artwork"):return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/potash_scene_retained.png")==OK,"retained scene capture failed")
	write_json("potash-scene-retained.json",{"sheet_visible":true,"owner_retained":true,"following":true})

	if fixture.get("transfer_scene",false):await transfer_scene()

func transfer_scene() -> void:
	var model=owner.item_owner.state;var follow=scene._ui.item_follow;var actions=scene._ui.actions
	var sheet=owner.item_owner.panel
	await native("independent_transfer");if stopped:return
	model.poll(1);follow._process(1)
	if not await settle(model,follow,actions):return
	if not check(model.phase==model.Phase.Ready and model.snapshot.has("stockpile") and not model.snapshot.has("holder") and scene._ui.host.active==owner.item_owner,"rendered transfer lost item authority"):return
	await native("independent_verify",{"snapshot":model.view_snapshot(),"revision_text":str(model.snapshot.revision)});if stopped:return
	await pointer(sheet.get_global_transform_with_canvas()*sheet.camera_rect().get_center())
	if not await settle(model,follow,actions):return
	if not check(follow.item_id==-1,"camera toggle did not stop follow"):return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	for hidden in [true,false]:
		await edit_item(model,follow,actions,Contract.FarmOperation.ItemHidden,hidden);if stopped:return
		await native("independent_verify",{"snapshot":model.view_snapshot(),"revision_text":str(model.snapshot.revision)});if stopped:return
		var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var label:="hidden" if hidden else "visible"
		check(image.save_png(directory+"/transferred_"+label+".png")==OK,"transfer capture failed")
		var crop:=image.get_region(Rect2i(Vector2i(sheet.get_global_transform_with_canvas().origin),Vector2i(sheet.size)))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		var expected:=""
		for native_state in reference.independent_item_native_reference.runs[1].states:
			if native_state.name=="farm-potash-transfer-helper-"+label:expected=native_state.panel_rgb_sha256
		var digest:=hash.finish().hex_encode();captures.append({"name":"transferred_"+label,"rgb_sha256":digest})
		if not check(digest==expected,"transferred panel differs from native: "+label):return
	var target: int=model.snapshot.stockpile.id
	await pointer(sheet.get_global_transform_with_canvas()*sheet.stockpile_rect().get_center())
	var areas=scene._ui.controller("areas");var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if areas.request_ticket==0 and areas.selected.get("id",-1)==target:break
		await create_timer(0.01).timeout
	if not check(areas.selected.get("id",-1)==target and areas.selected.get("kind",-1)==0 and areas.mode=="inspect" and areas.panel.visible and scene._ui.host.active==areas and model.item_id==-1 and not sheet.visible,"View stockpile did not transfer ownership to fresh stockpile controls"):return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/stockpile_navigation.png")==OK,"stockpile navigation capture failed")
	write_json("item-transfer-scene-results.json",{"stockpile_id":target,"item_owner_retired":true,"viewport_navigation":true,"visibility_both_values":true,"stockpile_revision":str(areas.selected.revision)})

	var navigation_revision:=str(areas.selected.revision)
	var retired: Array=[]
	for sent in [false,true]:
		areas.close_panel();areas.open_stockpile(target)
		var ticket: int=areas.request_ticket
		if not check(ticket>0,"stockpile handoff did not queue bootstrap"):return
		if sent:actions.poll()
		areas.close_panel()
		deadline=Time.get_ticks_msec()+30000
		while actions.result(ticket).is_empty() and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll();await create_timer(0.01).timeout
		if not check(not actions.result(ticket).is_empty() and not areas.panel.visible and areas.request_ticket==0 and areas._open_stockpile_id==-1 and scene._ui.host.active==null,"late stockpile bootstrap revived retired handoff"):return
		if not sent and not check(actions.result(ticket).outcome=="not_sent","closed queued handoff was sent"):return
		retired.append({"sent":sent,"outcome":actions.result(ticket).get("outcome","")})
	areas.open_stockpile(2147483647)
	deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if areas.request_ticket==0 and areas._open_stockpile_id==-1:break
		await create_timer(0.01).timeout
	if not check(areas.request_problem and areas.selected.is_empty(),"missing stockpile acquired selection authority"):return
	areas.close_panel()
	write_json("item-transfer-scene-results.json",{"stockpile_id":target,"item_owner_retired":true,"viewport_navigation":true,"visibility_both_values":true,"stockpile_revision":navigation_revision,"closed_bootstrap":retired,"missing_stockpile_rejected":true})
