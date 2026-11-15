extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "depot-wire-expected.json"
func result_filename() -> String:return "depot-scene-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	# Staged owner only; public map routes remain hidden until goods/trade are ready.
	owner.open_target(int(expected.id))
	if not await chest_ready():return
	if expected.has("reference"):
		check(owner.state.snapshot.depot.broker_id==int(expected.broker_id),"Depot broker identity differs")
		await panel_capture("depot-broker",expected.reference)
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Depot retained broker panel ownership")
		exercised=true
		return
	await panel_capture("depot-idle","depot-settings-idle")
	for step in [[0,"broker"],[1,"anyone"],[0,"broker-again"],[2,"dismissed"],[1,"anyone-fresh"],[2,"dismissed-anyone"],[0,"broker"],[2,"idle"]]:
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.mode_rect(step[0]).get_center())
		if not await chest_ready():return
		check(owner.state.snapshot.depot.requested==(step[0]!=2),"Depot request pointer failed")
		await panel_capture("depot-"+step[1],"depot-settings-"+step[1])
	key(KEY_ESCAPE);await drain()
	check(scene._ui.host.active==null,"Depot retained ownership")
	exercised=true
