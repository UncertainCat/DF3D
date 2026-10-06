extends "res://tests/areas_multi_controller_live.gd"
var invalidations := 0

func exercise_multi() -> void:
	step = "Multi receipt before producer replacement"
	if not await open_multi(): return
	select_bed()
	if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"pre-restart creation"): return
	var token: int = editor.multi_state.undo_token
	var scope: int = editor.multi_state.interaction_id
	var old_epoch := int(world.poll_session().get("fortress_epoch",0))
	if not check(token > 0 and old_epoch > 0,"missing pre-restart authority"): return
	await native("multi_check",{"count":1})
	editor.multi_pointer(Vector3i(172,57,164),true); editor.multi_pointer(Vector3i(172,57,164),false)
	if not check(editor.dragging,"pre-restart partial gesture missing"): return
	actions.session_changed.connect(func(): invalidations += 1)
	handshake += 1
	write_json("request-%d.json" % handshake,{"op":"reload"})
	var file := FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE)
	file.store_string(str(handshake)); file.close()
	if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt") == OK,"restart handshake failed"): return
	step = "Multi producer replacement"
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
	if not check(epoch != old_epoch and (epoch >> 32) == int(ack.pid),"replacement epoch invalid"): return
	if not await wait_ui(func(): return actions._epoch == epoch and actions._active == 0 and actions._queue.is_empty(),"new producer service"): return
	if not check(invalidations > 0 and editor.multi_state.interaction_id == 0 and editor.multi_state.undo_token == 0
		and not editor.available and not editor.dragging and editor.zone_types.is_empty() and editor.zone_draft.is_empty(),"old Multi authority or gesture survived producer replacement"): return
	var tickets: int = actions._next_ticket
	for frame in 30:
		world.poll(); actions.poll(0.02); editor._process(0.02); await create_timer(0.02).timeout
	if not check(actions._next_ticket == tickets,"retired Multi automatically submitted work"): return
	await native("multi_begin")
	await native("multi_check",{"count":0})
	if not await open_multi(): return
	var retired: int = actions.submit("areas",{"action":Contract.ManagementAction.AreaUpdate,"kind":1,
		"operation":Contract.AreaOperation.MultiUndo,"interaction_id":scope,"undo_token":token},Callable())
	if not await wait_ui(func(): return not actions.result(retired).is_empty(),"old producer token"): return
	var response: Dictionary = actions.result(retired)
	write_json("old-producer-token.json",{"old_epoch":str(old_epoch),"new_epoch":str(epoch),"response":response})
	if not check(int(response.get("status",-1)) == S.Rejected and int(response.get("area",{}).get("room_outcome",-1)) == Contract.AreaRoomOutcome.Rejected,"old producer token was not refused"): return
	select_bed()
	if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"new producer creation"): return
	await native("multi_check",{"count":1})
	editor.paint_view.accept_button.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.multi_state.has_result(),"new producer Undo"): return
	await native("multi_check",{"count":0})
	await native("multi_cleanup")
