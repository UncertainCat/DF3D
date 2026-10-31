extends "res://tests/item_carrier_wire_live.gd"
var service
var follow
var resets:=0

func transition(operation: String) -> void:
	var file:=FileAccess.open(directory+"/unit-follow-lifecycle-request.tmp",FileAccess.WRITE)
	file.store_string(JSON.stringify({"op":operation}));file.close()
	DirAccess.rename_absolute(directory+"/unit-follow-lifecycle-request.tmp",directory+"/unit-follow-lifecycle-request.json")
	var deadline:=Time.get_ticks_msec()+5000
	while not FileAccess.file_exists(directory+"/unit-follow-lifecycle-ack.json") and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	if not check(FileAccess.file_exists(directory+"/unit-follow-lifecycle-ack.json"),"Lifecycle transition timed out"):return
	var result: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-follow-lifecycle-ack.json"))
	DirAccess.remove_absolute(directory+"/unit-follow-lifecycle-ack.json")
	check(result.op==operation,"Lifecycle acknowledgement differs")

func ready() -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01)
		if follow.last_position!=null:return true
		await create_timer(0.01).timeout
	return check(false,"Follow position not confirmed")

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-follow-lifecycle-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Lifecycle attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Lifecycle catalog failed"):quit(1);return
	service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false);service.poll()
	service.session_changed.connect(func():resets+=1)
	follow=preload("res://scripts/creature_follow.gd").new();root.add_child(follow);follow.configure(service);follow.set_process(false)
	follow.toggle(int(expected.unit_id))
	if not await ready():quit(1);return
	var original: Vector3i=follow.last_position
	await transition("disable")
	deadline=Time.get_ticks_msec()+5000
	while resets==0 and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(resets>0 and follow.unit_id==-1 and follow.last_position==null,"Actual bridge loss retained follow authority")
	await transition("enable")
	deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01)
		if not service._transport_lost and service._active==0 and service._queue.is_empty() and world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	follow._process(10);service.poll()
	check(follow.unit_id==-1 and follow.ticket==0,"Replacement producer automatically resumed follow")
	follow.toggle(int(expected.unit_id))
	if await ready():check(follow.last_position==original,"Explicit recovery position differs")
	var file:=FileAccess.open(directory+"/unit-follow-lifecycle-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"resets":resets,"stopped_on_loss":true,"explicit_recovery":true}));file.close()
	follow.dispose();follow.queue_free();service.queue_free();world.queue_free();await process_frame
	quit(1 if failed else 0)
