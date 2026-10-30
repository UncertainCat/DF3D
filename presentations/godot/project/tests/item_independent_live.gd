extends "res://tests/areas_acceptance_live.gd"
var observations: Array=[]
var item_model
var item_actions

func ask(fields: Dictionary,outcome:=0) -> Dictionary:
	var data=fields.duplicate();data.independent_item=true;data.item_id=fields.get("item_id",int(fixture.item_id))
	world.poll()
	var sequence: int=world.management_request("production",data)
	if not check(sequence>0,"independent item command not sent: "+world.last_error()):return {}
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var response: Dictionary=world.poll_management()
		if int(response.get("request_seq",0))==sequence and response.get("status",S.Idle) in [S.Ok,S.Rejected]:
			if not check(response.status==(S.Ok if outcome in [0,1] else S.Rejected),"independent status differs"):return {}
			var production: Dictionary=response.get("production",{})
			var state: Dictionary=production.get("independent_item",{})
			if not check(state.get("outcome",-1)==(0 if outcome<0 else outcome) and production.get("selected_building",-1)==-1 and not production.has("item") and not production.has("contents"),"mixed independent authority"):return {}
			if outcome not in [0,1]:
				check(not state.has("snapshot") and not state.has("edit"),"unconfirmed independent authority");return {}
			if outcome==1:
				if not check(state.get("edit",{})=={"item_id":int(fixture.item_id),"farm_operation":data.farm_operation,"value":data.item_value},"independent receipt does not match intent"):return {}
			var snapshot: Dictionary=state.get("snapshot",{})
			if not check(not snapshot.is_empty() and not snapshot.has("building_id") and not snapshot.has("role") and not snapshot.has("completed"),"independent snapshot has building authority"):return {}
			await native("independent_verify",{"snapshot":snapshot,"revision_text":str(snapshot.revision)})
			if stopped:return {}
			observations.append(snapshot.duplicate(true));return snapshot
		await create_timer(0.01).timeout
	incomplete("independent item request timed out; no replay",true);return {}

func read_item() -> Dictionary:return await ask({"action":Contract.ManagementAction.ProductionInspect})
func edit_item(operation: int,value: bool,revision: int,outcome:=1) -> Dictionary:
	return await ask({"action":Contract.ManagementAction.FarmEdit,"farm_operation":operation,"item_value":int(value),"expected_revision":revision},outcome)

func exercise() -> void:
	await seed_catalog()
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var contained:=false
	for iteration in 100:
		step="independent delivery "+str(iteration)
		if iteration>0:
			if not await request_pause(false):return
			await create_timer(0.3).timeout
			if not await request_pause(true):return
		var sample:=await native("sample");if stopped:return
		if sample.contained:contained=true;break
	if not contained:incomplete("no delivered potash within observation bound",true);return
	var snapshot:=await read_item();if stopped:return
	if not check(snapshot.get("holder",{}).get("id",-1)==int(fixture.building_id),"initial item lost farm holder"):return
	for operation in [Contract.FarmOperation.ItemHidden,Contract.FarmOperation.ItemDump,Contract.FarmOperation.ItemForbid]:
		for value in [true,false]:
			snapshot=await edit_item(operation,value,int(snapshot.revision));if stopped:return
	var retired:=false
	for iteration in 100:
		step="independent job retirement "+str(iteration)
		if not await request_pause(false):return
		await create_timer(0.3).timeout
		if not await request_pause(true):return
		var sample:=await native("sample");if stopped:return
		if not sample.original_job_alive:retired=true;break
	if not retired:incomplete("original job did not retire",true);return
	snapshot=await read_item();if stopped:return
	var prior_revision: int=snapshot.revision
	item_actions=load("res://scripts/semantic_action_service.gd").new();root.add_child(item_actions)
	item_actions.set_process(false);item_actions.configure(world,true)
	item_model=load("res://scripts/item_sheet_state.gd").new();item_model.configure(item_actions)
	item_model.open(int(fixture.item_id))
	if not await settle_controller():return
	if not check(item_model.snapshot.holder.id==int(fixture.building_id),"controller initial holder differs"):return
	await native("independent_transfer");if stopped:return
	item_model.poll(1)
	if not await settle_controller():return
	if not check(item_model.phase==item_model.Phase.Ready and not item_model.snapshot.has("holder") and item_model.snapshot.has("stockpile"),"controller lost item after transfer"):return
	await native("independent_verify",{"snapshot":item_model.view_snapshot(),"revision_text":str(item_model.snapshot.revision)})
	if stopped:return
	snapshot=await read_item();if stopped:return
	if not check(not snapshot.has("holder") and snapshot.has("stockpile") and snapshot.revision!=prior_revision,"transferred item did not replace location authority"):return
	await edit_item(Contract.FarmOperation.ItemHidden,true,prior_revision,Contract.FarmEditOutcome.Stale);if stopped:return
	for value in [true,false]:
		snapshot=await edit_item(Contract.FarmOperation.ItemHidden,value,int(snapshot.revision));if stopped:return
		var repeated:=await edit_item(Contract.FarmOperation.ItemHidden,value,int(snapshot.revision));if stopped:return
		if not check(snapshot==repeated,"repeated desired value changed item receipt"):return
		var old_revision: int=snapshot.revision
		snapshot=await edit_item(Contract.FarmOperation.ItemDump,value,int(snapshot.revision));if stopped:return
		await edit_item(Contract.FarmOperation.ItemHidden,not value,old_revision,Contract.FarmEditOutcome.Stale);if stopped:return
	await edit_item(Contract.FarmOperation.ItemMelt,true,int(snapshot.revision),Contract.FarmEditOutcome.Rejected);if stopped:return
	await ask({"action":Contract.ManagementAction.ProductionInspect,"item_id":2147483647},-1);if stopped:return
	item_model.refresh()
	if not await settle_controller():return
	for value in [true,false]:
		item_model.set_flag(Contract.FarmOperation.ItemHidden,value)
		if not await settle_controller():return
		if not check(item_model.phase==item_model.Phase.Ready and item_model.snapshot.hidden==value,"transferred controller edit failed"):return
		await native("independent_verify",{"snapshot":item_model.view_snapshot(),"revision_text":str(item_model.snapshot.revision)})
		if stopped:return
	write_json("independent-controller-results.json",{"transfer_survived":true,"visibility_both_values":true,"snapshot":item_model.view_snapshot()})
	item_model.dispose();item_actions.free()
	write_json("independent-item-results.json",{"controlled_transfer":true,"snapshot_count":observations.size(),"snapshots":observations})

func request_pause(want_paused: bool) -> bool:
	world.poll()
	var sequence: int=world.send_set_pause(want_paused)
	if not check(sequence>0,"pause command not sent: "+world.last_error()):return false
	# Keep waiting on this exact command through slow initial simulation; no replay.
	var deadline:=Time.get_ticks_msec()+90000
	var accepted:=false;var session: Dictionary={}
	while Time.get_ticks_msec()<deadline:
		world.poll()
		for receipt in world.drain_command_results():
			if int(receipt.seq)==sequence:
				if not check(int(receipt.status)==0 and receipt.message==("paused" if want_paused else "unpaused"),"pause command refused"):return false
				accepted=true
		session=world.poll_session()
		if accepted and session.get("fortress_valid",false) and session.get("paused",not want_paused)==want_paused:return true
		await create_timer(0.02).timeout
	write_json("pause-timeout.json",{"sequence":sequence,"accepted":accepted,"session":session,"requested":want_paused})
	incomplete("pause receipt/readback wait cap hit; no replay",true);return false

func settle_controller() -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();item_actions.poll()
		if item_model.ticket==0:return check(item_model.phase==item_model.Phase.Ready,"independent controller not ready")
		await create_timer(0.01).timeout
	return check(false,"independent controller timed out")
