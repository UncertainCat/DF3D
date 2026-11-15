extends "res://tests/furniture_scene_live.gd"
func expected_filename() -> String:return "barrier-wire-expected.json"
func result_filename() -> String:return "barrier-scene-result.json"
func access_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.access.phase==owner.access.Phase.Ready:return true
		await create_timer(0.01).timeout
	return check(false,"Hatch access controls not Ready")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		if int(entry.type)==35 and not await access_ready():return
		await panel_capture("barrier-"+str(int(entry.type)),"barrier-sheet-"+str(int(entry.type)))
		if int(entry.type)==35:
			for forbidden in [true,false]:
				await pointer(Vector2(852 if forbidden else 876,154))
				if not await access_ready():return
				check(owner.access.snapshot.forbidden==forbidden,"Hatch pointer did not change access")
				var label: String="barrier-hatch-forbidden" if forbidden else "barrier-hatch-passable"
				await panel_capture(label,label)
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Barrier retained ownership")
	exercised=true
