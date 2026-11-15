extends "res://tests/barrier_scene_live.gd"
func expected_filename() -> String:return "well-scene-expected.json"
func result_filename() -> String:return OS.get_environment("DF3D_DOOR_CAPTURE")+"-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	if not await open_furniture(expected):return
	check(owner.state.snapshot.get("well",{})=={"status":int(expected.status)},"Well native state differs")
	await panel_capture(expected.reference,expected.reference)
	if expected.get("workflow",false):
		if not await rename_to(expected.custom_name+"x"):return
		await panel_capture("well-workflow-renamed","well-workflow-renamed")
		if not await rename_to(expected.custom_name):return
		await panel_capture("well-workflow-restored","well-workflow-restored")
		await pointer(Vector2(832,82));if not await chest_ready():return
		check(owner.state.snapshot.removing,"Well removal failed")
		await panel_capture("well-workflow-removing","well-workflow-removing")
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
		if not await chest_ready():return
		check(not owner.state.snapshot.removing,"Well removal not cancelled")
		await panel_capture("well-workflow-cancelled","well-workflow-cancelled")
	key(KEY_ESCAPE);await drain()
	scene._ui.open_building_holder(18,int(expected.id))
	if not await chest_ready():return
	check(owner.state.building_id==int(expected.id),"Well holder opened wrong target")
	key(KEY_ESCAPE);await drain()
	check(scene._ui.host.active==null,"Well retained panel ownership")
	exercised=true
