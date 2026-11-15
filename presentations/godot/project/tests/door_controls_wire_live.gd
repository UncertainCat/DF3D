extends "res://tests/item_carrier_wire_live.gd"
const Model=preload("res://scripts/door_controls_state.gd")
var service
var model

func settle() -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and model.phase in [Model.Phase.Reading,Model.Phase.Applying]:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	if model.phase!=Model.Phase.Ready:print("Door failure: phase=",model.phase," error=",world.last_error())
	return check(model.phase==Model.Phase.Ready,"Door controller did not obtain authority")

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/door-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Door bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Door catalog claim failed"):quit(1);return
	service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	model=Model.new();model.configure(service);model.open(int(expected.id))
	var receipts: Array=[]
	if await settle():
		check(str(model.snapshot.revision)==expected.revision,"Door revision lost precision across transport")
		var flags:=int(expected.flags)
		check(model.snapshot.taken_by_invaders==bool(flags&4) and model.snapshot.used_by_intruder==bool(flags&8) and model.snapshot.operated_by_mechanisms==bool(flags&32),"Door control reasons differ from native")
		if expected.get("read_only",false):
			check(model.snapshot.forbidden==bool(flags&1) and model.snapshot.closed==bool(flags&16),"Door mode state differs from native")
			receipts.append(model.snapshot.duplicate(true))
			await finish(receipts,false);return
		check(not model.snapshot.forbidden and model.snapshot.closed and not model.snapshot.controlled,"Door initial state differs")
		for value in [true,true,false]:
			if failed:break
			model.set_forbidden(value)
			if not await settle():break
			check(model.snapshot.forbidden==value,"Door completion disagrees with desired state")
			receipts.append({"forbidden":value,"revision":str(model.snapshot.revision)})
		if not failed:
			var stale:=await request("production",{"action":C.ManagementAction.FarmEdit,"door_controls":true,"building_id":int(expected.id),"expected_revision":1,"door_forbidden":1})
			var state: Dictionary=stale.get("production",{}).get("door_controls",{})
			check(state.get("outcome")==C.FarmEditOutcome.Stale and not state.has("snapshot"),"Stale door edit granted authority")
	model.close();model.open(int(expected.id));service.poll(0.01);model.close()
	for i in 10:world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty(),"Late door reply revived closed controls")
	await finish(receipts,true)

func finish(receipts: Array,edited: bool) -> void:
	model.dispose();service.queue_free()
	var capture:=OS.get_environment("DF3D_DOOR_CAPTURE")
	if capture.is_empty():capture="workshop-wire"
	var file:=FileAccess.open(directory+"/"+capture+"-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts,"stale_checked":edited,"late_retired":edited}));file.close()
	world.detach_live();world.queue_free();await process_frame
	if not failed:print("DOOR_CONTROLS_WIRE_PASS")
	quit(1 if failed else 0)
