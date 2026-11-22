extends "res://tests/furniture_map_scene_live.gd"
func expected_filename() -> String:return "siege-building-expected.json"
func result_filename() -> String:return "siege-building-wire-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		var kind:=int(entry.body.type)
		var prefix: String="siege-"+str(kind)
		await panel_capture(prefix+"-initial",prefix+"-initial")
		for slot in 5:
			var mode: int=[3,4,2,1,0][slot]
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.siege_mode_rect(slot).get_center())
			if not await chest_ready():return
			check(owner.state.snapshot.siege.action==mode,"Siege pointer mode failed")
			var reference: String=prefix+"-practice-reopened" if mode==4 and kind!=2 else prefix+"-action-"+str(mode)
			await panel_capture(prefix+"-mode-"+str(mode),reference)
		if kind==2:
			for direction in [7,0]:
				await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.siege_resting_rect(direction).get_center())
				if not await chest_ready():return
				check(owner.state.snapshot.siege.resting==direction and owner.state.snapshot.siege.facing==int(entry.body.facing),"Siege resting edit changed facing")
				await panel_capture("siege-resting-"+str(direction),"siege-resting-"+str(direction))
		if not await rename_to(entry.custom_name+"x"):return
		await panel_capture(prefix+"-renamed",prefix+"-renamed")
		if not await rename_to(entry.custom_name):return
		await panel_capture(prefix+"-restored",prefix+"-restored")
		await pointer(Vector2(832,82));if not await chest_ready():return
		check(owner.state.snapshot.removing,"Siege removal not queued")
		await panel_capture(prefix+"-removing",prefix+"-removing")
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
		if not await chest_ready():return
		await panel_capture(prefix+"-cancelled",prefix+"-cancelled")
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Siege retained ownership after close")
		scene._ui.open_building_holder(22,int(entry.id))
		if not await chest_ready():return
		check(owner.state.building_id==int(entry.id),"Siege holder opened wrong target")
		key(KEY_ESCAPE);await drain()
	exercised=true
