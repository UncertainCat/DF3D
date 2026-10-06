extends "res://tests/areas_controller_live.gd"
# Real producer replacement while the actual Areas controller owns a read.
var invalidations := 0

func exercise_ui(origin: Vector3i) -> void:
	step = "controller restart setup"
	editor.inspect_tile(origin+Vector3i(21,21,0))
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"fixture stockpile"): return
	if not check(int(editor.selected.id) == int(fixture.pile),"restart fixture identity mismatch"): return
	var old_epoch := int(world.poll_session().get("fortress_epoch",0))
	actions.session_changed.connect(func(): invalidations += 1)
	editor.choose_preset(0)
	var old_ticket := int(editor.request_ticket)
	actions.poll()
	if not check(old_ticket > 0 and actions._active == old_ticket,"restart read was not submitted"): return
	var old_sequence := int(actions._requests[old_ticket].sequence)
	handshake += 1
	write_json("request-%d.json" % handshake,{"op":"reload"})
	var file := FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE)
	file.store_string(str(handshake)); file.close()
	if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt") == OK,"restart handshake failed"): return
	step = "controller producer replacement"
	var deadline := Time.get_ticks_msec()+690000
	var ack: Dictionary = {}
	while ack.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll(); world.poll_session(); actions.poll(0.02); editor._process(0.02)
		for state in ["failed","incomplete","ack"]:
			var path := directory+"/%s-%d" % [state,handshake]
			if not FileAccess.file_exists(path): continue
			var reply: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			if state == "failed": check(false,"restart: "+str(reply.reason)); return
			if state == "incomplete": incomplete("restart: "+str(reply.reason),true); return
			ack = reply
		await create_timer(0.02).timeout
	if not check(not ack.is_empty(),"restart timed out; no intent replay"): return
	var epoch := int(str(ack.epoch))
	if not check(epoch != old_epoch and (epoch >> 32) == int(ack.pid),"replacement epoch identity invalid"): return
	deadline = Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll(); world.poll_session(); actions.poll(0.02); editor._process(0.02)
		if actions._epoch == epoch and actions._active == 0 and actions._queue.is_empty(): break
		await create_timer(0.02).timeout
	if not check(actions._epoch == epoch and actions._active == 0 and actions._queue.is_empty(),"replacement service not ready"): return
	if not check(invalidations > 0 and not editor.available and editor.selected.is_empty()
		and editor.paint_state.cells.is_empty() and editor.settings_state.pending.is_empty()
		and editor.request_ticket == 0 and editor.zone_types.is_empty() and editor.zone_draft.is_empty()
		and editor.zone_picker.item_count == 0 and editor.zone_menu.catalog.is_empty(),"old controller identity, catalog or draft survived restart"): return
	if not check(not actions._requests.has(old_ticket) and not actions.result(old_ticket).is_empty(),"old read receipt was lost or replayed"): return
	print("AREA_RESTART_OLD_READ ticket=",old_ticket," sequence=",old_sequence," result=",actions.result(old_ticket))
	# Replacement must remain idle until explicit reopening; no old settings poll.
	var after_claim := int(actions._next_ticket)
	for frame in 30:
		world.poll(); actions.poll(0.02); editor._process(0.02); await create_timer(0.02).timeout
	if not check(int(actions._next_ticket) == after_claim,"old controller issued a fresh request after restart"): return
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var p: Dictionary = fixture.origin
	world.set_top_z(int(p.z))
	editor.close_panel(); editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"fresh catalog after restart"): return
	editor.inspect_tile(Vector3i(int(p.x)+21,int(p.y)+21,int(p.z)))
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"fresh area after restart"): return
	if not check(int(editor.selected.id) == int(fixture.pile) and int(editor.selected.revision)>0,"fresh area lacks authoritative identity"): return
	editor.stockpile_view.controls.links_only.pressed.emit()
	if not await wait_ui(settled,"fresh edit after restart"): return
	await native("snapshot",{"id":int(fixture.pile),"expected":{"links_only":false}})
	if not stopped: print("AREAS_CONTROLLER_RESTART_PASS old_epoch=",old_epoch," new_epoch=",epoch)
