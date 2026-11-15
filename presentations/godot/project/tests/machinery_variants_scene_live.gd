extends "res://tests/furniture_scene_live.gd"
func expected_filename() -> String:return "machinery-variant-expected.json"
func result_filename() -> String:return OS.get_environment("DF3D_DOOR_CAPTURE")+"-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		var semantic: Dictionary=entry.semantic.duplicate(true)
		for field in ["machine_id","produced","required","status","pump_manual","pump_direction"]:semantic[field]=int(semantic[field])
		check(owner.state.snapshot.machinery==semantic,"Variant semantic facts differ")
		await panel_capture(entry.reference,entry.reference)
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Variant retained ownership")
	exercised=true
