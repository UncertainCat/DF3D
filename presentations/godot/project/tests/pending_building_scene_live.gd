extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "workshop-native.json"
func result_filename() -> String:return "workshop-wire-result.json"
func pending_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready:return true
		await create_timer(0.01).timeout
	return check(false,"Pending sheet did not obtain controls and contents")
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.basic_building_reference.pending
	scene._ui.focus_tile(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
	owner=scene._ui.controller("pending_building");owner.open_target(int(sample.id))
	if not await pending_ready():return
	check(scene._ui.host.active==owner,"Pending sheet did not own input")
	# Independent native221104 covers the same controlled stage1 farm. The
	# screenshot handshake can capture a native map redraw over the panel.
	var reference:="../stockpile-storage-native-farm-discovery-20261114-221104/" if int(sample.stage)>0 else ""
	await panel_capture("pending-initial",reference+"workshop-basic-building-pending")
	for suspended in [false,true]:
		await pointer(Vector2(520,202))
		if not await pending_ready():return
		check(owner.state.snapshot.suspended==suspended,"Pending pointer suspension differs")
		await panel_capture("pending-suspended-"+str(suspended),reference+"workshop-basic-building-pending-"+str(2 if suspended else 1))
	await pointer(Vector2(520,238));await drain();await process_frame
	if int(sample.stage)>0:
		if not await pending_ready():return
		check(owner.state.snapshot.removing and scene._ui.host.active==owner,"Removal handoff lost target or input ownership")
		await panel_capture("pending-removing",reference+"workshop-basic-building-pending-cancel")
		await pointer(Vector2(520,202))
		if not await pending_ready():return
		check(not owner.state.snapshot.removing and owner.state.snapshot.job_id==-1 and owner.state.snapshot.stage==int(sample.stage),"Cancel removal did not restore native idle state")
		await panel_capture("pending-idle",reference+"workshop-pending-removal-cancelled")
		var revision: int=owner.state.snapshot.revision
		await pointer(Vector2(520,202));await drain()
		check(owner.state.phase==owner.state.Phase.Ready and owner.state.ticket==0 and owner.state.snapshot.revision==revision,"Idle Suspend changed authority")
		await key(KEY_ESCAPE);await process_frame
		check(scene._ui.host.active==null,"Idle Escape retained panel ownership")
		owner.open_target(int(sample.id))
		if not await pending_ready():return
		check(owner.state.snapshot.job_id==-1,"Reopening idle target invented a job")
		await pointer(Vector2(520,238));await drain()
		if not await pending_ready():return
		check(owner.state.snapshot.removing,"Repeated removal did not reopen removal view")
		await key(KEY_ESCAPE);await process_frame
	check(owner.state.building_id==-1 and owner.contents.building_id==-1 and scene._ui.host.active==null,"Pending closure retained panel authority")
	exercised=true
