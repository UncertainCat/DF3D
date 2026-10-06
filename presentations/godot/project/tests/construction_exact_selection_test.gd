extends SceneTree
const Draft = preload("res://scripts/construction_draft.gd")
var failures := 0
var transitions := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func setup(rows: Array, quantity: int):
	var draft = Draft.new()
	draft.definition = {"key":"Construction:Track"}
	draft.preview_valid = true
	draft.filters = [{"index":0,"quantity":quantity}]
	draft.snapshots = {0:{"revision":123,"rows":rows.duplicate(true)}}
	return draft

func group(ids: Array, costs: Dictionary, material: int = 0) -> Dictionary:
	var candidates: Array = []
	for id in ids: candidates.append({"id":int(id),"distance":int(costs[str(int(id))]),"name":"fixture item"})
	candidates.sort_custom(func(a,b): return a.distance < b.distance or (a.distance == b.distance and a.id < b.id))
	return {"item_type":0,"item_subtype":-1,"mat_type":0,"mat_index":material,"count":ids.size(),"candidates":candidates}

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/material_candidates.json"))
	for capture in fixture.selection_kernel_capture.cases:
		for native_group in capture.groups:
			var row := group(native_group.ids,capture.candidate_distances)
			var draft = setup([row],native_group.ids.size())
			for step in native_group.steps:
				var current: int = draft.group_count(0,row)
				var desired := mini(current+1,int(row.count)) if step.action == "select" else maxi(current-1,0)
				check(draft.select_group(0,0,desired),"native transition accepted")
				var expected: Array = []
				for id in step.selected: expected.append(int(id))
				check(draft.selected_ids(0,row)==expected,"exact native selected IDs")
				check(draft.group_count(0,row)==int(step.used),"native used count")
				check(draft.group_distance(0,row)==int(step.distance),"native remaining distance")
				transitions += 1
	var iron := group([3225,3226],{"3225":2,"3226":1})
	var silver := group([41071,41075],{"41071":1,"41075":1},1)
	var draft = setup([iron,silver],3)
	check(draft.select_item(0,0,3225),"expanded farther item selected exactly")
	check(draft.selected_ids(0,iron)==[3225],"nearer item not substituted")
	check(draft.select_item(0,0,3225) and draft.group_count(0,iron)==1,"repeat click no-op")
	check(not draft.select_item(0,0,41071),"foreign group item rejected")
	check(draft.select_group(0,1,2) and draft.covered(0),"all obeys requirement across groups")
	check(not draft.select_item(0,0,3226),"exact click cannot exceed requirement")
	check(draft.select_item(0,0,3225),"repeat selected click at full requirement remains no-op")
	check(draft.place_request().is_empty(),"unfinished exact placement cannot silently drop IDs")
	check(draft.select_group(0,1,1) and draft.selected_ids(0,silver)==[41071],"farthest deselect highest ID on tie")
	check(draft.select_group(0,1,0) and draft.selected_ids(0,silver).is_empty(),"None clears exact IDs")
	check(draft.select_group(0,1,1) and draft.selected_ids(0,silver)==[41075],"nearest select highest ID on tie")
	var owned: Array = draft.selected_ids(0,iron); owned.clear()
	check(draft.selected_ids(0,iron)==[3225],"callers cannot mutate retained IDs")
	for kind in ["Bed","Chair","Table","Coffin","Cabinet","Box","Statue","Slab"]:
		var furniture = setup([iron],1)
		furniture.definition={"key":kind,"family":kind}
		check(furniture.select_item(0,0,3225),"furniture exact item selected")
		var intent: Dictionary=furniture.place_request()
		check(not intent.is_empty() and intent.selections[0].item_ids==[3225],"furniture preserves farther exact item")

	for kind in ["Wall","Floor","Ramp","Fortification","Stairs"]:
		var terrain=setup([iron],1);terrain.definition={"key":"Construction:"+kind,"family":"Construction"}
		terrain.origin=Vector3i(1,2,3);terrain.material_anchor=Vector3i(1,2,3)
		check(terrain.select_item(0,0,3225),"terrain farther item chosen")
		check(terrain.place_request().selections[0].item_ids==[3225],"terrain Place preserves exact choice")
	var ordinary := group([1],{"1":2})
	var improved := group([2],{"2":2}); improved.individual_id=2
	var improved_other := group([3],{"3":2}); improved_other.individual_id=3
	var special=setup([ordinary,improved,improved_other],3)
	special.definition={"key":"Bridge","family":"Bridge"}
	for index in 3: check(special.select_item(0,index,index+1),"same-material standalone selection remains distinct")
	check(special.selections.size()==3 and special.covered(0),"standalone rows do not overwrite generic group or each other")
	check(special.place_request().selections[1].individual_id==2,"standalone identity crosses request boundary")
	check(special.deselect_item(0,1,2) and special.selected_ids(0,ordinary)==[1] and special.selected_ids(0,improved_other)==[3],"standalone removal preserves other rows")

	draft.invalidate()
	check(draft.selections.is_empty() and draft.snapshots.is_empty() and not draft.select_item(0,0,3225),"reset clears selected IDs and ownership")
	print("CONSTRUCTION_EXACT_SELECTION ","PASS" if failures==0 else "FAIL"," native_transitions=",transitions)
	quit(0 if failures==0 else 1)
