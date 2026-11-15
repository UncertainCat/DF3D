extends "res://tests/furniture_scene_live.gd"
func expected_filename() -> String:return "machinery-wire-expected.json"
func result_filename() -> String:return "machinery-scene-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if int(entry.type)==13:continue
		if not await open_furniture(entry):return
		await panel_capture("machinery-"+str(int(entry.type)),"machinery-sheet-"+str(int(entry.type)))
		if int(entry.type)==33:
			for step in [1,2]:
				await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.pump_rect().get_center())
				if not await chest_ready():return
				check(owner.state.snapshot.machinery.pump_manual==(1 if step==1 else 0),"Pump gesture did not change native flag")
				await panel_capture("machinery-pump-"+str(step),"machinery-pump-manual-"+str(step))
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Machinery retained panel ownership")
	exercised=true
