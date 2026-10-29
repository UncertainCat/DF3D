extends "res://tests/farm_read_live.gd"

func edit_item(id: int, item: int, operation: int, desired: int, revision: int, outcome: int) -> Dictionary:
	world.poll()
	var seq: int=world.management_request("production",{"action":Contract.ManagementAction.FarmEdit,"building_id":id,"farm_operation":operation,"item_id":item,"item_value":desired,"expected_revision":revision})
	if not check(seq>0,"contents edit not sent: "+world.last_error()):return {}
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var response: Dictionary=world.poll_management()
		if int(response.get("request_seq",0))==seq and response.get("status",S.Idle) not in [S.Idle,S.Pending]:
			if not check(response.status==(S.Ok if outcome==1 else S.Rejected),"contents edit status differs"):return {}
			var production: Dictionary=response.get("production",{})
			if not check(production.get("farm_edit_outcome")==outcome,"contents edit outcome differs"):return {}
			if not check(production.has("contents")==bool(outcome==1) and production.has("contents_edit")==bool(outcome==1) and not production.has("farm"),"unconfirmed contents authority"):return {}
			if outcome==1:
				if not check(production.contents_edit=={"item_id":item,"farm_operation":operation,"value":desired},"contents receipt intent differs"):return {}
			return production.get("contents",{})
		await create_timer(0.01).timeout
	incomplete("contents edit timed out; no replay",true);return {}

func wait_contents_model(model, actions) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if model.phase not in [model.Phase.Reading,model.Phase.Applying]:return check(model.phase==model.Phase.Ready,"contents controller failed: "+str(model.phase))
		await create_timer(0.01).timeout
	incomplete("contents controller timed out; no replay",true);return false

func exercise_controller(id: int, initial: Dictionary) -> void:
	var actions=load("res://scripts/semantic_action_service.gd").new()
	root.add_child(actions);actions.set_process(false);actions.configure(world,true)
	var model=load("res://scripts/building_contents_state.gd").new();model.configure(actions)
	var applied: Array=[];model.applied.connect(func():applied.append(true))
	model.open(id)
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.snapshot==initial,"controller initial page differs"):model.dispose();actions.free();return
	var second:=int(initial.rows[1].id)
	var hidden:=bool(initial.rows[1].hidden)
	model.set_flag(second,Contract.FarmOperation.ItemHidden,not hidden)
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.snapshot.cursor==0 and model.snapshot.rows[1].hidden!=hidden and applied.size()==1,"controller did not recover viewport after later-row edit"):model.dispose();actions.free();return
	await native("contents-verify",{"rows":model.rows()})
	model.set_flag(second,Contract.FarmOperation.ItemHidden,hidden)
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.snapshot==initial,"controller restoration differs"):model.dispose();actions.free();return
	model.seek(1);actions.poll();model.seek(2)
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.snapshot.cursor==2 and model.rows()[0].id==initial.rows[2].id,"late scroll reply replaced latest viewport"):model.dispose();actions.free();return
	model.set_flag(int(model.rows()[0].id),Contract.FarmOperation.ItemHidden,not bool(model.rows()[0].hidden))
	var queued: int=model.ticket;model.close();actions.poll()
	if not check(actions.result(queued).get("outcome")=="not_sent","queued controller edit survived close"):model.dispose();actions.free();return
	model.open(id)
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.snapshot==initial,"queued closed edit changed native state"):model.dispose();actions.free();return
	var first:=int(initial.rows[0].id)
	model.set_flag(first,Contract.FarmOperation.ItemHidden,not bool(initial.rows[0].hidden));actions.poll()
	var sent: int=model.ticket;var before_applied:=applied.size();model.close()
	var deadline:=Time.get_ticks_msec()+30000
	while actions.result(sent).is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll();await create_timer(0.01).timeout
	if not check(actions.result(sent).get("status")==S.Ok and model.snapshot.is_empty() and applied.size()==before_applied,"detached sent edit did not reconcile independently"):model.dispose();actions.free();return
	model.open(id)
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.rows()[0].hidden!=initial.rows[0].hidden,"sent detached effect missing on explicit reopen"):model.dispose();actions.free();return
	model.set_flag(first,Contract.FarmOperation.ItemHidden,bool(initial.rows[0].hidden))
	if not await wait_contents_model(model,actions):model.dispose();actions.free();return
	if not check(model.snapshot==initial,"detached effect not explicitly restored"):model.dispose();actions.free();return
	await native("contents-verify",{"rows":model.rows()})
	write_json("contents-controller-results.json",{"later_row_viewport":true,"latest_scroll":true,"queued_close":"not_sent","sent_close":"detached_completed","restored":true})
	model.dispose();actions.free()

func verify_staged_inspection(id: int, item: int, initial: Dictionary) -> void:
	world.poll()
	var seq: int=world.management_request("production",{"action":Contract.ManagementAction.ProductionInspect,"building_id":id,"item_id":item})
	if not check(seq>0,"item inspection contract rejected locally"):return
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var response: Dictionary=world.poll_management()
		if int(response.get("request_seq",0))==seq and response.get("status",S.Idle) not in [S.Idle,S.Pending]:
			var production: Dictionary=response.get("production",{})
			if not check(response.status==S.Rejected and not production.has("item") and not production.has("contents") and not production.has("farm"),"staged item inspection granted authority"):return
			var observed:=await read_contents(id)
			if stopped:return
			if not check(observed==initial,"staged inspection changed contents"):return
			await native("contents-verify",{"rows":observed.rows})
			write_json("item-inspection-staged.json",{"rejected":true,"no_authority":true,"contents_unchanged":true})
			return
		await create_timer(0.01).timeout
	incomplete("staged inspection timed out",true)

func exercise() -> void:
	await seed_catalog()
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var id:=int(fixture.contents.building_id)
	var initial:=await read_contents(id)
	if stopped:return
	if not check(initial.next_cursor==0 and initial.rows.size()>1,"contents edit fixture requires one complete page"):return
	var item:=int(initial.rows[0].id)
	await verify_staged_inspection(id,item,initial)
	if stopped:return
	var cases: Array=[]
	for probe in [[Contract.FarmOperation.ItemForbid,"forbid"],[Contract.FarmOperation.ItemDump,"dump"],[Contract.FarmOperation.ItemHidden,"hidden"]]:
		step="native contents wire edit "+str(probe[1])
		var original:=int(bool(initial.rows[0][probe[1]]))
		var changed:=await edit_item(id,item,int(probe[0]),1-original,int(initial.revision),1)
		if stopped:return
		if not check(changed.rows[0][probe[1]]==bool(1-original) and changed.revision!=initial.revision,"contents edit had no observed effect"):return
		await native("contents-verify",{"rows":changed.rows})
		if stopped:return
		await edit_item(id,item,int(probe[0]),original,int(initial.revision),3)
		if stopped:return
		var stale_read:=await read_contents(id)
		if stopped:return
		if not check(stale_read==changed,"stale contents edit changed native facts"):return
		var identical:=await edit_item(id,item,int(probe[0]),1-original,int(changed.revision),1)
		if stopped:return
		if not check(identical==changed,"same desired value toggled contents"):return
		var restored:=await edit_item(id,item,int(probe[0]),original,int(identical.revision),1)
		if stopped:return
		if not check(restored==initial,"restored contents receipt differs"):return
		await native("contents-verify",{"rows":restored.rows})
		if stopped:return
		cases.append({"operation":probe[0],"completed":3,"stale":1,"restored":true})
	step="contents receipt for a later row"
	var second:=int(initial.rows[1].id)
	var original_hidden:=int(bool(initial.rows[1].hidden))
	var tail:=await edit_item(id,second,Contract.FarmOperation.ItemHidden,1-original_hidden,int(initial.revision),1)
	if stopped:return
	if not check(tail.cursor==1 and tail.rows[0].id==second and tail.total==initial.total,"item receipt page missed target"):return
	var all_changed:=await read_contents(id)
	if stopped:return
	await native("contents-verify",{"rows":all_changed.rows})
	if stopped:return
	await edit_item(id,second,Contract.FarmOperation.ItemHidden,original_hidden,int(tail.revision),1)
	if stopped:return
	var all_restored:=await read_contents(id)
	if stopped:return
	if not check(all_restored==initial,"later-row edit not restored"):return
	await edit_item(id,item,Contract.FarmOperation.ItemMelt,1,int(initial.revision),2)
	if stopped:return
	await edit_item(id,2147483647,Contract.FarmOperation.ItemHidden,1,int(initial.revision),2)
	if stopped:return
	for invalid in [int(fixture.nonfarm),2147483647]:
		await edit_item(invalid,item,Contract.FarmOperation.ItemHidden,1,int(initial.revision),2)
		if stopped:return
	var final_page:=await read_contents(id)
	if stopped:return
	if not check(final_page==initial,"refused item intents changed native contents"):return
	await native("contents-verify",{"rows":final_page.rows})
	if stopped:return
	await exercise_controller(id,initial)
	if stopped:return
	await native("final")
	write_json("contents-edit-results.json",{"cases":cases,"rejected":4,"restored":true,"later_row_receipt":tail,"initial":initial,"final":final_page})
