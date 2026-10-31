extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-follow-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Follow bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Follow catalog failed"):quit(1);return
	var intent: Dictionary={"action":C.ManagementAction.CreatureLocate,"unit_id":int(expected.unit_id)}
	var response:=await request("creature_follow",intent)
	check(response.get("status")== (C.ManagementStatus.Ok if expected.valid else C.ManagementStatus.Rejected),"Follow status differs")
	check(response.has("creature_position")==expected.valid,"Follow authority differs")
	if expected.valid:
		check(response.creature_position=={"unit_id":int(expected.unit_id),"position":Vector3i(int(expected.x),int(expected.y),int(expected.z))},"Follow position differs")
	var absent:=intent.duplicate();absent.unit_id=2147483000
	var refusal:=await request("creature_follow",absent)
	check(refusal.get("status")==C.ManagementStatus.Rejected and not refusal.has("creature_position"),"Missing unit retained position")
	for bad in [{"action":C.ManagementAction.CreatureLocate,"unit_id":-1},{"action":C.ManagementAction.CreatureLocate,"unit_id":1.5},{"action":C.ManagementAction.CreatureLocate,"unit_id":int(expected.unit_id),"name":"extra"}]:
		check(world.management_request("creature_follow",bad)==0,"Malformed follow request accepted")
	var file:=FileAccess.open(directory+"/unit-follow-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"valid":expected.valid,"unit_id":expected.unit_id}));file.close()
	world.queue_free();await process_frame
	quit(1 if failed else 0)
