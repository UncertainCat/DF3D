extends "res://tests/barrier_scene_live.gd"
func expected_filename() -> String:return "barrier-variant-expected.json"
func result_filename() -> String:return OS.get_environment("DF3D_DOOR_CAPTURE")+"-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		if int(entry.type)==35 and not await access_ready():return
		if int(entry.type) in [36,37]:
			var found:=false
			for row in owner.contents.rows():
				if int(row.item_type)==79:
					found=true
					check(row.appearance.get("grate",{})=={"wall":int(entry.type)==36,"open":entry.grate_open},"Native grate facts differ")
			check(found,"Grate variant lacks installed item")
		await panel_capture(entry.reference,entry.reference)
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Barrier variant retained ownership")
	exercised=true
