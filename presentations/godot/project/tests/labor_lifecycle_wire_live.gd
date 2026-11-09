extends "res://tests/standing_automation_wire_live.gd"
func ready_state(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while state.phase in [state.Phase.Reading,state.Phase.Applying] and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
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
	var deadline:=Time.get_ticks_msec()+15000
	var stable_since:=0;var epoch: int=-1;var generation: int=-1
	var actions=main._ui.actions
	while Time.get_ticks_msec()<deadline:
		var ready: bool=main._loader.entered and main._ui.host.play_enabled and not actions._transport_lost and not actions._needs_claim and actions._active==0 and actions._queue.is_empty() and actions._epoch>0 and actions._generation==world.session_generation()
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
	quit(1 if failed else 0)
