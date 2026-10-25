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
	var categories := ["animals","food","furniture","corpses","refuse","stone","ammo","coins",
		"bars_blocks","gems","finished_goods","leather","cloth","wood","weapons","armor","sheet"]
	var pile := int(fixture.pile)
	for bit in range(categories.size()):
		step = "activate " + categories[bit]
		await edit(pile,0,{"operation":3,"preset":bit+2})
		await edit(pile,0,{"changed_categories":1 << bit,"categories":0})
		for repeat_selection in range(2):
			await native("category_before",{"id":pile,"category":categories[bit]})
			await edit(pile,0,{"changed_categories":1 << bit,"categories":1 << bit})
			await native("category_after",{"id":pile,"category":categories[bit]})
			if stopped: return
	for entry in [["furniture",26],["ammo",48],["finished_goods",69],["weapons",92],["armor",103]]:
		for quality in range(2):
			var key: String = entry[0] + ("/quality_core" if quality == 0 else "/quality_total")
			var mode: int = entry[1] + quality
			step = "native quality " + key
			for query in ["", "CRAFTED", "zzzznomatch"]:
				var page := await pages({"action":9,"id":pile,"operation":1,"list_key":key,"query":query},"settings")
				if stopped: return
				await native("quality_rows",{"id":pile,"mode":mode,"list_key":key,"query":query,"rows":page.settings})
			for value in [1,2]:
				await native("quality_before",{"id":pile,"mode":mode,"query":"CRAFTED","value":value})
				await edit(pile,0,{"operation":2,"scope":2,"value":value,"list_key":key,"query":"CRAFTED"})
				await native("quality_after",{"id":pile,"mode":mode})
				if stopped: return
	await paint()
	await native("final")
