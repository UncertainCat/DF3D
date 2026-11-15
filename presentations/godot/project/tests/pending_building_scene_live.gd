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
	await panel_capture("pending-initial","workshop-basic-building-pending")
	for suspended in [false,true]:
		await pointer(Vector2(520,202))
		if not await pending_ready():return
		check(owner.state.snapshot.suspended==suspended,"Pending pointer suspension differs")
		await panel_capture("pending-suspended-"+str(suspended),"workshop-basic-building-pending-"+str(2 if suspended else 1))
	await pointer(Vector2(520,238));await drain();await process_frame
	check(owner.state.building_id==-1 and owner.contents.building_id==-1 and scene._ui.host.active==null,"Pending cancel retained panel authority")
	exercised=true
