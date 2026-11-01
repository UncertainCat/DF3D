extends "res://tests/item_carrier_wire_live.gd"

func expel(intent: Dictionary, outcome: int) -> Dictionary:
	var reply:=await request("creature_expel",intent)
	var result: Dictionary=reply.get("creature_expel",{})
	check(reply.get("status")== (C.ManagementStatus.Ok if outcome in [C.CreatureExpelOutcome.Ready,C.CreatureExpelOutcome.Applied] else C.ManagementStatus.Rejected),"Expel status differs")
	check(result.get("outcome")==outcome,"Expel outcome differs")
	check(result.has("preview")== (outcome==C.CreatureExpelOutcome.Ready),"Expel preview authority differs")
	return result.get("preview",{})

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var phase:=OS.get_environment("DF3D_EXPEL_WIRE_PHASE")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-expel-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Expel bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Expel catalog failed"):quit(1);return
	var id:=int(expected.unit_id)
	var read: Dictionary={"action":C.ManagementAction.CreatureExpelRead,"unit_id":id}
	var initial:=await expel(read,C.CreatureExpelOutcome.Ready)
	if failed:quit(1);return
	for key in ["unit_id","eligible","reason"]:check(initial.get(key)==expected[key],"Expel preview differs: "+key)
	check(initial.destinations.size()==expected.destinations.size(),"Expel destinations length differs")
	for i in range(min(initial.destinations.size(),expected.destinations.size())):
		check(initial.destinations[i].id==int(expected.destinations[i].id) and initial.destinations[i].name==expected.destinations[i].name,"Expel destination differs")
	check(initial.units.size()==expected.units.size(),"Expel group length differs")
	var ids: Array=[]
	for i in range(min(initial.units.size(),expected.units.size())):
		var row: Dictionary=initial.units[i];var reference: Dictionary=expected.units[i]
		for key in ["id","name"]:check(row[key]==reference[key],"Expel unit differs: "+key)
		check(row.name_color.effect==int(reference.effect),"Expel color effect differs")
		for key in ["color","alternate"]:
			for component in range(3):check(row.name_color[key][component]==int(reference[key][component]),"Expel color differs: "+key)
		check(not row.sheet_icon.layers.is_empty(),"Expel full-body recipe absent")
		ids.append(int(row.id))
	var apply: Dictionary={"action":C.ManagementAction.CreatureExpelApply,"unit_id":id,"destination_id":int(expected.destination),"expected_unit_ids":ids}
	if phase=="preview":
		for bad in [{"action":C.ManagementAction.CreatureExpelRead,"unit_id":1.5},
			{"action":C.ManagementAction.CreatureExpelRead,"unit_id":id,"destination_id":-1},
			{"action":C.ManagementAction.CreatureExpelApply,"unit_id":id,"destination_id":-1,"expected_unit_ids":[float(id)]},
			{"action":C.ManagementAction.CreatureExpelApply,"unit_id":id,"destination_id":-1,"expected_unit_ids":[id,id]},
			{"action":C.ManagementAction.CreatureExpelApply,"unit_id":id,"destination_id":-1,"expected_unit_ids":[]}]:
			check(world.management_request("creature_expel",bad)==0,"Malformed Expel accepted locally")
		var stale:=apply.duplicate(true);stale.expected_unit_ids.append(2147483000)
		await expel(stale,C.CreatureExpelOutcome.Rejected)
		stale=apply.duplicate(true);stale.destination_id=2147483000
		await expel(stale,C.CreatureExpelOutcome.Rejected)
		stale=apply.duplicate(true);stale.unit_id=2147483000;stale.expected_unit_ids=[2147483000]
		await expel(stale,C.CreatureExpelOutcome.Rejected)
		var final:=await expel(read,C.CreatureExpelOutcome.Ready)
		check(final==initial,"Rejected Expel changed preview")
	elif phase=="apply":
		if failed:quit(1);return
		await expel(apply,C.CreatureExpelOutcome.Applied)
		if failed:quit(1);return
		await expel(apply,C.CreatureExpelOutcome.Rejected)
		var after:=await expel(read,C.CreatureExpelOutcome.Ready)
		check(not after.eligible and after.units.is_empty(),"Departing unit retained Expel eligibility")
	else:check(false,"Unknown Expel test phase")
	var file:=FileAccess.open(directory+"/unit-expel-wire-"+phase+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"preview":initial,"phase":phase}));file.close()
	world.queue_free();await process_frame
	quit(1 if failed else 0)
