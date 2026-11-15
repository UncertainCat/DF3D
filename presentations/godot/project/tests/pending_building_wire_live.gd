extends "res://tests/item_carrier_wire_live.gd"
var service
var model
func settle_model() -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and (model.ticket!=0 or service._active!=0 or not service._queue.is_empty()):
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(model.ticket==0 and service._active==0 and service._queue.is_empty(),"Pending controller did not settle; no replay")
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/pending-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Pending building attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Pending catalog claim failed"):quit(1);return
	var intent: Dictionary={"action":C.ManagementAction.ProductionInspect,"pending_building":true,"building_id":int(expected.id)}
	var result:=await request("production",intent)
	var snapshot: Dictionary=result.get("production",{}).get("pending_building",{}).get("snapshot",{})
	check(result.get("status")==C.ManagementStatus.Ok and str(snapshot.get("revision"))==expected.revision,"Pending read lost exact revision")
	check(snapshot.get("stage")==int(expected.stage) and snapshot.get("max_stage")==int(expected.max_stage) and snapshot.get("job_id")==int(expected.job_id),"Pending read changed native identity/stage")
	check(not str(snapshot.get("header_name","")).is_empty(),"Pending header name absent")
	var receipts: Array=[]
	for operation in [0,0,1]:
		if failed:break
		intent={"action":C.ManagementAction.FarmEdit,"pending_building":true,"building_id":int(expected.id),"expected_revision":snapshot.revision,"pending_operation":operation}
		result=await request("production",intent)
		var state: Dictionary=result.get("production",{}).get("pending_building",{})
		check(result.get("status")==C.ManagementStatus.Ok and state.get("outcome")==C.FarmEditOutcome.Completed,"Pending edit failed")
		snapshot=state.get("snapshot",{})
		check(snapshot.get("suspended")==bool(operation==1) and not state.get("removed",true) and not state.get("removing",true),"Pending suspension receipt differs")
		receipts.append(snapshot.duplicate(true))
	if not failed:
		intent.expected_revision=1;intent.pending_operation=2
		result=await request("production",intent)
		var stale: Dictionary=result.get("production",{}).get("pending_building",{})
		check(stale.get("outcome")==C.FarmEditOutcome.Stale and not stale.has("snapshot") and not stale.get("removed",true) and not stale.get("removing",true),"Stale cancellation granted authority")
		service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
		model=preload("res://scripts/pending_building_state.gd").new();model.configure(service)
		model.open(int(expected.id));service.poll(0.01);model.close();await settle_model()
		check(model.phase==model.Phase.Closed and model.snapshot.is_empty(),"Late pending read revived closed controller")
		model.open(int(expected.id));await settle_model()
		check(model.phase==model.Phase.Ready and model.snapshot.revision==snapshot.revision,"Pending controller did not refresh native authority")
		var retired: Array=[];model.retired.connect(func(id,removing):retired.append([id,removing]))
		if not failed:model.edit(model.Operation.Cancel);await settle_model()
		check(model.phase==model.Phase.Closed and model.snapshot.is_empty() and model.building_id==-1,"Cancellation retained obsolete authority")
		check(retired==[[int(expected.id),bool(expected.stage>0)]],"Cancellation outcome differs from stage")
		receipts.append({"retired":retired,"late_read_retired":true})
		model.dispose();service.queue_free()
	if not failed and int(expected.stage)>0:
		var read_intent: Dictionary={"action":C.ManagementAction.ProductionInspect,"pending_building":true,"building_id":int(expected.id)}
		result=await request("production",read_intent)
		snapshot=result.get("production",{}).get("pending_building",{}).get("snapshot",{})
		check(snapshot.get("removing",false) and int(snapshot.get("job_id",-1))>=0,"Removal observation missing native job")
		if not failed:
			intent={"action":C.ManagementAction.FarmEdit,"pending_building":true,"building_id":int(expected.id),"expected_revision":snapshot.revision,"pending_operation":3}
			result=await request("production",intent)
			var cancelled: Dictionary=result.get("production",{}).get("pending_building",{})
			snapshot=cancelled.get("snapshot",{})
			check(result.get("status")==C.ManagementStatus.Ok and cancelled.get("outcome")==C.FarmEditOutcome.Completed,"Cancel removal transport failed")
			check(snapshot.get("job_id")==-1 and snapshot.get("removing")==false and snapshot.get("suspended")==false and snapshot.get("has_worker")==false,"Idle snapshot invented a construction job or worker")
			check(snapshot.get("stage")==int(expected.stage),"Cancel removal changed construction stage")
			receipts.append({"cancel_removal":cancelled.duplicate(true)})
			if not failed:
				intent.expected_revision=snapshot.revision;intent.pending_operation=2
				result=await request("production",intent)
				var queued: Dictionary=result.get("production",{}).get("pending_building",{})
				check(queued.get("outcome")==C.FarmEditOutcome.Completed and queued.get("removing",false) and not queued.has("snapshot"),"Idle removal did not retire authority")
				receipts.append({"idle_remove":queued})
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts}));file.close()
	world.detach_live();world.queue_free();await process_frame
	if not failed:print("PENDING_BUILDING_WIRE_PASS")
	quit(1 if failed else 0)
