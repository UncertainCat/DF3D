extends "res://tests/areas_controller_scene_restart_live.gd"
# Actual producer replacement with a sent target query and an undelivered native
# reply. The inherited GPU harness already owns manual semantic-service polling.
func open_fixture() -> void:
	var p: Dictionary = fixture.origin
	var tile := Vector3i(int(p.x)+21,int(p.y)+21,int(p.z))
	world.set_top_z(tile.z)
	scene.camera_rig.focus_on(Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5),30)
	var launcher: Button = scene._fortress_hud.navigation.Stockpiles
	for frame in 12:
		scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
	await click_control(launcher)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"restart launcher"): return
	await pointer_click(tile_screen(tile))
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"restart inspect"): return
	check(int(editor.selected.id)==int(fixture.pile),"restart source identity")

func start_pick() -> Vector3i:
	await click_control(editor.stockpile_view.controls.links)
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"restart links list"): return Vector3i.ZERO
	var wp: Dictionary = fixture.workshop_origin
	var tile := Vector3i(int(wp.x),int(wp.y),int(wp.z))
	scene.camera_rig.focus_on(Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5),30)
	for frame in 12: await process_frame
	await click_control(editor.links_view.add_buttons[0])
	check(editor.links_picking and editor.mode=="link_pick","restart picker not active")
	return tile

func pointer_areas() -> void:
	step = "pending link query before producer replacement"
	await open_fixture()
	if stopped: return
	var old_epoch := int(world.poll_session().get("fortress_epoch",0))
	actions.session_changed.connect(func(): invalidations += 1)
	var tile := await start_pick()
	if stopped: return
	await native("guard_before")
	await pointer_click(tile_screen(tile))
	var ticket := int(editor.request_ticket)
	if not check(ticket>0 and editor.links_picking,"target query was not queued"): return
	actions.poll(0.02)
	if not check(actions._active==ticket and int(actions._requests[ticket].sequence)>0,"target query was not sent"): return
	var sequence := int(actions._requests[ticket].sequence)
	# Observe the private native receipt without delivering it to the controller.
	var deadline := Time.get_ticks_msec()+30000
	var ready: Dictionary = {}
	while Time.get_ticks_msec()<deadline:
		var header: Dictionary = world.poll_management_header()
		if int(header.get("request_seq",0))==sequence and int(header.get("status",0))==S.Ok:
			ready=world.management_payload(old_epoch,int(header.revision),sequence); break
		await create_timer(0.02).timeout
	if not check(not ready.is_empty() and ready.area.links.size()==1 and int(ready.area.links[0].id)==int(fixture.workshop),"native target reply missing"): return
	if not check(actions._active==ticket and editor.links_picking,"native target reply was delivered early"): return
	await native("guard_after")
	await capture("link_restart_pending")
	handshake += 1
	write_json("request-%d.json" % handshake,{"op":"reload"})
	var file := FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE)
	file.store_string(str(handshake)); file.close()
	if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt")==OK,"restart handshake failed"): return
	step = "link picker producer loss and replacement"
	deadline = Time.get_ticks_msec()+690000
	var ack: Dictionary = {}
	var lost := false
	while ack.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll_session()
		var header: Dictionary = world.poll_management_header()
		if not bool(header.get("transport_alive",true)): lost=true
		# Do not deliver the old completed query while the restart lane hashes
		# saves. Resume production polling only after confirmed transport loss.
		if lost: actions.poll(0.02); editor._process(0.02)
		for state in ["failed","incomplete","ack"]:
			var path := directory+"/%s-%d" % [state,handshake]
			if not FileAccess.file_exists(path): continue
			var reply: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			if state=="failed": check(false,"restart: "+str(reply.reason)); return
			if state=="incomplete": incomplete("restart: "+str(reply.reason),true); return
			ack=reply
		await create_timer(0.02).timeout
	if not check(lost and not ack.is_empty(),"producer loss/restart not observed"): return
	var epoch := int(str(ack.epoch))
	if not check(epoch!=old_epoch and (epoch>>32)==int(ack.pid),"replacement epoch identity invalid"): return
	if not await wait_ui(func(): return actions._epoch==epoch and actions._active==0 and actions._queue.is_empty() and not actions._needs_claim and not actions._transport_lost and scene._loader.entered and scene._fortress_hud.enabled,"replacement service claim"): return
	if not check(invalidations>0 and not editor.links_picking and editor.selected.is_empty() and editor.request_ticket==0
		and editor.observed_links.is_empty() and editor.links_pending.is_empty() and not editor.panel.visible,"old picker survived producer loss"): return
	if not check(not actions._requests.has(ticket) and str(actions._results.get(ticket,{}).get("outcome",""))=="unknown","old sent query was not retired"): return
	await capture("link_restart_retired")
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	await native("guard_before")
	var after_claim := int(actions._next_ticket)
	for frame in 30:
		actions.poll(0.02); editor._process(0.02); await create_timer(0.02).timeout
	if not check(int(actions._next_ticket)==after_claim,"old picker submitted another request"): return
	await native("guard_after")
	for give in [true,false]:
		await native("link",{"id":int(fixture.workshop),"pile_id":int(fixture.pile),"give":give,"linked":false})
	await open_fixture()
	if stopped: return
	tile=await start_pick()
	if stopped: return
	await pointer_click(tile_screen(tile))
	if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"fresh link after restart"): return
	await native("link",{"id":int(fixture.workshop),"pile_id":int(fixture.pile),"give":false,"linked":true})
	await capture("link_restart_reopened")
	await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"fresh unlink after restart"): return
	await native("link",{"id":int(fixture.workshop),"pile_id":int(fixture.pile),"give":false,"linked":false})
	await native("final")
	write_json("link-restart-evidence.json",{"old_epoch":str(old_epoch),"new_epoch":str(epoch),"ticket":ticket,"sequence":sequence,"transport_lost":lost,"invalidations":invalidations})
