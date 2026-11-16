extends "res://tests/barrier_scene_live.gd"
func expected_filename() -> String:return "special-building-expected.json"
func result_filename() -> String:return "special-building-wire-result.json"
func local_click(point: Vector2) -> bool:
	await pointer(owner.panel.get_global_transform_with_canvas()*point)
	return await chest_ready()
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		var kind:=int(entry.type)
		var prefix: String="remaining-building-"+str(kind)
		await panel_capture(prefix,prefix)
		if kind==24:
			for index in 4:
				if not await local_click(owner.panel.bait_rect(index).get_center()):return
				check(owner.state.snapshot.trap.bait_type==[48,49,44,-1][index],"Bait pointer edit differs")
				var reference: String="special-building-24-bait-"+str(index+1)
				await panel_capture(reference,reference)
		elif kind==49:
			for sample in [[true,1,"install"],[false,3,"gather"],[true,2,"no-install"],[false,0,"restored"]]:
				if not await local_click(owner.panel.hive_rect(sample[0]).get_center()):return
				check(owner.state.snapshot.hive.flags==sample[1],"Hive pointer edit differs")
				var reference: String="special-building-49-"+sample[2]
				await panel_capture(reference,reference)
		if not await rename_to(entry.custom_name+"x"):return
		await panel_capture(prefix+"-renamed",prefix+"-renamed")
		if not await rename_to(entry.custom_name):return
		await panel_capture(prefix+"-restored",prefix+"-restored")
		if not await local_click(Vector2(416,30)):return
		check(owner.state.snapshot.removing,"Special building removal failed")
		await panel_capture(prefix+"-removing",prefix+"-removing")
		if not await local_click(owner.panel.cancel_rect().get_center()):return
		check(not owner.state.snapshot.removing,"Special building cancellation failed")
		await panel_capture(prefix+"-cancelled",prefix+"-cancelled")
		key(KEY_ESCAPE);await drain()
		scene._ui.open_building_holder(kind,int(entry.id))
		if not await chest_ready():return
		check(owner.state.building_id==int(entry.id),"Special holder route changed target")
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Special building retained input ownership")
	exercised=true
