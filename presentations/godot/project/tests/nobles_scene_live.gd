extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "nobles-native.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func commit_handoff(expected: Dictionary) -> bool:
	var target: Dictionary=expected.pickers[0].selected
	var index:=-1;var setting:=-1
	for i in owner.state.rows.size():
		var row: Dictionary=owner.state.rows[i]
		if row.entity_id==int(target.entity_id) and row.assignment_id==int(target.assignment_id):index=i
		if row.get("help",{}).has("accounting"):setting=row.help.accounting.setting
	if not check(index>=0 and setting>=0,"Main appointment target missing"):return false
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(200,owner.panel.list_top()+index*36+18))
	await drain()
	if not check(owner.state.phase==owner.state.Phase.CandidatesReady,"Main appointment picker unavailable"):return false
	var chosen:=-1;index=-1
	for i in owner.state.candidates.size():
		if owner.state.candidates[i].unit_id>=0:chosen=owner.state.candidates[i].unit_id;index=i;break
	if not check(index>=0 and index<owner.panel.capacity(),"Main appointment candidate not visible"):return false
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,owner.panel.list_top()+index*36+18))
	if not await settle(owner.state):return false
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(352,24))
	var ticket: int=owner.state.ticket
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(352,24))
	check(ticket>0 and owner.state.ticket==ticket and owner.state.phase==owner.state.Phase.Applying and scene._ui.host.active==owner,"Main handoff did not retain one pending commit")
	await drain()
	var destination=scene._ui.controller("workshop")
	if not check(scene._ui.host.active==destination and destination.global_orders_mode and owner.state.phase==owner.state.Phase.Closed,"Confirmed main appointment did not open global Work orders"):return false
	var file=FileAccess.open(directory+"/nobles-commit-wire.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit_id":chosen,"entity_id":int(target.entity_id),"assignment_id":int(target.assignment_id),"accounting_values":[],"accounting_restored":setting,"main_scene_handoff":true}));file.close()
	owner.open_panel()
	return await settle(owner.state)
func lifecycle_handshake(step: int) -> bool:
	var file=FileAccess.open(directory+"/nobles-lifecycle-request",FileAccess.WRITE)
	file.store_string(str(step));file.close()
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		if FileAccess.file_exists(directory+"/nobles-lifecycle-ack") and FileAccess.get_file_as_string(directory+"/nobles-lifecycle-ack")==str(step):return true
		await create_timer(0.01).timeout
	return check(false,"Nobles lifecycle handshake timed out")
func lifecycle_recovery(expected: Dictionary) -> bool:
	# Optionally send once, then stop observing until DF confirms the effect
	# and disables the producer. Recovery must never replay that request.
	var sent_case:=OS.get_environment("DF3D_NOBLES_LIFECYCLE_SENT")=="1"
	var sent_ticket:=0
	var target: Dictionary=expected.pickers[0].selected
	var row: Dictionary={}
	for candidate in owner.state.rows:
		if candidate.entity_id==int(target.entity_id) and candidate.assignment_id==int(target.assignment_id):row=candidate;break
	if not check(not row.is_empty(),"Lifecycle office missing"):return false
	owner.state.begin_appointment(owner.state.office(row));await drain()
	if not check(owner.state.phase==owner.state.Phase.CandidatesReady,"Lifecycle candidates unavailable"):return false
	var chosen:=-1
	for candidate in owner.state.candidates:
		if candidate.unit_id>=0:chosen=candidate.unit_id;break
	if not check(chosen>=0,"Lifecycle candidate missing"):return false
	owner.state.choose_candidate(chosen)
	if not await settle(owner.state):return false
	if not check(owner.state.choices.size()==1,"Lifecycle draft missing"):return false
	var generation: int=owner.state.generation
	if sent_case:
		await drain();owner.state.request_dismiss();sent_ticket=owner.state.ticket
		var send_deadline:=Time.get_ticks_msec()+10000
		while actions._requests.has(sent_ticket) and int(actions._requests[sent_ticket].sequence)==0 and Time.get_ticks_msec()<send_deadline:
			actions.poll(0.01)
			if int(actions._requests.get(sent_ticket,{}).get("sequence",0))>0:break
			await create_timer(0.01).timeout
		if not check(sent_ticket>0 and int(actions._requests.get(sent_ticket,{}).get("sequence",0))>0 and owner.state.phase==owner.state.Phase.Applying,"Appointment was not sent exactly once before loss"):return false
		var intent_file=FileAccess.open(directory+"/nobles-lifecycle-intent.json",FileAccess.WRITE)
		intent_file.store_string(JSON.stringify({"chosen":chosen,"target":owner.state.office(row)}));intent_file.close()
	if not await lifecycle_handshake(1):return false
	actions.set_process(true)
	var deadline:=Time.get_ticks_msec()+10000
	while owner.panel.visible and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
	check(not owner.panel.visible and not owner.name_panel.visible and scene._ui.host.active==null,"Nobles loss retained input ownership")
	check(owner.state.generation>generation and owner.state.ticket==0 and owner.state.rows.is_empty() and owner.state.choices.is_empty(),"Nobles loss retained draft authority")
	if sent_case:check(actions.result(sent_ticket).get("outcome")=="unknown","Lost sent appointment was not retained as unknown")
	if not await lifecycle_handshake(2):return false
	deadline=Time.get_ticks_msec()+60000
	var stable_since:=0;var epoch: int=-1;var connection_generation: int=-1
	while Time.get_ticks_msec()<deadline:
		var ready: bool=scene._loader.entered and scene._ui.host.play_enabled and not actions._transport_lost and not actions._needs_claim and actions._epoch>0 and actions._generation==world.session_generation()
		if not ready or epoch!=actions._epoch or connection_generation!=actions._generation:stable_since=0
		epoch=actions._epoch;connection_generation=actions._generation
		if ready:
			if stable_since==0:stable_since=Time.get_ticks_msec()
			elif Time.get_ticks_msec()-stable_since>=500:break
		await create_timer(0.02).timeout
	if not check(stable_since>0 and Time.get_ticks_msec()-stable_since>=500,"Nobles replacement connection unavailable"):return false
	check(not owner.panel.visible and scene._ui.host.active==null,"Reconnect reopened stale Nobles panel")
	actions.set_process(false)
	owner.open_panel()
	if not await settle(owner.state):
		print("NOBLES_RECOVERY_FAILED ",owner.state.phase," ",owner.state.last_result," ",actions._epoch," ",actions._generation," ",world.session_generation());return false
	check(owner.panel.visible and owner.state.choices.is_empty(),"Fresh Nobles read restored stale draft")
	var refreshed: Dictionary={}
	for candidate in owner.state.rows:
		if owner.state.office(candidate)==owner.state.office(row):refreshed=candidate;break
	check(not refreshed.is_empty() and (refreshed.get("unit_id")==chosen if sent_case else refreshed.get("unit_id")!=chosen),"Recovered holder differs from native effect")
	var file=FileAccess.open(directory+"/nobles-lifecycle-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"sent_case":sent_case,"sent_outcome":actions.result(sent_ticket).get("outcome","") if sent_case else "not_sent","draft_retired":true,"fresh_read":true,"chosen":chosen,"holder":refreshed.get("unit_id"),"success":not failed}));file.close()
	return not failed
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("nobles");owner.open_panel()
	if not await settle(owner.state):return
	check(owner.state.rows.size()==expected.rows.size(),"Composed Nobles rows differ")
	check(scene._interaction.construction_active,"Nobles does not own world input")
	if OS.get_environment("DF3D_NOBLES_LIFECYCLE")=="1" and not await lifecycle_recovery(expected):return
	for dimensions in [Vector2i(912,552),Vector2i(1600,900)]:
		root.size=dimensions;await process_frame;await process_frame
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(136,24));await drain()
		var tasks=scene._ui.controller("tasks")
		check(scene._ui.host.active==tasks and not owner.panel.visible,"Nobles header failed to reach Tasks")
		await pointer(tasks.panel.get_global_transform_with_canvas()*Vector2(24 if dimensions.x<1240 else 456,24))
		if not await settle(owner.state):return
		check(scene._ui.host.active==owner and not tasks.panel.visible,"Tasks failed to return to Nobles")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-main-"+str(dimensions.x)+".png")
	scene._fortress_hud.toggle_game_menu();await process_frame
	check(scene._ui.host.overlay_blocked,"Nobles overlay gate missing")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(136,24))
	check(scene._ui.host.active==owner,"Overlay allowed Nobles header navigation")
	scene._fortress_hud.close_menus();await process_frame
	if OS.get_environment("DF3D_NOBLES_SCENE_COMMIT")=="1" and not await commit_handoff(expected):return
	key(KEY_F10);await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible and not scene._interaction.construction_active,"Nobles reset did not release map input")
	await drain();exercised=true
