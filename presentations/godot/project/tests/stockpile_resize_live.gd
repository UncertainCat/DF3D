extends "res://tests/areas_acceptance_live.gd"
# Protected semantic acceptance, with independent DF observations. UI lifecycle
# and rendering remain separate requirements.
func exercise() -> void:
	await request({"action":0})
	if stopped: return
	step = "stocked pile resize setup"
	var setup := await native("resize_setup")
	if stopped: return
	for rows in [setup.erase,setup.grow,setup.keep]:
		for row in rows:
			for key in ["x","y","length"]: row[key] = int(row[key])
	var pile := await inspect(int(setup.id))
	if stopped: return
	var intent := {"action":11,"kind":0,"id":int(pile.id),"expected_revision":int(pile.revision),
		"operation":Contract.AreaOperation.Paint,"paint_mode":2,"paint_z":int(pile.origin.z),"spans":setup.erase}
	step = "retired replacement command is rejected before dispatch"
	var retired := intent.duplicate(true); retired.paint_mode = 3
	if not check(world.area_request(retired) == 0,"retired replacement was dispatched"): return
	var unchanged := await inspect(int(pile.id))
	if stopped: return
	if not check(unchanged.revision == pile.revision and unchanged.extents == pile.extents,"retired replacement changed pile"): return
	step = "malformed parallel storage vectors refuse before mutation"
	await native("resize_malformed")
	await request(intent,"Invalid area paint geometry")
	if stopped: return
	await native("resize_restore")
	step = "native assignment release and limit clamp"
	var receipt := await request(intent)
	if stopped: return
	if not check(receipt.areas.size() == 1 and int(receipt.areas[0].tile_count) == 1,"shrink did not return one occupied tile"): return
	await native("resize_check",{"tiles":1})
	step = "stale resize must not replay"
	await request(intent,"Area changed; inspect again")
	if stopped: return
	await native("resize_check",{"tiles":1})
	step = "regrow retains clamped limits and released assignments"
	pile = receipt.areas[0]
	intent.expected_revision = int(pile.revision); intent.paint_mode = 1; intent.spans = setup.grow
	receipt = await request(intent)
	if stopped: return
	await native("resize_check",{"tiles":2})
	step = "empty footprint retains identity and assignments during painting"
	intent.expected_revision = int(receipt.areas[0].revision); intent.paint_mode = 2
	intent.spans = setup.grow + setup.keep
	receipt = await request(intent)
	if stopped: return
	if not check(receipt.areas.size() == 1 and int(receipt.areas[0].tile_count) == 0,"empty pile receipt missing"): return
	await native("resize_check",{"tiles":0})
	step = "regrow empty pile with the same identity"
	intent.expected_revision = int(receipt.areas[0].revision); intent.paint_mode = 1; intent.spans = setup.keep
	receipt = await request(intent)
	if stopped: return
	await native("resize_check",{"tiles":1})
	step = "empty pile removal on painting exit"
	intent.expected_revision = int(receipt.areas[0].revision); intent.paint_mode = 2
	receipt = await request(intent)
	if stopped: return
	await native("resize_check",{"tiles":0})
	await request({"action":12,"kind":0,"id":int(pile.id),"expected_revision":int(receipt.areas[0].revision)})
	if stopped: return
	await native("resize_deleted")
	for sample in ["floor","wall","wall-left","wall-right","all-wall","water7","magma1","hidden","building"]:
		step = "native-clipped creation "+sample
		var site := await native("resize_create_prepare",{"case":sample})
		if stopped: return
		var point := Vector3i(int(site.origin.x),int(site.origin.y),int(site.origin.z))
		var created := await request({"action":10,"kind":0,"operation":5,"paint_mode":1,"paint_z":point.z,
			"spans":[{"x":point.x,"y":point.y,"length":3}]})
		if stopped: return
		if sample == "all-wall":
			if not check(created.areas.is_empty(),"all-clipped creation returned an identity"): return
			await native("resize_create_check",{"id":-1})
		else:
			if not check(created.areas.size()==1,"clipped creation missing identity"): return
			var target: Dictionary = created.areas[0]
			await native("resize_create_check",{"id":int(target.id)})
			await request({"action":12,"kind":0,"id":int(target.id),"expected_revision":int(target.revision)})
			if stopped: return
	for sample in ["wall-left","wall-right","all-wall","floor"]:
		step = "native-clipped repaint growth "+sample
		var site := await native("resize_create_prepare",{"case":"floor"})
		var point := Vector3i(int(site.origin.x),int(site.origin.y),int(site.origin.z))
		var created := await request({"action":10,"kind":0,"operation":5,"paint_mode":1,"paint_z":point.z,
			"spans":[{"x":point.x,"y":point.y,"length":3}]})
		if stopped: return
		var target: Dictionary = created.areas[0]
		site = await native("resize_grow_prepare",{"id":int(target.id),"case":sample})
		point = Vector3i(int(site.origin.x),int(site.origin.y),int(site.origin.z))
		var grown := await request({"action":11,"kind":0,"id":int(target.id),"expected_revision":int(target.revision),
			"operation":5,"paint_mode":1,"paint_z":point.z,"spans":[{"x":point.x,"y":point.y,"length":3}]})
		if stopped: return
		await native("resize_grow_check")
		await request({"action":12,"kind":0,"id":int(target.id),"expected_revision":int(grown.areas[0].revision)})
		if stopped: return
		await native("removed",{"id":int(target.id)})
	for sample in ["hidden","wall","open","water7","magma1","building"]:
		step = "erase invalid stockpile cell "+sample
		var site := await native("resize_create_prepare",{"case":"floor"})
		var point := Vector3i(int(site.origin.x),int(site.origin.y),int(site.origin.z))
		var created := await request({"action":10,"kind":0,"operation":5,"paint_mode":1,"paint_z":point.z,
			"spans":[{"x":point.x,"y":point.y,"length":3}]})
		if stopped: return
		var target: Dictionary = created.areas[0]
		await native("resize_erase_prepare",{"id":int(target.id),"case":sample})
		target = await inspect(int(target.id))
		if stopped: return
		var erased := await request({"action":11,"kind":0,"id":int(target.id),"expected_revision":int(target.revision),
			"operation":5,"paint_mode":2,"paint_z":point.z,"spans":[{"x":point.x,"y":point.y,"length":3}]})
		if stopped: return
		await native("resize_erase_check")
		await request({"action":12,"kind":0,"id":int(target.id),"expected_revision":int(erased.areas[0].revision)})
		if stopped: return
		await native("removed",{"id":int(target.id)})
	for sample in ["partial","full","create-partial","create-full"]:
		step = "native stockpile transfer "+sample
		var site := await native("resize_create_prepare",{"case":"floor"})
		var point := Vector3i(int(site.origin.x),int(site.origin.y),int(site.origin.z))
		var created := await request({"action":10,"kind":0,"operation":5,"paint_mode":1,"paint_z":point.z,
			"spans":[{"x":point.x,"y":point.y,"length":3}]})
		if stopped: return
		var target: Dictionary = created.areas[0]
		site = await native("resize_transfer_prepare",{"id":int(target.id),"case":sample})
		for span in site.spans:
			for key in ["x","y","length"]: span[key]=int(span[key])
		var transfer_intent := {"action":11,"kind":0,"id":int(target.id),"expected_revision":int(target.revision),
			"operation":5,"paint_mode":1,"paint_z":point.z,"spans":site.spans}
		if sample.begins_with("create"):
			transfer_intent.action=10;transfer_intent.erase("id");transfer_intent.erase("expected_revision")
		if sample == "partial":
			var outside_erase := transfer_intent.duplicate(true);outside_erase.paint_mode=2
			await request(outside_erase)
			if stopped: return
			await native("resize_transfer_unchanged")
			await native("resize_transfer_malformed")
			await request(transfer_intent,"",true)
			if stopped: return
			await native("resize_transfer_restore")
		var transferred := await request(transfer_intent)
		if stopped: return
		var recipient: Dictionary = transferred.areas[0]
		await native("resize_transfer_check",{"id":int(recipient.id)})
		await request({"action":12,"kind":0,"id":int(recipient.id),"expected_revision":int(recipient.revision)})
		if stopped: return
		await native("removed",{"id":int(recipient.id)})
		if sample.begins_with("create"):
			await request({"action":12,"kind":0,"id":int(target.id),"expected_revision":int(target.revision)})
			if stopped: return
			await native("removed",{"id":int(target.id)})
	await link_boundaries()
	await native("final")

func link_boundaries() -> void:
	var cases: Array = []
	for endpoint in [1,2,3]:
		for key in ["give_to_pile","take_from_pile","give_to_workshop","take_from_workshop"]:
			for malformed in ["duplicate","unsorted","null"]:
				cases.append({"endpoint":endpoint,"key":key,"case":malformed,"give":true})
	for give in [true,false]:
		for workshop in [false,true]:
			var source_key := "give_to_pile" if give else "take_from_pile"
			var reverse_key := ("take_from_workshop" if give else "give_to_workshop") if workshop else ("take_from_pile" if give else "give_to_pile")
			for endpoint in [3 if workshop else 1,2]:
				for count in [1023,1024,1025]:
					cases.append({"endpoint":endpoint,"key":source_key if endpoint != 2 else reverse_key,
						"case":"capacity","count":count,"give":give,"workshop":workshop,"success":count == 1023})
	for scenario in cases:
		step = "link boundary " + JSON.stringify(scenario)
		var setup := await native("resize_link_setup")
		if stopped: return
		var workshop: bool = bool(scenario.get("workshop",int(scenario.endpoint) == 3))
		var source: int = int(setup.workshop if workshop else setup.source)
		var observed: int = int(setup.target if workshop else setup.source)
		var before := await inspect(observed)
		if stopped: return
		await native("resize_link_inject",scenario)
		if stopped: return
		var inspector_rejects: bool = int(scenario.endpoint) != 3 and (scenario.case != "capacity" or int(scenario.get("count",0)) > 1024)
		if not inspector_rejects:
			before = await inspect(observed)
			if stopped: return
		var intent := {"action":13,"kind":0,"id":source,"link_id":int(setup.target),
			"expected_revision":int(before.revision),"give":bool(scenario.give)}
		if workshop:
			intent.operation = Contract.AreaOperation.WorkshopLink
			intent.kind = Contract.AreaKind.Workshop
		var succeeds: bool = bool(scenario.get("success",false))
		var rejection := ""
		if inspector_rejects:
			rejection = "Area no longer exists" if scenario.case != "capacity" else "This pile exceeds the bounded link inspector (1024 per direction)"
		await request(intent,rejection,not succeeds)
		# Restore fixture state even when the production assertion fails.
		var prior_stopped := stopped; stopped = false
		var expected: Dictionary = scenario.duplicate(); expected.workshop = workshop; expected.success = succeeds
		await native("resize_link_check_restore",expected)
		stopped = stopped or prior_stopped
		if stopped: return
