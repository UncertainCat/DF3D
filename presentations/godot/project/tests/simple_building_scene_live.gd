extends "res://tests/barrier_scene_live.gd"
func expected_filename() -> String:return "simple-building-expected.json"
func result_filename() -> String:return "simple-building-wire-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		var prefix: String="remaining-building-"+str(int(entry.type))
		await panel_capture(prefix,prefix)
		if not await rename_to(entry.custom_name+"x"):return
		await panel_capture(prefix+"-renamed",prefix+"-renamed")
		if not await rename_to(entry.custom_name):return
		await panel_capture(prefix+"-restored",prefix+"-restored")
		await pointer(Vector2(832,82));if not await chest_ready():return
		check(owner.state.snapshot.removing,"Building removal failed")
		await panel_capture(prefix+"-removing",prefix+"-removing")
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
		if not await chest_ready():return
		check(not owner.state.snapshot.removing,"Building removal not cancelled")
		await panel_capture(prefix+"-cancelled",prefix+"-cancelled")
		key(KEY_ESCAPE);await drain()
		scene._ui.open_building_holder(int(entry.type),int(entry.id))
		if not await chest_ready():return
		check(owner.state.building_id==int(entry.id),"Holder opened wrong building")
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Building retained ownership")
	exercised=true
