extends SceneTree
const Draft = preload("res://scripts/construction_draft.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func definition() -> Dictionary:
	return {"key":"TradeDepot", "family":"TradeDepot", "supported":true, "orientations":1, "area_mode":1,
		"max_width":5, "max_height":5, "max_depth":1,
		"footprints":[{"direction":0,"width":5,"height":5,"center_x":2,"center_y":2}]}

func group(material: int, count: int = 2) -> Dictionary:
	return {"item_type":0,"item_subtype":-1,"mat_type":0,"mat_index":material,"count":count,"name":"stone"}

func preview(filters: Array) -> Dictionary:
	return {"status":2,"placement_valid":true,"construction":{"filters":filters,"valid_mask":[1],"pieces":[0]}}

func page(rows: Array, revision: int, cursor: int = 0, filter_index: int = 0) -> Dictionary:
	return {"status":2,"next_cursor":cursor,"construction":{"filter":filter_index,"build_phase":0,"list_revision":revision,"total":3,"materials":rows}}

func _initialize() -> void:
	test_material_transfer()
	var draft = Draft.new()
	var wheel := definition(); wheel.key="WaterWheel"; wheel.family="WaterWheel"; wheel.orientations=3
	wheel.footprints=[{"direction":0,"width":3,"height":1,"center_x":1,"center_y":0},{"direction":1,"width":1,"height":3,"center_x":0,"center_y":1}]
	check(draft.choose(wheel) and draft.direction==1,"native WaterWheel defaults north-south")
	check(draft.set_site(Vector3i(103,39,165),Vector3i(103,39,165)) and draft.origin==Vector3i(103,38,165),"native WaterWheel centered pointer anchor")
	draft.definition.key="ScrewPump";draft.direction=1;draft.preview_valid=true
	var pump_query:Dictionary=draft.material_request(0)
	check(int(pump_query.direction)==1,"Pump materials carry input direction into native admission and distance identity")
	pump_query.direction=3
	check(draft.accept_materials(page([],10),pump_query)=="obsolete","Opposite pump input has a different material snapshot even with the same footprint")
	check(draft.choose(definition()), "catalog footprint selected")
	check(draft.set_site(Vector3i(10,20,3), Vector3i(10,20,3)), "center click accepted")
	check(draft.origin == Vector3i(8,18,3) and draft.dimensions == Vector3i(5,5,1), "catalog center determines fixed footprint origin")
	draft.accept_preview(preview([{"index":0,"quantity":3}]))
	var query: Dictionary = draft.material_request(0)
	check(query.width==5 and query.height==5 and query.depth==1,"material requests retain the preview footprint")
	var pending := page([], 0); pending.construction.build_phase = 1
	check(draft.accept_materials(pending, query) == "pending" and draft.snapshots.is_empty(), "builder progress is not an empty snapshot")
	check(draft.accept_materials(page([group(1),group(2)],17,2),query) == "ready", "first material page")
	check(draft.select_group(0,0,2) and not draft.can_place(), "partial group cannot place")
	query = draft.material_request(0,2)
	check(query.expected_list_revision == 17, "next page pinned to exact revision")
	check(draft.accept_materials(page([group(3)],17),query) == "ready", "second page accumulates")
	check(draft.group_count(0,group(1)) == 2, "pagination preserves selection")
	check(not draft.select_group(0,2,2) and draft.select_group(0,2,1), "group selection enforces remaining recipe quantity")
	var place: Dictionary = draft.place_request()
	check(place.action == 2 and not place.has("items") and place.selections.size() == 2 and place.selections[1].mat_index == 3 and place.selections[1].expected_list_revision == 17, "Place carries grouped identity and snapshot without retired item IDs")
	check(draft.accept_materials(page([group(3)],18),query) == "failed" and not draft.can_place() and draft.selections.is_empty(), "mixed snapshot clears readiness and chosen groups")
	draft.accept_preview(preview([{"index":0,"quantity":1},{"index":1,"quantity":1}]))
	draft.accept_materials(page([group(1)],20),draft.material_request(0))
	draft.select_group(0,0,1)
	check(not draft.can_place(), "multi-input recipe requires every filter")
	draft.accept_materials(page([group(9)],21,0,1),draft.material_request(1))
	draft.select_group(1,0,1)
	check(draft.can_place() and draft.place_request().selections[1].expected_list_revision == 21, "different filters retain their own revisions")
	draft.definition.key = "Trap:WeaponTrap"; draft.definition.subtype_key = "WeaponTrap"
	check(draft.variable_count(1) and not draft.select_group(1,0,11), "weapon input allows a bounded variable count")
	check(draft.select_group(1,0,2) and draft.can_place(), "weapon input can exceed preview minimum")
	draft.accept_preview(preview([{"index":0,"quantity":1}]))
	query = draft.material_request(0)
	draft.accept_materials(page([group(1)],22,1),query)
	check(draft.accept_materials(page([group(1)],22),draft.material_request(0,1)) == "failed", "duplicate groups across pages fail closed")
	var area := definition(); area.key="Construction:Stairs"; area.area_mode = 4; area.max_width = 31; area.max_height = 31; area.max_depth = 256
	draft.choose(area)
	check(draft.set_site(Vector3i(14,22,5),Vector3i(10,20,3)) and draft.origin == Vector3i(10,20,3) and draft.dimensions == Vector3i(5,3,3), "reverse area and elevation selection normalize minimum corner")
	query=draft.material_request(0)
	check(query.width==5 and query.height==3 and query.depth==3 and query.material_anchor==Vector3i(10,20,3),"Materials preserves volume and reverse gesture endpoint")
	var reverse_request=draft.request(2)
	check(reverse_request.material_anchor==query.material_anchor,"Place keeps the material anchor")
	draft.accept_preview(preview([{"index":0,"quantity":3}]))
	var stale=query.duplicate();stale.material_anchor=Vector3i(14,22,5)
	check(draft.accept_materials(page([group(1)],29),stale)=="obsolete","opposite endpoint material receipt is obsolete")
	check(not draft.set_site(Vector3i(0,0,0),Vector3i(30,30,2)) and not draft.can_place(), "bounded footprint rejects more than 1024 cells")
	area.orientations = 3; area.footprints.append({"direction":1,"width":1,"height":3,"center_x":0,"center_y":1})
	draft.choose(area)
	check(draft.orient(1) and draft.dimensions == Vector3i(1,3,1) and not draft.orient(3), "orientation uses only catalog-supported footprints")
	area.family = "Rollers"; area.area_mode = 2
	draft.choose(area); draft.set_site(Vector3i(8,8,3),Vector3i(4,5,3))
	check(draft.origin == Vector3i(8,5,3) and draft.dimensions == Vector3i(1,4,1), "north-source roller drag remains on its vertical axis")
	draft.orient(1); draft.set_site(Vector3i(8,8,3),Vector3i(4,5,3))
	check(draft.origin == Vector3i(4,8,3) and draft.dimensions == Vector3i(5,1,1), "east-source roller drag remains on its horizontal axis")
	draft.clear()
	check(draft.definition.is_empty() and draft.snapshots.is_empty() and draft.selections.is_empty() and not draft.can_place(), "session clear removes all local identity")
	pressure_rules(draft)
	var windmill:=definition(); windmill.key="Windmill"; windmill.family="Windmill"
	draft.choose(windmill); draft.set_site(Vector3i(8,8,3),Vector3i(8,8,3))
	draft.accept_preview(preview([{"index":0,"quantity":4}]))
	var logs:=group(1,6); logs.candidates=[]
	for id in range(1,7): logs.candidates.append({"id":id,"name":"fixture log","distance":id})
	draft.accept_materials(page([logs],23),draft.material_request(0))
	for id in [2,3,4,5]: check(draft.select_item(0,0,id),"Windmill accepts an explicit expanded item")
	var exact:Dictionary=draft.place_request()
	check(not exact.is_empty() and exact.selections[0].item_ids==[2,3,4,5],"Windmill Place preserves exact selected identities")
	print("CONSTRUCTION_DRAFT ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func pressure_rules(draft) -> void:
	var path := ProjectSettings.globalize_path("res://../../../fixtures/construction/pressure_plate.json")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var plate := definition(); plate.key = "Trap:PressurePlate"; plate.family = "Trap"
	draft.choose(plate)
	for key in Draft.PRESSURE_DEFAULT:
		var expected = fixture.default.flags[key] if key in fixture.default.flags else fixture.default[key]
		check(draft.pressure_plate[key] == expected,"pressure default matches native capture: " + key)
	var fluid_kind := ""
	for row in fixture.controls.fluid_ranges:
		if row.kind != fluid_kind:
			draft.choose(plate); fluid_kind = row.kind
		# Replay the capture's actual continuous 0,7,minimum,maximum input sequence.
		draft.choose_pressure_fluid(row.kind,0)
		draft.choose_pressure_fluid(row.kind,7)
		draft.choose_pressure_fluid(row.kind,int(row.expected_min))
		draft.choose_pressure_fluid(row.kind,int(row.expected_max))
		check(draft.pressure_plate[row.kind+"_min"] == row.expected_min and draft.pressure_plate[row.kind+"_max"] == row.expected_max,"native fluid range replay")
	draft.choose(plate)
	for row in fixture.controls.cart_boundaries:
		draft.adjust_pressure_cart("min" if row.phase.begins_with("min") else "max",1 if row.phase.begins_with("min-up") or row.phase.begins_with("max-up") else -1)
		check(draft.pressure_plate.track_min == row.track_min and draft.pressure_plate.track_max == row.track_max,"native cart crossing/boundary replay")
	draft.choose(plate)
	for row in fixture.scroll.bottom_choices:
		draft.choose_pressure_creature((185+int(row.clicked_y)-26+1)*1000)
		check(draft.pressure_plate.unit_min == row.unit_min and draft.pressure_plate.unit_max == row.unit_max,"native final-row selection replay")
	draft.set_pressure_flag("citizens",true); draft.set_pressure_flag("units",true)
	var before: Dictionary = draft.pressure_plate.duplicate()
	draft.set_pressure_flag("units",false); draft.set_pressure_flag("units",true)
	check(draft.pressure_plate == before,"creature toggles preserve range and citizen flag")
	draft.preview_valid = true; draft.choose_pressure_fluid("water",3)
	check(not draft.preview_valid,"pressure change invalidates preview/material choices")
	var intent: Dictionary = draft.request(2)
	check(intent.pressure_plate == draft.pressure_plate,"complete pressure profile reaches Place")
	intent.pressure_plate.unit_min = 123
	check(draft.pressure_plate.unit_min != 123,"intent owns its profile copy")
	draft.choose(plate)
	check(draft.pressure_plate == Draft.PRESSURE_DEFAULT,"reopen resets native pressure defaults")
	check(not draft.request(0).has("pressure_plate"),"pressure options stay out of catalog requests")
	draft.choose(definition())
	check(not draft.request(2).has("pressure_plate"),"pressure options stay out of other building requests")

func test_material_transfer() -> void:
	for take in [false,true]:
		var draft := Draft.new(); draft.choose(definition())
		draft.set_site(Vector3i(10,20,3),Vector3i(10,20,3))
		draft.accept_preview(preview([{"index":0,"quantity":1}]))
		var source := page([group(1)],90)
		check(draft.accept_materials(source,draft.material_request(0),take)=="ready","material transfer accepts pinned receipt")
		check(is_same(draft.snapshots[0].rows[0],source.construction.materials[0])==take,"owned rows transfer while borrowed rows keep copy isolation")
