extends "res://tests/areas_controller_live.gd"
# Real controller/action-service reconnect, with native readbacks. Headless;
# pointer and rendered acceptance belong to the separate scene driver.
func exercise() -> void:
	step = "Multi controller setup"
	await native("multi_begin")
	if stopped: return
	if not check(world.load_assets(FileAccess.get_file_as_string(directory+"/df-path.txt")),"installed assets unavailable"): return
	world.set_top_z(164)
	interaction = preload("res://tests/areas_test.gd").FakeInteraction.new(); root.add_child(interaction)
	host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	actions = preload("res://scripts/semantic_action_service.gd").new(); actions.configure(world); root.add_child(actions); actions.set_process(false)
	editor = preload("res://scripts/areas.gd").new()
	editor.world = world; editor.action_service = actions; editor.ui_host = host; editor.interaction = interaction
	camera = Camera3D.new(); root.add_child(camera); editor.camera = camera
	root.add_child(editor); host.register(editor); editor.set_process(false)
	editor.set_area_kind(1)
	await exercise_multi()
	editor.close_panel(); editor.free(); camera.free(); actions.free(); host.free(); interaction.free()
	if not stopped: await native("multi_final")

func exercise_multi() -> void:
	await mixed_result_case()
	if not stopped: await reconnect_case()
	if not stopped: await unobserved_receipt_case()

func mixed_result_case() -> void:
	step = "mixed Bedroom/Dormitory controller result"
	var prepared := await native("multi_case_prepare",{"case":"beds-mixed-bedroom-dormitory"})
	if stopped: return
	var selection: Dictionary = prepared.selection
	var first := Vector3i(int(selection.x),int(selection.y),int(selection.z))
	var last := first+Vector3i(int(selection.width)-1,0,0)
	for finish in [false,true]:
		if not await open_multi(): return
		var tickets: int = actions._next_ticket
		editor.multi_pointer(first,true); editor.multi_pointer(first,false)
		if not check(editor.dragging and actions._next_ticket == tickets,"first corner submitted a mutation"): return
		editor.multi_pointer(last,true); editor.multi_pointer(last,false)
		if not check(actions._next_ticket == tickets+1,"rectangle did not submit exactly one intent"): return
		if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"mixed creation"): return
		await native("multi_case_check")
		if stopped: return
		var view = editor.paint_view
		var observed: Dictionary = editor.multi_state.observed
		# Native source: multi-native-drag-042938/mixed-result-screen.txt.
		if not check(int(observed.rooms_created) == 2 and int(observed.rooms_dormitories) == 1
			and view.multi_result.visible and view.multi_result.text == "Bedroom created.\nDormitory created."
			and view.multi_rejected.text.is_empty() and view.prompt.text == "Select another rectangle\nto continue."
			and view.cancel_button.text == "Done" and view.accept_button.text == "Undo"
			and view.accept_button.visible and not view.accept_button.disabled,"mixed native result copy/controls differ"): return
		write_json("mixed-controller-%s.json" % ("done" if finish else "undo"),{
			"observed":observed,"result":view.multi_result.text,"prompt":view.prompt.text,
			"cancel":view.cancel_button.text,"accept":view.accept_button.text})
		if finish:
			view.cancel_button.pressed.emit()
			if not await wait_ui(func(): return settled() and actions._active == 0 and actions._queue.is_empty(),"mixed Done"): return
			if not check(editor.mode == "zone_select","Done did not return to the native zone chooser"): return
			if not check(editor.multi_state.interaction_id == 0 and editor.multi_state.undo_token == 0,"Done retained local mixed authority"): return
			await native("multi_case_check") # Done must retain both native rooms.
			if stopped: return
			await native("multi_case_cleanup")
		else:
			view.accept_button.pressed.emit()
			if not await wait_ui(func(): return settled() and not editor.multi_state.has_result(),"mixed Undo"): return
			await native("multi_case_check",{"removed":true})
			if not check(editor.multi_state.undo_token == 0 and view.cancel_button.text == "Cancel" and not view.accept_button.visible,"Undo did not restore initial native controls"): return
		if stopped: return
	await native("multi_case_restore")

func open_multi() -> bool:
	if editor.panel.visible: editor.close_panel()
	editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"Multi catalog"): return false
	editor.zone_menu.buttons.Bedroom.pressed.emit()
	editor.paint_view.multi_button.pressed.emit()
	return check(editor.mode == "multi" and editor.multi_state.ready(),"Multi did not open")

func select_bed() -> void:
	for corner in 2:
		editor.multi_pointer(Vector3i(172,57,164),true)
		editor.multi_pointer(Vector3i(172,57,164),false)

func reconnect_case() -> void:
	if not await open_multi(): return
	step = "Multi controller owned receipt"
	select_bed()
	if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"first controller creation"): return
	var token: int = editor.multi_state.undo_token
	var scope: int = editor.multi_state.interaction_id
	if not check(token > 0,"controller received no Undo token"): return
	await native("multi_check",{"count":1})
	step = "Multi queued selection at disconnect"
	select_bed() # Queued but deliberately not polled/sent before the boundary.
	var queued: int = editor.request_ticket
	if not check(queued > 0,"missing queued selection"): return
	world.detach_live()
	actions.poll()
	if not check(str(actions.result(queued).get("outcome","")) == "not_sent","queued selection was not retired as unsent"): return
	if not check(editor.multi_state.interaction_id == 0 and editor.multi_state.undo_token == 0 and not editor.available,"controller retained prior session authority"): return
	if not check(world.attach(),"world reattach failed"): return
	if not await wait_ui(func(): return world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)),"controller reconnect"): return
	# The actual action service observes the new generation and resets the
	# management channel. No direct reconnect_management call in this driver.
	await native("multi_check",{"count":1})
	# A replacement channel needs its normal catalog handshake before semantic
	# edits. Reopen through the controller, as a user must after invalidation.
	if not await open_multi(): return
	if not check(editor.multi_state.interaction_id != scope,"reopen reused retired interaction"): return
	var stale: int = actions.submit("areas",{"action":Contract.ManagementAction.AreaUpdate,"kind":1,
		"operation":Contract.AreaOperation.MultiUndo,"interaction_id":scope,"undo_token":token},Callable())
	if not await wait_ui(func(): return not actions.result(stale).is_empty(),"retired token refusal"): return
	var response: Dictionary = actions.result(stale)
	write_json("retired-token-response.json",response)
	if not check(int(response.get("status",-1)) == S.Rejected and int(response.get("area",{}).get("room_outcome",-1)) == Contract.AreaRoomOutcome.Rejected,"expected bridge refusal of retired token: "+str(response)): return
	await native("multi_check",{"count":1})
	await native("multi_cleanup")
	step = "explicit Multi reopen after reconnect"
	if not await open_multi(): return
	if not check(editor.multi_state.interaction_id != scope,"reopen reused retired interaction"): return
	select_bed()
	if not await wait_ui(func(): return settled() and editor.multi_state.has_result(),"reopened creation"): return
	await native("multi_check",{"count":1})
	editor.paint_view.accept_button.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.multi_state.has_result(),"reopened Undo"): return
	await native("multi_check",{"count":0})
	await native("multi_cleanup")

func unobserved_receipt_case() -> void:
	step = "sent Multi receipt unobserved at disconnect"
	if not await open_multi(): return
	select_bed()
	var ticket: int = editor.request_ticket
	actions.poll() # Dispatch exactly once; do not let the service observe a reply.
	if not check(actions._requests.has(ticket) and int(actions._requests[ticket].sequence) > 0,"selection was not sent"): return
	var sequence: int = actions._requests[ticket].sequence
	var receipt: Dictionary = {}
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var value: Dictionary = world.poll_management()
		if int(value.get("request_seq",0)) == sequence and int(value.get("status",0)) == S.Ok:
			receipt = value; break
		await create_timer(0.01).timeout
	if not check(not receipt.is_empty(),"test could not establish native completion before disconnect"): return
	write_json("unobserved-native-receipt.json",receipt)
	if not check(actions.result(ticket).is_empty() and not editor.multi_state.has_result(),"service observed receipt before boundary"): return
	await native("multi_check",{"count":1})
	world.detach_live(); actions.poll()
	var outcome: Dictionary = actions.result(ticket)
	write_json("unobserved-service-outcome.json",outcome)
	if not check(str(outcome.get("outcome","")) == "unknown","sent work was not retired as unknown"): return
	if not check(editor.multi_state.interaction_id == 0 and editor.multi_state.undo_token == 0 and not editor.available,"late receipt restored controller authority"): return
	if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active == 0,"retired request remains dispatchable"): return
	if not check(world.attach(),"reattach after unobserved receipt failed"): return
	if not await wait_ui(func(): return world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)),"unobserved receipt reconnect"): return
	if not await open_multi(): return
	for frame in 4:
		world.poll(); actions.poll(); editor._process(0); await process_frame
	if not check(str(actions.result(ticket).get("outcome","")) == "unknown" and editor.multi_state.undo_token == 0 and not editor.multi_state.has_result(),"old receipt was delivered after reopen"): return
	await native("multi_check",{"count":1})
	await native("multi_cleanup")
