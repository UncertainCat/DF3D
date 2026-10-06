extends "res://tests/areas_acceptance_live.gd"
const Op = Contract.AreaOperation
const Outcome = Contract.AreaRoomOutcome

func multi(data: Dictionary, expected := Outcome.Completed) -> Dictionary:
	if stopped: return {}
	world.poll()
	var seq: int = world.area_request(data)
	if not check(seq > 0,"Multi request not sent: " + world.last_error()): return {}
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var value: Dictionary = world.poll_management()
		if int(value.get("request_seq",0)) == seq and int(value.get("status",S.Idle)) in [S.Ok,S.Rejected]:
			print("MULTI_RECEIPT ",step," ",value)
			var page: Dictionary = value.get("area",{})
			check(int(page.get("operation",-1)) == int(data.operation) and int(page.get("interaction_id",0)) == int(data.interaction_id),"wrong scoped reply")
			check(int(page.get("room_outcome",-1)) == expected,"unexpected room outcome")
			check(int(value.status) == (S.Ok if expected == Outcome.Completed else S.Rejected),"envelope outcome disagrees")
			return page
		await create_timer(0.01).timeout
	incomplete("Multi outcome unknown; no replay",true)
	return {}

func create_room(interaction: int, empty := false) -> Dictionary:
	return await multi({"action":Contract.ManagementAction.AreaCreate,"kind":1,"operation":Op.MultiCreate,
		"interaction_id":interaction,"room_furniture":1,"origin":Vector3i(0,0,164) if empty else Vector3i(172,57,164),"width":1,"height":1})

func undo_room(interaction: int, token: int, expected := Outcome.Completed) -> Dictionary:
	return await multi({"action":Contract.ManagementAction.AreaUpdate,"kind":1,"operation":Op.MultiUndo,"interaction_id":interaction,"undo_token":token},expected)

func exercise() -> void:
	await seed_catalog()
	if stopped: return
	step = "Multi native baseline"; await native("multi_begin")
	for scenario in ["undo","empty","in_use","stale","done","foreign_scope"]:
		if stopped: return
		step = scenario
		var page := await create_room(101)
		if stopped: return
		if not check(int(page.get("rooms_created",0)) == 1 and int(page.get("rooms_dormitories",-1)) == 0 and int(page.get("undo_token",0)) > 0,"one Bedroom and scoped receipt required"): return
		var token := int(page.undo_token)
		await native("multi_check",{"count":1})
		if stopped: return
		if scenario == "undo" or scenario == "foreign_scope":
			if scenario == "foreign_scope": await undo_room(102,token,Outcome.Rejected)
			var removed := await undo_room(101,token)
			if stopped: return
			check(int(removed.get("rooms_removed",0)) == 1,"Undo removed count")
			await native("multi_check",{"count":0})
			await undo_room(101,token,Outcome.Rejected)
		elif scenario == "empty" or scenario == "in_use":
			var replacement := await create_room(101,scenario == "empty")
			if stopped: return
			check(int(replacement.get("rooms_created",-1)) == 0 and int(replacement.get("undo_token",-1)) == 0,"empty/rejected set must replace receipt")
			check(int(replacement.get("rooms_in_use",-1)) == (1 if scenario == "in_use" else 0),"native in-use count")
			await undo_room(101,token,Outcome.Rejected)
			await native("multi_check",{"count":1})
		elif scenario == "stale":
			await native("multi_stale")
			await undo_room(101,token,Outcome.Stale)
			await native("multi_check",{"count":1})
		else:
			await multi({"action":Contract.ManagementAction.AreaUpdate,"kind":1,"operation":Op.MultiFinish,"interaction_id":101})
			await undo_room(101,token,Outcome.Rejected)
			await native("multi_check",{"count":1})
		await native("multi_cleanup")
	var references: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory+"/multi-reference.json"))
	for reference in references.cases:
		var case_name := str(reference.name)
		if stopped: return
		step = case_name
		var prepared := await native("multi_case_prepare", {"case":case_name})
		if stopped: return
		var selection: Dictionary = prepared.selection
		var intent := {"action":Contract.ManagementAction.AreaCreate,"kind":1,"operation":Op.MultiCreate,
			"interaction_id":201,"room_furniture":int(selection.furniture),
			"origin":Vector3i(int(selection.x),int(selection.y),int(selection.z)),"width":int(selection.width),"height":1}
		var page := await multi(intent)
		if stopped: return
		if not check(int(page.rooms_created) == int(prepared.count) and int(page.rooms_dormitories) == int(prepared.dormitories)
			and int(page.rooms_in_use) == int(prepared.in_use) and int(page.rooms_unenclosed) == int(prepared.unenclosed),"native reference result counts differ"): return
		await native("multi_case_check")
		if stopped: return
		if int(prepared.count) > 0:
			if not check(int(page.undo_token) > 0,"created set has no Undo authority"): return
			var removed := await undo_room(201,int(page.undo_token))
			if stopped: return
			if not check(int(removed.rooms_removed) == int(prepared.count),"whole-set Undo count differs"): return
		else:
			if not check(int(page.undo_token) == 0,"empty result retained Undo authority"): return
		await native("multi_case_check", {"removed":true})
		if case_name == "beds-split-both-unused":
			# A new explicit selection after successful Undo, never a retry.
			step = "second-room stale refusal"
			var second := await multi(intent)
			if stopped: return
			await native("multi_case_check")
			await native("multi_case_stale")
			var refused := await undo_room(201,int(second.undo_token),Outcome.Stale)
			if stopped: return
			if not check(int(refused.rooms_removed) == 0,"stale second room allowed partial Undo"): return
			await native("multi_case_check")
			await native("multi_case_cleanup")
		await native("multi_case_restore")
	await client_ownership()
	step = "Multi final"; await native("multi_final")

func ready_client() -> bool:
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var state: Dictionary = world.poll_management()
		if world.terrain_loaded() and bool(state.get("transport_alive",false)) and int(state.get("world_epoch",0)) > 0:
			await seed_catalog()
			return not stopped
		await create_timer(0.01).timeout
	incomplete("new client did not become ready; no command replay",true)
	return false

func client_ownership() -> void:
	if stopped: return
	step = "foreign client Undo and Finish"
	var owned := await create_room(301)
	if stopped: return
	if not check(int(owned.undo_token) > 0,"owner has no Undo receipt"): return
	await native("multi_check",{"count":1})
	var owner = world
	var peer = Df3dWorld.new(); root.add_child(peer)
	world = peer
	if check(peer.attach(),"foreign client attach failed") and await ready_client():
		await undo_room(301,int(owned.undo_token),Outcome.Rejected)
		await multi({"action":Contract.ManagementAction.AreaUpdate,"kind":1,"operation":Op.MultiFinish,"interaction_id":301})
		await native("multi_check",{"count":1})
	world = owner
	peer.detach_live(); peer.queue_free(); await process_frame
	if stopped: return
	var removed := await undo_room(301,int(owned.undo_token))
	if stopped: return
	if not check(int(removed.rooms_removed) == 1,"foreign request discarded owner's receipt"): return
	await native("multi_check",{"count":0})
	await native("multi_cleanup")
	step = "reconnected client cannot reclaim old Undo"
	owned = await create_room(302)
	if stopped: return
	await native("multi_check",{"count":1})
	world.detach_live()
	if not check(not world.is_attached(),"client did not detach"): return
	# World-stream and semantic transports have separate owners. The action
	# service resets this channel when it observes a session-generation change.
	world.reconnect_management()
	if not check(world.attach(),"client reattach failed"): return
	if not await ready_client(): return
	await undo_room(302,int(owned.undo_token),Outcome.Rejected)
	await native("multi_check",{"count":1})
	await native("multi_cleanup")
