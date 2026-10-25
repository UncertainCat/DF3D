extends "res://tests/areas_acceptance_live.gd"

# Focused native initialization acceptance; the parent supplies one-shot requests.
func exercise() -> void:
	await seed_catalog()
	if stopped: return
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	if not check(fixture.has("origin"), "missing free stockpile footprint"): return
	var p: Dictionary = fixture.origin
	var masks: Array[int] = [0]
	for bit in range(17): masks.append(1 << bit)
	masks.append(131071)
	masks.append(8194) # Food and Wood together.
	for mask in masks:
		step = "initialize categories %d" % mask
		var reply := await request({"action":10, "operation":0,
			"origin":Vector3i(int(p.x),int(p.y),int(p.z)), "width":2, "height":1,
			"categories":mask})
		if stopped: return
		if not check(reply.areas.size() == 1, "new stockpile absent"): return
		var a: Dictionary = reply.areas[0]
		if not check(int(a.categories) == mask, "published category mask differs"): return
		await native("stockpile_initialization", {"id":int(a.id), "categories":mask})
		await request({"action":12, "id":int(a.id), "expected_revision":a.revision})
		await native("removed", {"id":int(a.id)})
		if stopped: return
	await settings_and_presets()
	await paint()
	await native("final")
