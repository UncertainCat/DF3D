extends "res://tests/construction_acceptance_live.gd"
# Real controller + shared action service against owned DF. Native verification
# is readback only. This headless lane does not claim mouse/GPU acceptance.
var editor
var actions
var host
var interaction
var last_receipt: Dictionary = {}

func wait_for(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+120000
	while not stopped and Time.get_ticks_msec() < deadline and lane_budget_ok():
		world.poll(); actions.poll(); editor._process(0.02)
		if predicate.call(): return true
		await create_timer(0.02).timeout
	return check(false,label+" timed out; no command replay")

func exercise() -> void:
	step = "controller setup"
	if not check(world.load_assets(FileAccess.get_file_as_string(directory+"/df-path.txt")),"installed assets unavailable"): return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	if not check(fixture.get("sites",{}).has("wall"),"wall fixture unavailable"): return
	var origin := point(fixture.sites.wall)
	world.set_top_z(origin.z)
	setup_controller()
	editor.open_panel()
	if not await wait_for(func(): return not editor.catalog.is_empty() and editor.request_ticket == 0,"catalog"): return
	await observe_stage("catalog")
	if not check(editor.menu.catalog.has("Construction:Wall"),"paged catalog did not enable Wall"): return
	await exercise_controller(fixture,origin)

func setup_controller() -> void:
	interaction = preload("res://tests/construction_test.gd").FakeInteraction.new(); root.add_child(interaction)
	host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	actions = preload("res://scripts/semantic_action_service.gd").new(); actions.configure(world); root.add_child(actions); actions.set_process(false)
	actions.completed.connect(func(ticket,result):
		last_receipt = result.duplicate(true)
		print("CONTROLLER_RECEIPT ticket=",ticket," action=",result.get("action",-1)," status=",result.get("status",-1)," valid=",result.get("placement_valid",false)," message=",result.get("message","")))
	editor = preload("res://scripts/construction.gd").new()
	editor.world = world; editor.interaction = interaction; editor.ui_host = host; editor.action_service = actions
	editor.camera = Camera3D.new(); root.add_child(editor.camera); root.add_child(editor); host.register(editor); editor.set_process(false)

func observe_stage(_label: String) -> void:
	pass

func exercise_controller(fixture: Dictionary, origin: Vector3i) -> void:
	step = "cancel placement gesture"
	await native("guard_before")
	editor.choose_definition("Construction:Wall"); editor.target_tile(origin,true); editor.handle_back()
	if not check(editor.draft.origin.z < 0,"cancel retained draft"): return
	await native("guard_after")
	for iteration in 2:
		step = "controller wall %d" % iteration
		editor.choose_definition("Construction:Wall"); editor.keep_building.button_pressed = true
		if iteration == 1: editor.set_material_strategy("last")
		editor.target_tile(origin,true); editor.target_tile(origin,true)
		if iteration == 0:
			if not await wait_for(func(): return editor.mode == "materials" and editor.request_ticket == 0 and editor.pending_read.is_empty(),"materials"): return
			await observe_stage("wall_materials")
			var filter_index := int(editor.draft.filters[0].index)
			var snapshot: Dictionary = editor.draft.snapshots[filter_index]
			if not check(not snapshot.rows.is_empty(),"no eligible wall materials"): return
			editor.select_material(filter_index,0,1)
		if not await wait_for(func(): return editor.request_ticket == 0 and editor.mode == "place" and not editor.placed_sites.is_empty(),"Place"): return
		if not check(int(last_receipt.get("status",-1)) == S.Ok and not editor.last_material.is_empty(),"Place did not confirm material preference"): return
		var verified := await native("placed",{"definition":"Construction:Wall","origin":native_point(origin),"width":1,"height":1,"depth":1,"direction":0,"retracting":false,"mode":3,"mask":[1],"placed":1,"skipped":0})
		if stopped: return
		var ids := building_ids(verified)
		if not check(ids.size() == 1 and editor.placed_sites.has(ids[0]),"controller/native building identities differ"): return
		editor.begin_inspect(); editor.send({"action":5,"origin":origin})
		if not await wait_for(func(): return editor.request_ticket == 0 and editor.inspected_id == ids[0],"InspectAtTile"): return
		editor.remove_button.pressed.emit()
		if not await wait_for(func(): return editor.request_ticket == 0 and not editor.placed_sites.has(ids[0]),"Remove"): return
		await native("removed",{"id":ids[0]})
		await native("site_clear",{"origin":native_point(origin),"width":1,"height":1})
		if stopped: return
	for scenario in [
		["Well","well",0,Vector3i.ZERO],
		["ScrewPump","pump3",3,Vector3i.ZERO],
		["SiegeEngine:Ballista","siege",5,Vector3i.ZERO],
		["Bridge","retracting",4,Vector3i(2,2,1)],
		["Trap:WeaponTrap","trap",0,Vector3i.ZERO],
		["Construction:Stairs","stairs",0,Vector3i(1,1,3)]]:
		await place_scenario(fixture,scenario)
		if stopped: return
	editor.close_panel()
	check(not interaction.construction_active,"close did not release map input")
	await native("final")
	print("CONSTRUCTION_CONTROLLER_LIVE_PASS")

func place_scenario(fixture: Dictionary, scenario: Array) -> void:
	var key: String = scenario[0]; var site: String = scenario[1]
	step = "controller " + key
	if not check(fixture.sites.has(site),"fixture site missing"): return
	var origin := point(fixture.sites[site])
	world.set_top_z(origin.z); editor._process(0)
	editor.choose_definition(key); editor.set_material_strategy("after")
	if not check(str(editor.draft.definition.get("key","")) == key,"catalog leaf unavailable"): return
	editor.set_orientation(int(scenario[2]))
	var first := origin; var dimensions: Vector3i = scenario[3]
	var area := int(editor.draft.definition.area_mode)
	if area == 1:
		dimensions = editor.draft.dimensions
		for fp in editor.draft.definition.footprints:
			if int(fp.direction) == int(scenario[2]): first += Vector3i(int(fp.center_x),int(fp.center_y),0)
	editor.target_tile(first,true)
	if area > 1:
		if dimensions.z > 1:
			world.set_top_z(origin.z+dimensions.z-1); editor._process(0)
			if not check(editor.corner == first and host.allows_elevation_input(),"stairs lost lower corner on elevation change"): return
		editor.target_tile(origin+dimensions-Vector3i.ONE,true)
	if not await wait_for(func(): return editor.mode == "materials" and editor.request_ticket == 0 and editor.pending_read.is_empty(),"recipe materials"): return
	await observe_stage(key.replace(":","_")+"_materials")
	var mask: Array = Array(editor.draft.valid_mask)
	var recipe: Array = editor.draft.filters.duplicate(true)
	if key == "Well":
		if not check(recipe.size() >= 3,"well must exercise multiple inputs"): return
	for filter_row in recipe:
		var index := int(filter_row.index)
		if not await wait_for(func(): return editor.request_ticket == 0 and editor.pending_read.is_empty() and editor.draft.snapshots.has(index),"filter %d" % index): return
		var variable: bool = editor.draft.variable_count(index)
		var needed := 2 if variable else int(filter_row.quantity)
		var cursor_row := 0
		while needed > 0 and not stopped:
			var snapshot: Dictionary = editor.draft.snapshots[index]
			if cursor_row >= snapshot.rows.size():
				if not check(int(snapshot.next_cursor) > 0,"not enough material for input %d" % index): return
				editor.material_view.page_requested.emit(index,int(snapshot.next_cursor))
				if not await wait_for(func(): return editor.request_ticket == 0 and editor.pending_read.is_empty(),"material page"): return
				continue
			var take := mini(needed,int(snapshot.rows[cursor_row].count))
			editor.material_view.group_selected.emit(index,cursor_row,take)
			needed -= take; cursor_row += 1
		if variable: editor.material_view.filter_done.emit(index)
	if not await wait_for(func(): return editor.request_ticket == 0 and editor.mode == "place" and not editor.placed_sites.is_empty(),"Place"): return
	var receipt: Dictionary = last_receipt.get("construction",{})
	if not check(int(last_receipt.get("status",-1)) == S.Ok,"Place refused"): return
	await observe_stage(key.replace(":","_")+"_placed")
	var args := {"definition":key,"origin":native_point(origin),"width":dimensions.x,"height":dimensions.y,"depth":dimensions.z,
		"direction":0 if int(scenario[2]) == 4 else int(scenario[2]),"retracting":key == "Bridge" and int(scenario[2]) == 4,
		"mode":area,"mask":mask,"placed":int(receipt.get("placed",0)),"skipped":int(receipt.get("skipped",0))}
	if key == "Trap:WeaponTrap": args.weapon_count = 2
	var verified := await native("placed",args)
	if stopped: return
	var ids := building_ids(verified)
	if not check(not ids.is_empty() and editor.placed_sites.has(int(receipt.first_building)),"native/controller placement identity mismatch"): return
	for id in ids:
		editor.begin_inspect(); editor.send({"action":3,"building_id":id})
		if not await wait_for(func(): return editor.request_ticket == 0 and editor.inspected_id == id,"Inspect"): return
		editor.remove_button.pressed.emit()
		if not await wait_for(func(): return editor.request_ticket == 0 and editor.inspected_id == -1,"Remove"): return
		await native("removed",{"id":id})
		if stopped: return
	for dz in dimensions.z:
		await native("site_clear",{"origin":native_point(origin+Vector3i(0,0,dz)),"width":dimensions.x,"height":dimensions.y})
		if stopped: return

func departure_report() -> void:
	write_json("departures.json",[{"id":"controller","text":"Controller scope: catalog/cancel, wall/material reuse, multi-input well and pump, oriented ballista/retracting bridge, variable weapon trap, multi-z stairs, inspect/removal. Consult result status: headless run does not prove mouse/GPU or full native parity."}])
