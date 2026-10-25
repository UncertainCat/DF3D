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
	await native_filter_lists(pile)
	await header_actions(pile,categories)
	await paint()
	await native("final")

func header_actions(pile: int, categories: Array) -> void:
	for bit in range(categories.size()):
		var category: String = categories[bit]
		step = "native category header " + category
		await edit(pile,0,{"operation":3,"preset":bit+2})
		for shortened in [false,true]:
			if shortened: await native("header_setup",{"id":pile,"category":category})
			for value in [1,2]:
				await native("header_before",{"id":pile,"category":category,"value":value})
				await edit(pile,0,{"operation":2,"scope":3,"value":value,"list_key":category,"query":"ignored"})
				await native("header_after",{"id":pile,"category":category})
				if stopped: return
	step = "native global headers"
	for enabled in [false,true]:
		await native("header_setup",{"id":pile,"category":"","enabled":enabled})
		for value in [2,1]:
			await native("header_before",{"id":pile,"category":"","value":value})
			await edit(pile,0,{"operation":2,"scope":4,"value":value,"list_key":""})
			await native("header_after",{"id":pile,"category":""})
			if stopped: return

func native_filter_lists(pile: int) -> void:
	var category_bits := {"furniture":4,"ammo":64,"bars_blocks":256,"finished_goods":1024,"weapons":16384,"armor":32768,"leather":2048,"cloth":4096}
	for entry in [["furniture/other_materials","furniture.other_mats",25],
		["ammo/other_materials","ammo.other_mats",46],
		["bars_blocks/bars_other","bars_blocks.bars_other_mats",53],
		["bars_blocks/blocks_other","bars_blocks.blocks_other_mats",56],
		["finished_goods/other_materials","finished_goods.other_mats",68],
		["weapons/other_materials","weapons.other_mats",91],
		["armor/other_materials","armor.other_mats",102],
		["finished_goods/color","finished_goods.color",71],["leather/color","leather.color",74],
		["cloth/color","cloth.color",84],["armor/color","armor.color",105],
		["ammo/type","ammo.type",45],["weapons/weapons","weapons.weapon_type",87],
		["weapons/trap_components","weapons.trapcomp_type",88],["armor/body","armor.body",95],
		["armor/head","armor.head",96],["armor/feet","armor.feet",97],
		["armor/hands","armor.hands",98],["armor/legs","armor.legs",99],["armor/shield","armor.shield",100]]:
		var key: String = entry[0]
		var field: String = entry[1]
		var mode: int = entry[2]
		step = "native materials " + key
		var category_bit: int = category_bits[field.get_slice(".",0)]
		await edit(pile,0,{"changed_categories":category_bit,"categories":category_bit})
		for query in ["", "a", "zzzznomatch"]:
			var page := await pages({"action":9,"id":pile,"operation":1,"list_key":key,"query":query},"settings")
			if stopped: return
			await native("filter_rows",{"id":pile,"mode":mode,"list_key":key,"query":query,"rows":page.settings})
			for value in [1,2]:
				await native("filter_before",{"id":pile,"mode":mode,"field":field,"query":query,"value":value})
				await edit(pile,0,{"operation":2,"scope":2,"value":value,"list_key":key,"query":query})
				await native("filter_after",{"id":pile,"mode":mode})
				if stopped: return
		await native("filter_before",{"id":pile,"mode":mode,"field":field,"row":0,"value":1})
		await edit(pile,0,{"operation":2,"scope":1,"value":1,"list_key":key,"row_key":key+"/0"})
		await native("filter_after",{"id":pile,"mode":mode})
		for count in [1,0]:
			await native("filter_setup",{"id":pile,"field":field,"count":count})
			await native("filter_before",{"id":pile,"mode":mode,"field":field,"value":2})
			await edit(pile,0,{"operation":2,"scope":2,"value":2,"list_key":key})
			await native("filter_after",{"id":pile,"mode":mode})
			if stopped: return
