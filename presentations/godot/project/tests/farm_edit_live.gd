extends "res://tests/farm_read_live.gd"

func edit_crop(id: int, season: int, crop: int, revision: int, outcome: int, operation := 0, seasonal := -1, farm_name := "") -> Dictionary:
	world.poll()
	var request: Dictionary={"action":Contract.ManagementAction.FarmEdit,"building_id":id,"season":season,"expected_revision":revision,"farm_operation":operation}
	if operation==0:request.crop_id=crop
	if operation==2:request.seasonal_fertilization=seasonal
	if operation==3:request.farm_name=farm_name
	var seq: int=world.management_request("production",request)
	if not check(seq>0,"farm edit not sent: "+world.last_error()):return {}
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var response: Dictionary=world.poll_management()
		if int(response.get("request_seq",0))==seq and response.get("status",S.Idle) not in [S.Idle,S.Pending]:
			if not check(response.status==(S.Ok if outcome==1 else S.Rejected),"farm edit status differs"):return {}
			var production: Dictionary=response.get("production",{})
			if not check(production.get("farm_edit_outcome")==outcome,"farm edit outcome differs"):return {}
			if not check(production.has("farm")==(outcome==1),"unconfirmed farm authority"):return {}
			return production.get("farm",{})
		await create_timer(0.01).timeout
	incomplete("farm edit timed out; no replay",true);return {}

func exercise() -> void:
	await seed_catalog()
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var id:=int(fixture.id)
	var seasons: Array=[]
	for crop in fixture.seasons:seasons.append(int(crop))
	var results: Array=[]
	# Future-season effects avoid time-dependent current-season eligibility.
	for season in 4:
		if season==int(fixture.current_season):continue
		step="farm wire crop edit "+str(season)
		var before:=await read_farm(id,season)
		if stopped:return
		var target: int=-1
		if seasons[season]<0:
			if not check(not before.choices.is_empty(),"fixture lacks eligible future crop"):return
			target=int(before.choices[0].id)
		var after:=await edit_crop(id,season,target,before.revision,1)
		if stopped:return
		seasons[season]=target
		if not check(after.seasonal_crops==seasons and after.revision!=before.revision,"completed crop receipt differs"):return
		await native("verify",{"seasons":seasons})
		if stopped:return
		await edit_crop(id,season,int(fixture.seasons[season]),before.revision,3)
		if stopped:return
		await native("verify",{"seasons":seasons})
		if stopped:return
		var same:=await edit_crop(id,season,target,after.revision,1)
		if stopped:return
		if not check(same==after,"same crop changed content"):return
		await edit_crop(id,season,32767,same.revision,2)
		if stopped:return
		await native("verify",{"seasons":seasons})
		if stopped:return
		var restored:=await edit_crop(id,season,int(fixture.seasons[season]),same.revision,1)
		if stopped:return
		seasons[season]=int(fixture.seasons[season])
		if not check(restored==before,"restored receipt differs"):return
		await native("verify",{"seasons":seasons})
		if stopped:return
		results.append({"season":season,"completed":3,"stale":1,"rejected":1})
	step="native fertilizer wire edits"
	var initial:=await read_farm(id,1)
	if stopped:return
	if not check(initial.pending_fertilization==0 and initial.current_fertilization==0 and initial.max_fertilization==29 and initial.seasonal_fertilization,"unexpected fertilizer fixture"):return
	var off:=await edit_crop(id,1,-1,initial.revision,1,2,0)
	if stopped:return
	if not check(not off.seasonal_fertilization and off.revision!=initial.revision,"seasonal edit retained old facts"):return
	await native("verify",{"seasons":seasons,"fertilization":off})
	if stopped:return
	await edit_crop(id,1,-1,initial.revision,3,2,1)
	if stopped:return
	await native("verify",{"seasons":seasons,"fertilization":off})
	if stopped:return
	var same_off:=await edit_crop(id,1,-1,off.revision,1,2,0)
	if stopped:return
	if not check(same_off==off,"same seasonal intent changed receipt"):return
	var restored_on:=await edit_crop(id,1,-1,off.revision,1,2,1)
	if stopped:return
	if not check(restored_on==initial,"seasonal restoration differs"):return
	var queued:=await edit_crop(id,1,-1,initial.revision,1,1)
	if stopped:return
	if not check(queued.pending_fertilization==29 and queued.revision!=initial.revision,"fertilizer toggle did not queue native jobs"):return
	await native("verify",{"seasons":seasons,"fertilization":queued})
	if stopped:return
	await edit_crop(id,1,-1,initial.revision,3,1)
	if stopped:return
	await native("verify",{"seasons":seasons,"fertilization":queued})
	if stopped:return
	var canceled:=await edit_crop(id,1,-1,queued.revision,1,1)
	if stopped:return
	if not check(canceled==initial,"fertilizer cancellation did not restore receipt"):return
	await native("verify",{"seasons":seasons,"fertilization":canceled})
	if stopped:return
	step="native farm rename wire edits"
	var rename_receipt: Dictionary=initial
	var rename_cases: Array=[]
	for name in ["lower farm","x".repeat(30),"Caf"+String.chr(233),""]:
		var previous: Dictionary=rename_receipt
		rename_receipt=await edit_crop(id,1,-1,previous.revision,1,3,-1,name)
		if stopped:return
		if not check(rename_receipt.custom_name==name and rename_receipt.revision!=previous.revision,"rename receipt differs"):return
		var native_header:=await native("verify",{"seasons":seasons,"fertilization":rename_receipt,"name":name})
		if stopped:return
		if not check(native_header.header.header_name==rename_receipt.header_name,"native formatted rename caption differs"):return
		var same_name:=await edit_crop(id,1,-1,rename_receipt.revision,1,3,-1,name)
		if stopped:return
		if not check(same_name==rename_receipt,"identical name changed receipt"):return
		await edit_crop(id,1,-1,previous.revision,3,3,-1,"stale")
		if stopped:return
		await native("verify",{"seasons":seasons,"name":name})
		if stopped:return
		rename_cases.append({"name":name,"header_name":rename_receipt.header_name,"identical_unchanged":true,"stale_refused":true})
	if not check(rename_receipt==initial,"rename restoration did not recover original receipt"):return
	for invalid_name in ["x".repeat(31),String.chr(0x1f600)]:
		await edit_crop(id,1,-1,rename_receipt.revision,2,3,-1,invalid_name)
		if stopped:return
		await native("verify",{"seasons":seasons,"name":initial.custom_name})
		if stopped:return
	for invalid in [int(fixture.nonfarm),2147483647]:
		await edit_crop(invalid,0,-1,17,2)
		if stopped:return
	await native("mark_removal",{"seasons":seasons,"name":initial.custom_name})
	if stopped:return
	var removing:=await read_farm(id,1)
	if stopped:return
	if not check(removing.removing,"wire removal flag missing"):return
	for operation in 4:
		await edit_crop(id,1,-1,removing.revision,2,operation,0 if operation==2 else -1,"blocked")
		if stopped:return
		var unchanged:=await read_farm(id,1)
		if stopped:return
		if not check(unchanged==removing,"refused edit changed removing farm"):return
	await native("clear_removal",{"seasons":seasons,"name":initial.custom_name})
	if stopped:return
	var final_receipt:=await read_farm(id,1)
	if stopped:return
	if not check(final_receipt==initial,"removal fixture did not restore receipt"):return
	step="native removal commands"
	for fertilized in [false,true]:
		var before_remove: Dictionary=final_receipt
		if fertilized:before_remove=await edit_crop(id,1,-1,before_remove.revision,1,1)
		if stopped:return
		var removed:=await edit_crop(id,1,-1,before_remove.revision,1,4)
		if stopped:return
		if not check(removed.removing,"remove command did not mark farm"):return
		await native("verify",{"seasons":seasons,"removing":true,"fertilization":removed})
		await edit_crop(id,1,-1,before_remove.revision,3,5)
		if stopped:return
		final_receipt=await edit_crop(id,1,-1,removed.revision,1,5)
		if stopped:return
		if not check(final_receipt==initial,"native cancellation did not restore farm receipt"):return
		await native("verify",{"seasons":seasons,"removing":false,"fertilization":final_receipt})
		await edit_crop(id,1,-1,final_receipt.revision,2,5)
		if stopped:return
	await native("verify",{"seasons":seasons})
	if stopped:return
	write_json("farm-edit-results.json",{"cases":results,"invalid_targets":2,"original_selections_restored":true,"fertilizer_completed":5,"fertilizer_stale":2,"fertilizer_original_restored":true,"rename_cases":rename_cases,"rename_invalid":2,"rename_original_restored":true,"removal_refusals":4})
