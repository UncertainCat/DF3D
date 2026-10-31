extends "res://tests/item_carrier_wire_live.gd"
const Header=preload("res://scripts/creature_header_state.gd")

func wait_ready(model,service) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll()
		if model.phase==Header.Phase.Ready:return true
		if model.phase not in [Header.Phase.Reading,Header.Phase.Editing]:break
		await create_timer(0.01).timeout
	return check(false,"Header controller did not become ready; no replay")

func header(data: Dictionary, outcome: int) -> Dictionary:
	var reply:=await request("creature_header",data)
	var result: Dictionary=reply.get("creature_header",{})
	check(reply.get("status")== (C.ManagementStatus.Ok if outcome==1 else C.ManagementStatus.Rejected),"Header status differs")
	check(result.get("outcome")==outcome,"Header outcome differs")
	check(result.has("snapshot")== (outcome==1),"Header authority differs")
	return result.get("snapshot",{})

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-header-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Header bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Header catalog failed"):quit(1);return
	var id:=int(expected.unit_id)
	var read: Dictionary={"action":C.ManagementAction.CreatureHeaderRead,"unit_id":id}
	var initial:=await header(read,1)
	if failed:quit(1);return
	check(str(initial.revision)==expected.revision,"Header exact revision lost in transport")
	for key in ["nickname","profession","figure_nickname"]:check(initial[key]==expected[key],"Header field differs: "+key)
	var current:=initial
	var receipts: Array=[]
	for profession in [false,true]:
		var key: String="profession" if profession else "nickname"
		for value in ["Wire profession" if profession else "Wire nickname","",initial[key]]:
			var edit: Dictionary={"action":C.ManagementAction.CreatureHeaderEdit,"unit_id":id,"profession":profession,"name":value,"expected_revision":current.revision}
			var before:=current
			current=await header(edit,1)
			if failed:quit(1);return
			check(current[key]==value,"Header write receipt differs")
			receipts.append(current)
			if before.revision!=current.revision:
				await header(edit,2)
				var observed:=await header(read,1)
				check(observed==current,"Stale header edit changed state")
				if failed:quit(1);return
	var absent:=read.duplicate();absent.unit_id=2147483000
	await header(absent,0)
	var final:=await header(read,1)
	check(final==initial,"Header transport did not restore original state")
	var service=preload("res://scripts/semantic_action_service.gd").new()
	root.add_child(service);service.configure(world,true)
	var model=Header.new();model.configure(service);model.open(id)
	if not await wait_ready(model,service):quit(1);return
	check(model.begin(),"Header controller refused entry")
	model.edit(false,"Controller A");model.edit(false,"Controller AB");model.edit(true,"Controller job")
	model.close();model.open(id)
	if not await wait_ready(model,service):quit(1);return
	check(model.snapshot.nickname=="Controller AB" and model.snapshot.profession=="Controller job","Closed editor did not finish explicit text before reopen")
	check(model.begin(),"Header controller refused restoration")
	model.edit(false,initial.nickname);model.edit(true,initial.profession);model.finish()
	if not await wait_ready(model,service):quit(1);return
	check(model.snapshot==initial,"Header controller restoration differs")
	model.dispose();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/unit-header-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts,"restored":final==initial,"controller_close_reopen_restored":not failed}));file.close()
	world.queue_free();await process_frame
	quit(1 if failed else 0)
