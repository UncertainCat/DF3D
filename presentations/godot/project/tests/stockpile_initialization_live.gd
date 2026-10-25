extends "res://tests/areas_acceptance_live.gd"

# Native initialization acceptance; an explicit filter-scope file selects a
# focused command run and records exactly which native lists were exercised.
var filter_modes: Array = []
func exercise() -> void:
	await seed_catalog()
	if stopped: return
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory + "/fixture.json"))
	if not check(fixture.has("origin"), "missing free stockpile footprint"): return
	if FileAccess.file_exists(directory + "/filter-scope.json"):
		var scope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/filter-scope.json"))
		if scope.get("summary_only",false):
			await focused_summaries()
			return
		for mode in scope.filter_modes: filter_modes.append(int(mode))
		await focused_filters()
		return
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

func focused_filters() -> void:
	var p: Dictionary = fixture.origin
	var reply := await request({"action":10,"operation":0,
		"origin":Vector3i(int(p.x),int(p.y),int(p.z)),"width":2,"height":1,"categories":131071})
	if stopped: return
	if not check(reply.areas.size() == 1,"focused pile absent"): return
	var pile: int = reply.areas[0].id
	await native("stockpile_initialization",{"id":pile,"categories":131071})
	await native_filter_lists(pile)
	if stopped: return
	var current := await request({"action":9,"id":pile})
	if stopped: return
	await request({"action":12,"id":pile,"expected_revision":current.areas[0].revision})
	await native("removed",{"id":pile})
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
	var exercised: Array = []
	var category_bits := {"food":2,"sheet":65536,"furniture":4,"ammo":64,"bars_blocks":256,"finished_goods":1024,"weapons":16384,"armor":32768,"leather":2048,"cloth":4096,"animals":1,"corpses":8,"refuse":16,"wood":8192,"coins":128,"gems":512,"stone":32}
	for entry in [["food/meat","food.meat",2],
		["food/fish","food.fish",3],
		["food/unprepared_fish","food.unprepared_fish",4],
		["food/egg","food.egg",5],
		["food/plants","food.plants",6],
		["food/drink_plant","food.drink_plant",7],
		["food/drink_animal","food.drink_animal",8],
		["food/cheese_plant","food.cheese_plant",9],
		["food/cheese_animal","food.cheese_animal",10],
		["food/seeds","food.seeds",11],
		["food/leaves","food.leaves",12],
		["food/powder_plant","food.powder_plant",13],
		["food/powder_creature","food.powder_creature",14],
		["food/glob","food.glob",15],
		["food/glob_paste","food.glob_paste",16],
		["food/glob_pressed","food.glob_pressed",17],
		["food/liquid_plant","food.liquid_plant",18],
		["food/liquid_animal","food.liquid_animal",19],
		["food/liquid_misc","food.liquid_misc",20],
		["leather/type","leather.mats",73],
		["cloth/thread_silk","cloth.thread_silk",76],
		["cloth/thread_plant","cloth.thread_plant",77],
		["cloth/thread_yarn","cloth.thread_yarn",78],
		["cloth/thread_metal","cloth.thread_metal",79],
		["cloth/cloth_silk","cloth.cloth_silk",80],
		["cloth/cloth_plant","cloth.cloth_plant",81],
		["cloth/cloth_yarn","cloth.cloth_yarn",82],
		["cloth/cloth_metal","cloth.cloth_metal",83],
		["sheet/paper","sheet.paper",107],
		["sheet/parchment","sheet.parchment",108],
		["stone/metal_ores","stone.mats",40],["stone/economic","stone.mats",41],
		["stone/other_stone","stone.mats",42],["stone/clay","stone.mats",43],
		["gems/rough_glass","gems.rough_other_mats",58],["gems/cut_glass","gems.cut_other_mats",59],
		["gems/rough_gem","gems.rough_mats",60],["gems/cut_gem","gems.cut_mats",61],["gems/cut_stone","gems.cut_mats",62],
		["furniture/stone","furniture.mats",23],["furniture/metal","furniture.mats",24],
		["ammo/metal","ammo.mats",47],["coins","coins.mats",50],
		["bars_blocks/bars_metal","bars_blocks.bars_mats",52],["bars_blocks/blocks_stone","bars_blocks.blocks_mats",54],
		["bars_blocks/blocks_metal","bars_blocks.blocks_mats",55],["finished_goods/stone","finished_goods.mats",65],
		["finished_goods/metal","finished_goods.mats",66],["finished_goods/gem","finished_goods.mats",67],
		["weapons/metal","weapons.mats",89],["weapons/stone","weapons.mats",90],["armor/metal","armor.mats",101],
		["furniture/type","furniture.type",22],["refuse/type","refuse.type",30],["finished_goods/type","finished_goods.type",64],["wood","wood.mats",85],["furniture/other_materials","furniture.other_mats",25],
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
		["armor/hands","armor.hands",98],["armor/legs","armor.legs",99],["armor/shield","armor.shield",100],
		["animals/animals","animals.enabled",0],["corpses","corpses.corpses",28],
		["refuse/corpses","refuse.corpses",31],["refuse/body_parts","refuse.body_parts",32],
		["refuse/skulls","refuse.skulls",33],["refuse/bones","refuse.bones",34],
		["refuse/shells","refuse.shells",35],["refuse/teeth","refuse.teeth",36],
		["refuse/horns","refuse.horns",37],["refuse/hair","refuse.hair",38]]:
		var key: String = entry[0]
		var field: String = entry[1]
		var mode: int = entry[2]
		if not filter_modes.is_empty() and not mode in filter_modes: continue
		var first_row := -1
		exercised.append(mode)
		step = "native materials " + key
		var category_bit: int = category_bits[field.get_slice(".",0)]
		await edit(pile,0,{"changed_categories":category_bit,"categories":category_bit})
		for query in ["", "a", "zzzznomatch"]:
			var page := await pages({"action":9,"id":pile,"operation":1,"list_key":key,"query":query},"settings")
			if stopped: return
			if query.is_empty() and not page.settings.is_empty(): first_row = int(page.settings[0].index)
			if not check(int(page.get("settings_count",-1)) == page.settings.size(),"filtered count must equal the complete native visible list"): return
			await native("filter_rows",{"id":pile,"mode":mode,"list_key":key,"query":query,"rows":page.settings})
			var parent_modes := {2:1,22:21,30:29,40:39,45:44,52:51,60:57,64:63,73:72,76:75,87:86,95:94,107:106}
			if parent_modes.has(mode):
				await native("guard_before")
				var parent_page := await pages({"action":9,"id":pile,"operation":1,"list_key":key,"query":query,"category_opening":true},"settings")
				if stopped: return
				if not check(int(parent_page.get("settings_count",-1)) == parent_page.settings.size(),"parent filtered count must equal the complete native visible list"): return
				await native("guard_after")
				await native("filter_rows",{"id":pile,"mode":parent_modes[mode],"list_key":key,"query":query,"rows":parent_page.settings})
				if not check(parent_page.list_revision != page.list_revision,"opening context must change receipt even for an empty search result"): return
				await refusal({"action":9,"id":pile,"operation":1,"list_key":key,"query":query,"category_opening":true,"cursor":128,"expected_list_revision":page.list_revision},"List changed; refresh")

			for value in [1,2]:
				await native("filter_before",{"id":pile,"mode":mode,"field":field,"query":query,"value":value})
				await edit(pile,0,{"operation":2,"scope":2,"value":value,"list_key":key,"query":query})
				await native("filter_after",{"id":pile,"mode":mode})
				if stopped: return
		if mode in [9,14]:
			if not check(first_row == -1,"expected empty native organic category"): return
		else:
			if not check(first_row >= 0,"fixture has no eligible rows for " + key): return
			await native("filter_before",{"id":pile,"mode":mode,"field":field,"row":first_row,"value":1})
			await edit(pile,0,{"operation":2,"scope":1,"value":1,"list_key":key,"row_key":key+"/"+str(first_row)})
			await native("filter_after",{"id":pile,"mode":mode})
		if mode == 30:
			for scalar in ["fresh_raw_hide","rotten_raw_hide"]:
				await native("filter_before",{"id":pile,"mode":mode,"field":"refuse."+scalar,"row":0,"value":1})
				await edit(pile,0,{"operation":2,"scope":1,"value":1,"list_key":key,"row_key":key+"/"+scalar})
				await native("filter_after",{"id":pile,"mode":mode})
		for count in [1,0]:
			await native("filter_setup",{"id":pile,"field":field,"count":count})
			await native("filter_before",{"id":pile,"mode":mode,"field":field,"value":2})
			await edit(pile,0,{"operation":2,"scope":2,"value":2,"list_key":key})
			await native("filter_after",{"id":pile,"mode":mode})
			if stopped: return

		await native("filter_restore",{"id":pile,"field":field})

	if not filter_modes.is_empty():
		for mode in filter_modes:
			if not check(mode in exercised,"requested native mode was not exercised"): return

func summary_read(pile: int,key: String = "") -> Dictionary:
	await native("summary_before",{"id":pile})
	var page := await pages({"action":9,"id":pile,"operation":1,"list_key":key},"settings")
	if stopped: return {}
	await native("summary_rows",{"id":pile,"list_key":key,"rows":page.settings})
	return page

func focused_summaries() -> void:
	var p: Dictionary = fixture.origin
	var created := await request({"action":10,"operation":0,
		"origin":Vector3i(int(p.x),int(p.y),int(p.z)),"width":2,"height":1,"categories":0})
	if stopped: return
	var pile: int = created.areas[0].id
	await native("stockpile_initialization",{"id":pile,"categories":0})
	step = "empty native summaries"
	await summary_read(pile)
	var categories := ["animals","food","furniture","corpses","refuse","stone","ammo","coins",
		"bars_blocks","gems","finished_goods","leather","cloth","wood","weapons","armor","sheet"]
	for bit in range(categories.size()):
		step = "activate summary " + categories[bit]
		await edit(pile,0,{"changed_categories":1 << bit,"categories":1 << bit})
		await summary_read(pile)
		if not categories[bit] in ["corpses","coins","wood"]: await summary_read(pile,categories[bit])
		if stopped: return
	for value in [2,1,2]:
		step = "native summary header " + str(value)
		await edit(pile,0,{"operation":2,"scope":4,"value":value})
		await summary_read(pile)
		for category in categories:
			if not category in ["corpses","coins","wood"]: await summary_read(pile,category)
			if stopped: return
	var observed := await summary_read(pile)
	await edit(pile,0,{"operation":2,"scope":2,"value":1,"list_key":"wood"})
	await request({"action":9,"id":pile,"operation":1,"expected_list_revision":observed.list_revision},"List changed; refresh")
	await summary_read(pile)
	var current := await request({"action":9,"id":pile})
	if stopped: return
	await request({"action":12,"id":pile,"expected_revision":current.areas[0].revision})
	await native("removed",{"id":pile})
	await native("final")
