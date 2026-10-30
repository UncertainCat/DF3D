extends "res://tests/item_carrier_wire_live.gd"

func edit_header(snapshot: Dictionary, operation: int, name: String="") -> Dictionary:
	var intent={"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":snapshot.id,"expected_revision":snapshot.revision,"farm_operation":operation}
	if operation==C.FarmOperation.Rename:intent.farm_name=name
	return await request("production",intent)

func completed(response: Dictionary, operation: int) -> Dictionary:
	var state: Dictionary=response.get("production",{}).get("building_header",{})
	check(response.get("status")==C.ManagementStatus.Ok and state.get("outcome")==C.FarmEditOutcome.Completed and state.get("operation")==operation,"Chest header edit not confirmed")
	return state.get("snapshot",{})

func refused(response: Dictionary, outcome: int) -> void:
	var state: Dictionary=response.get("production",{}).get("building_header",{})
	check(response.get("status")==C.ManagementStatus.Rejected and state.get("outcome")==outcome and not state.has("snapshot"),"Refused header edit granted authority")

var header_service
var header_model
func settle_header() -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();header_service.poll(0.01)
		if header_model.phase not in [header_model.Phase.Reading,header_model.Phase.Applying]:break
		await create_timer(0.01).timeout
	check(header_model.phase==header_model.Phase.Ready,"Header controller did not reach Ready")

func open_header(id: int) -> void:
	header_service=preload("res://scripts/semantic_action_service.gd").new();header_service.configure(world,true)
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();header_service.poll(0.01)
		if header_service._epoch>0 and not header_service._needs_claim and header_service._active==0 and not header_service._transport_lost:break
		await create_timer(0.01).timeout
	check(header_service._epoch>0 and not header_service._needs_claim and header_service._active==0,"Header service claim failed")
	header_model=preload("res://scripts/building_header_state.gd").new();header_model.configure(header_service)
	header_model.open(id);await settle_header()

func close_header() -> void:
	header_model.dispose();header_service.free();header_model=null;header_service=null

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/chest-header-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Chest header attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Chest header catalog failed"):quit(1);return
	var intent={"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":int(expected.snapshot.id)}
	var response:=await request("production",intent)
	var initial: Dictionary=response.get("production",{}).get("building_header",{}).get("snapshot",{})
	if not check(response.get("status")==C.ManagementStatus.Ok and not initial.is_empty(),"Chest header read failed"):quit(1);return
	check(str(initial.revision)==expected.snapshot.revision,"Chest header exact revision differs")
	for field in ["id","type","stage","max_stage","custom_name","native_name","header_name","removing","suspended","has_worker"]:
		check(initial[field]==expected.snapshot[field],"Chest header field differs: "+field)
	var receipts: Array=[]
	if expected.mode in ["worker","suspended"]:
		if expected.mode=="worker":
			var stale:=initial.duplicate();stale.revision=int(expected.stale_revision)
			refused(await edit_header(stale,C.FarmOperation.CancelRemoval),C.FarmEditOutcome.Stale)
		await open_header(initial.id)
		check(header_model.snapshot==initial,"Controller worker read differs")
		header_model.cancel_removal();await settle_header()
		var cancelled: Dictionary=header_model.snapshot.duplicate(true)
		check(not cancelled.get("removing",true) and not cancelled.get("has_worker",true),"Chest worker cancellation not reflected")
		receipts.append(cancelled);close_header()
	else:
		var renamed:=completed(await edit_header(initial,C.FarmOperation.Rename,"lower chest"),C.FarmOperation.Rename)
		if not check(not renamed.is_empty(),"Missing rename receipt"):quit(1);return
		check(renamed.custom_name=="lower chest" and renamed.header_name=="Lower chest","Chest rename captions differ")
		refused(await edit_header(initial,C.FarmOperation.Rename,"stale"),C.FarmEditOutcome.Stale)
		var repeated:=completed(await edit_header(renamed,C.FarmOperation.Rename,"lower chest"),C.FarmOperation.Rename)
		check(repeated==renamed,"Repeated rename changed authority")
		refused(await edit_header(renamed,C.FarmOperation.Rename,"X".repeat(31)),C.FarmEditOutcome.Rejected)
		var restored:=completed(await edit_header(renamed,C.FarmOperation.Rename,initial.custom_name),C.FarmOperation.Rename)
		check(restored==initial,"Rename restoration differs")
		var removed:=completed(await edit_header(restored,C.FarmOperation.Remove),C.FarmOperation.Remove)
		check(removed.get("removing",false),"Chest not marked for removal")
		refused(await edit_header(removed,C.FarmOperation.Rename,"blocked"),C.FarmEditOutcome.Rejected)
		var cancelled:=completed(await edit_header(removed,C.FarmOperation.CancelRemoval),C.FarmOperation.CancelRemoval)
		check(cancelled==initial,"Cancellation restoration differs")
		receipts=[renamed,restored,removed,cancelled]
		var absent:=intent.duplicate();absent.building_id=2147483647
		var rejected:=await request("production",absent)
		check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.get("production",{}).get("building_header",{}).has("snapshot"),"Absent chest read granted authority")
	var controller_receipts: Array=[]
	if expected.mode=="idle":
		await open_header(initial.id)
		check(header_model.snapshot==initial,"Controller header read differs")
		header_model.rename("controller chest");await settle_header()
		check(header_model.snapshot.get("custom_name")=="controller chest","Controller rename not reflected")
		controller_receipts.append(header_model.snapshot.duplicate(true))
		header_model.rename(initial.custom_name);await settle_header()
		header_model.request_removal();await settle_header()
		check(header_model.snapshot.get("removing",false),"Controller removal not reflected")
		controller_receipts.append(header_model.snapshot.duplicate(true))
		header_model.cancel_removal();await settle_header()
		check(header_model.snapshot==initial,"Controller final restoration differs")
		controller_receipts.append(header_model.snapshot.duplicate(true))
		check(header_model.begin_name_entry(),"Live chest name entry did not begin")
		header_model.edit_name_entry("typed");header_model.edit_name_entry("typed chest");header_model.finish_name_entry();await settle_header()
		check(header_model.snapshot.get("custom_name")=="typed chest","Final typed chest name differs")
		controller_receipts.append(header_model.snapshot.duplicate(true))
		check(header_model.begin_name_entry(),"Live restore name entry did not begin")
		header_model.edit_name_entry(initial.custom_name);header_model.close()
		var drain_deadline:=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<drain_deadline:
			world.poll();header_service.poll(0.01)
			if header_service._active==0 and header_service._queue.is_empty():break
			await create_timer(0.01).timeout
		check(header_service._active==0 and header_service._queue.is_empty() and header_model.phase==header_model.Phase.Closed,"Close did not drain typed name")
		header_model.open(initial.id);await settle_header()
		check(header_model.snapshot==initial,"Closing name entry did not restore final typed name")
		controller_receipts.append(header_model.snapshot.duplicate(true));close_header()
	var file:=FileAccess.open(directory+"/chest-header-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"mode":expected.mode,"initial_revision":str(initial.revision),"receipts":receipts,"controller_receipts":controller_receipts,"worker_uses_controller":expected.mode=="worker"}));file.close()
	world.detach_live();world.queue_free();await process_frame
	if not failed:print("CHEST_HEADER_WIRE_PASS")
	quit(1 if failed else 0)
