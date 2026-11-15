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
	await pointer(owner.panel.contents.get_global_transform_with_canvas()*owner.panel.contents.control_rect(0,1).get_center())
	if not await settle(owner.item_owner.state):return
	check(scene._ui.host.active==owner.item_owner and owner.item_owner.state.item_id==22339,"Component View did not open its item")
	await panel_capture("component-item","../stockpile-storage-native-farm-discovery-20261115-002303/workshop-pending-component-view")
	await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*owner.item_owner.panel.holder_rect().get_center())
	if not await pending_ready():return
	check(scene._ui.host.active==owner and owner.state.building_id==int(sample.id) and not owner.item_owner.panel.visible,"Component holder did not return to unfinished building")
	await panel_capture("component-return",reference+"workshop-pending-component-hidden-2")
	await key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null and owner.contents.building_id==-1,"Closing component sheet retained authority")
	exercised=true
