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

func exercise() -> void:
	await seed_catalog()
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var id:=int(fixture.contents.building_id)
	var initial:=await read_contents(id)
	if stopped:return
	if not check(initial.next_cursor==0 and initial.rows.size()>1,"contents edit fixture requires one complete page"):return
	var item:=int(initial.rows[0].id)
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
	await native("final")
	write_json("contents-edit-results.json",{"cases":cases,"rejected":4,"restored":true,"later_row_receipt":tail,"initial":initial,"final":final_page})
