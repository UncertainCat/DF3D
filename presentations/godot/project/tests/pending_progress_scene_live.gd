extends "res://tests/pending_building_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.basic_building_reference.pending
	scene._ui.focus_tile(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
	owner=scene._ui.controller("pending_building");owner.open_target(int(sample.id))
	if not await pending_ready():return
	check(owner.state.snapshot.progress==2,"Native initiated progress missing from receipt")
	await panel_capture("progress-initiated","workshop-pending-progress-initiated")
	await key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null and owner.state.building_id==-1,"Progress panel closure retained authority")
	exercised=true
