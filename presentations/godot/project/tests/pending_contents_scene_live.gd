extends "res://tests/pending_building_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.basic_building_reference.pending
	scene._ui.focus_tile(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
	owner=scene._ui.controller("pending_building");owner.open_target(int(sample.id))
	if not await pending_ready():return
	var reference:="../stockpile-storage-native-farm-discovery-20261114-235233/"
	await panel_capture("component-initial",reference+"workshop-basic-building-pending")
	for entry in [["forbid",796],["dump",820],["melt",844],["hidden",868]]:
		for attempt in [1,2]:
			await pointer(Vector2(entry[1],526));await drain()
			if not await pending_ready():return
			var rows: Array=owner.contents.rows()
			check(rows.size()==1 and rows[0].id==22339 and rows[0][entry[0]]==bool(attempt==1),"Native component flag differs: "+entry[0])
			check(not rows[0].in_job,"Forbid did not release native component reservation")
			check(owner.state.snapshot.get("forbidden")==rows[0].forbid,"Native building predicate did not refresh the header")
			await panel_capture("component-"+entry[0]+"-"+str(attempt),reference+"workshop-pending-component-"+entry[0]+"-"+str(attempt))
	await key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null and owner.contents.building_id==-1,"Closing component sheet retained authority")
	exercised=true
