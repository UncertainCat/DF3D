extends "res://tests/standing_automation_wire_live.gd"
func ready_state(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while state.phase!=state.Phase.Ready and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
	return check(state.phase==state.Phase.Ready,"Labor authority failed: %s phase=%s result=%s"%[state.get_script().resource_path,state.phase,state.last_result])
func handshake(step: int) -> bool:
	var file:=FileAccess.open(directory+"/labor-lifecycle-request",FileAccess.WRITE)
	file.store_string(str(step));file.close()
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		if FileAccess.file_exists(directory+"/labor-lifecycle-ack") and FileAccess.get_file_as_string(directory+"/labor-lifecycle-ack")==str(step):return true
		await create_timer(0.01).timeout
	return check(false,"Native lifecycle acknowledgement missing")
func settled(main) -> bool:
	var deadline:=Time.get_ticks_msec()+90000
	var stable_since:=0;var epoch: int=-1;var generation: int=-1
	var actions=main._ui.actions
	var last_readiness: Array=[]
	var next_trace:=0
	while Time.get_ticks_msec()<deadline:
		var readiness: Array=[world.is_attached(),world.live_synchronized(),world.terrain_loaded(),world.pending_block_count(),world.composite_pending_count(),world.building_pending_count(),world.item_composite_pending_count(),main._focused,main._loader.entered]
		if readiness!=last_readiness and Time.get_ticks_msec()>=next_trace:
			last_readiness=readiness;next_trace=Time.get_ticks_msec()+1000;print("LABOR_RECOVERY_READINESS ",readiness)
		# The main scene keeps submitting background reads. Recovery requires a
		# stable claimed identity and input readiness, not an idle shared queue.
		var ready: bool=main._loader.entered and main._ui.host.play_enabled and not actions._transport_lost and not actions._needs_claim and actions._epoch>0 and actions._generation==world.session_generation()
		if not ready or epoch!=actions._epoch or generation!=actions._generation:stable_since=0
		epoch=actions._epoch;generation=actions._generation
		if ready:
			if stable_since==0:stable_since=Time.get_ticks_msec()
			elif Time.get_ticks_msec()-stable_since>=500:return true
		await create_timer(0.02).timeout
	var snapshot: Dictionary={"entered":main._loader.entered,"play_enabled":main._ui.host.play_enabled,"transport_lost":actions._transport_lost,"needs_claim":actions._needs_claim,"active":actions._active,"queue":actions._queue.duplicate(),"epoch":str(actions._epoch),"generation":actions._generation,"world_generation":world.session_generation(),"session":world.poll_session(),"management":world.poll_management_header()}
	var output:=FileAccess.open(directory+"/labor-lifecycle-unsettled.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(snapshot));output.close()
	return check(false,"Labor replacement connection did not settle: "+JSON.stringify(snapshot))
func run() -> void:
	if OS.get_environment("DF3D_MANAGEMENT_LIFECYCLE")=="1":
		await management_run();return
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	OS.set_environment("DF3D_FIXTURE","")
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);world=main.world
	var deadline:=Time.get_ticks_msec()+90000
	while (not main._loader.entered or not main._ui.host.play_enabled or main._ui.actions._needs_claim) and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if not check(main._loader.entered and main._ui.host.play_enabled,"Labor main scene did not enter fortress"):quit(1);return
	var owner=main._ui.controller("standing_orders")
	var records: Array=[]
	for kind in 3:
		owner.open_panel()
		if not await ready_state(owner.state):quit(1);return
		var state;var panel
		if kind==0:
			owner.open_kitchen();state=owner.kitchen_state;panel=owner.kitchen_panel
		elif kind==1:
			owner.open_stone_use();state=owner.stone_state;panel=owner.stone_panel
		else:
			owner.state.select_category(6)
			if not await ready_state(owner.state):quit(1);return
			await pointer(owner.panel,owner.panel.ammunition_rect().get_center())
			state=owner.ammunition_owner.state;panel=owner.ammunition_owner.panel
		if not await ready_state(state):quit(1);return
		if kind==0:state.first=1
		elif kind==1:state.select_category(1);state.seek(1,15)
		else:state.begin_amount(0);state.set_amount_text("123")
		var generation: int=state.generation
		if not await handshake(kind*2+1):quit(1);return
		deadline=Time.get_ticks_msec()+10000
		while panel.visible and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
		check(not panel.visible and main._ui.host.active==null,"Transport loss retained panel ownership")
		check(state.generation>generation and state.ticket==0,"Transport loss retained request authority")
		if kind==2:check(state.specs.is_empty() and state.amount_text.is_empty(),"Hunter loss retained receipt/draft")
		else:check(state.rows.is_empty(),"Labor loss retained rows")
		if not await handshake(kind*2+2):quit(1);return
		if not await settled(main):quit(1);return
		check(not panel.visible and main._ui.host.active==null,"Reconnect reopened stale panel")
		owner.open_panel()
		if not await ready_state(owner.state):quit(1);return
		if kind==0:owner.open_kitchen()
		elif kind==1:owner.open_stone_use()
		else:
			owner.state.select_category(6)
			if not await ready_state(owner.state):quit(1);return
			owner.open_ammunition()
		if not await ready_state(state):quit(1);return
		check(panel.visible,"Fresh Labor read failed to reopen panel")
		if kind==2:check(not state.specs.is_empty() and state.amount_text.is_empty(),"Fresh Hunter authority/draft incorrect")
		else:check(not state.rows.is_empty(),"Fresh Labor read returned no rows")
		main._ui.host.close_active()
		records.append({"kind":kind,"retired":true,"fresh_read":true})
		if failed:quit(1);return
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"main":true,"transport_cycles":records}));output.close()
	main.queue_free();await process_frame;await process_frame
	quit(1 if failed else 0)

func management_run() -> void:
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	OS.set_environment("DF3D_FIXTURE","")
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);world=main.world
	if not await settled(main):quit(1);return
	var actions=main._ui.actions
	var records: Array=[]
	var screens: Array=[{"name":"Tasks","owner":"tasks","key":"job_id"},{"name":"Objects","owner":"objects","key":"artifact_id"},{"name":"Justice","owner":"justice","key":"crime_id"}]
	for index in screens.size():
		var spec: Dictionary=screens[index]
		var owner=main._ui.controller(spec.owner);var state=owner.state
		await hud_click(main._fortress_hud.launcher_rect(spec.name).get_center())
		if not await ready_state(state):quit(1);return
		check(owner.panel.visible and main._ui.host.active==owner,"Public management entry lost owner: "+spec.name)
		var ids: Array=state.rows.map(func(row):return row.get(spec.key,-1))
		# Hold delivery after dispatch so a pre-loss read cannot grant authority
		# to the replacement producer, even if DF completed it before disabling.
		actions.set_process(false)
		var interrupted_edit: bool=index==0 and OS.get_environment("DF3D_MANAGEMENT_MUTATION")=="1"
		if interrupted_edit:
			var row_index: int=ids.find(68196)
			if not check(row_index>=0 and state.rows[row_index].suspended and state.rows[row_index].can_suspend,"Interrupted Tasks fixture unavailable"):quit(1);return
			state.seek(row_index,owner.panel.capacity())
			await pointer(owner.panel,owner.panel.button_rect(row_index-state.first,3).get_center())
		else:state.refresh()
		var old_ticket: int=state.ticket
		var deadline:=Time.get_ticks_msec()+5000
		while actions._requests.has(old_ticket) and int(actions._requests[old_ticket].sequence)==0 and Time.get_ticks_msec()<deadline:
			actions.poll(0.01);await process_frame
		if not check(old_ticket>0 and actions._requests.has(old_ticket) and int(actions._requests[old_ticket].sequence)>0,"Management read was not dispatched: "+spec.name):quit(1);return
		var generation: int=state.generation
		if not await handshake(index*2+1):quit(1);return
		actions.set_process(true)
		deadline=Time.get_ticks_msec()+10000
		while owner.panel.visible and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
		check(not owner.panel.visible and main._ui.host.active==null,"Producer loss retained management owner: "+spec.name)
		check(state.generation>generation and state.ticket==0 and state.rows.is_empty(),"Producer loss retained management facts: "+spec.name)
		if spec.owner=="justice":check(state.detail.is_empty(),"Justice retained case detail after loss")
		if not await handshake(index*2+2):quit(1);return
		if not await settled(main):quit(1);return
		check(not owner.panel.visible and state.rows.is_empty(),"Reconnect reused retired management facts: "+spec.name)
		await hud_click(main._fortress_hud.launcher_rect(spec.name).get_center())
		if not await ready_state(state):quit(1);return
		check(owner.panel.visible and state.rows.map(func(row):return row.get(spec.key,-1))==ids,"Fresh management membership changed: "+spec.name)
		if interrupted_edit:
			check(actions.result(old_ticket).get("outcome")=="unknown","Interrupted Tasks edit did not retire as unknown")
			var submitted: Array=[]
			for collection in [actions._outcomes,actions._requests]:
				for request_ticket in collection:
					var request: Dictionary=collection[request_ticket].get("request",{})
					if request.get("action")==C.ManagementAction.TasksApply and request.get("job_id")==68196:submitted.append(request_ticket)
			check(submitted==[old_ticket],"Interrupted Tasks edit was replayed")
			var row_index: int=ids.find(68196)
			check(not state.rows[row_index].suspended,"Fresh Tasks read lost completed native edit")
			state.seek(row_index,owner.panel.capacity())
			await pointer(owner.panel,owner.panel.button_rect(row_index-state.first,3).get_center())
			if not await ready_state(state):quit(1);return
			check(state.rows[row_index].suspended,"Explicit Tasks restore failed")
			records.append({"screen":"Tasks","unknown_edit":true,"no_replay":submitted==[old_ticket],"fresh_effect":true,"restored":true})
		main._ui.host.close_active()
		records.append({"screen":spec.name,"rows":ids.size(),"retired":true,"fresh_read":true})
		if failed:quit(1);return
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"main":true,"transport_cycles":records}));output.close()
	main.queue_free();await process_frame;await process_frame
	quit(1 if failed else 0)

func hud_click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.position=point;event.global_position=point;root.push_input(event,true);await process_frame
