extends "res://tests/areas_acceptance_live.gd"

func read_farm(id: int, season: int, rejected := false) -> Dictionary:
	world.poll()
	var seq: int=world.management_request("production",{"action":Contract.ManagementAction.ProductionInspect,"building_id":id,"season":season})
	if not check(seq>0,"farm read not sent: "+world.last_error()):return {}
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var response: Dictionary=world.poll_management()
		if int(response.get("request_seq",0))==seq and response.get("status",S.Idle) not in [S.Idle,S.Pending]:
			if not check(response.status==(S.Rejected if rejected else S.Ok),"farm read status differs"):return {}
			return response.get("production",{}).get("farm",{})
		await create_timer(0.01).timeout
	incomplete("farm read timed out; no replay",true);return {}

func read_contents(id: int, cursor := 0, revision := 0, rejected := false) -> Dictionary:
	world.poll()
	var seq: int=world.management_request("production",{"action":Contract.ManagementAction.ProductionInspect,"building_id":id,"contents":true,"cursor":cursor,"expected_revision":revision})
	if not check(seq>0,"contents read not sent: "+world.last_error()):return {}
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var response: Dictionary=world.poll_management()
		if int(response.get("request_seq",0))==seq and response.get("status",S.Idle) not in [S.Idle,S.Pending]:
			if not check(response.status==(S.Rejected if rejected else S.Ok),"contents read status differs"):return {}
			return response.get("production",{}).get("contents",{})
		await create_timer(0.01).timeout
	incomplete("contents read timed out; no replay",true);return {}

func exercise_contents() -> void:
	var expected: Dictionary=fixture.contents
	var page:=await read_contents(int(expected.building_id))
	if stopped:return
	if not check(page.revision==int(expected.revision) and page.total==expected.rows.size(),"contents revision/count differs"):return
	var all_rows: Array=page.rows.duplicate()
	var next: int=page.next_cursor
	while next>0:
		var tail:=await read_contents(int(expected.building_id),next,int(page.revision))
		if stopped:return
		if not check(tail.cursor==next and tail.revision==page.revision,"contents continuation identity differs"):return
		all_rows.append_array(tail.rows);next=tail.next_cursor
	if not check(all_rows.size()==expected.rows.size(),"contents rows lost"):return
	for index in all_rows.size():
		var row: Dictionary=all_rows[index]
		var original: Dictionary=expected.rows[index]
		if not check(row.id==int(original.id) and row.role==int(original.role_value) and row.name==original.name,"contents order/caption differs"):return
		for key in ["forbid","dump","melt","hidden","can_dump","can_melt","in_job","in_building"]:
			if not check(row[key]==original[key],"contents semantic flag differs: "+key):return
	var tail:=await read_contents(int(expected.building_id),1,int(page.revision))
	if stopped:return
	if not check(tail.cursor==1 and tail.rows[0].id==all_rows[1].id,"contents offset ignored"):return
	await native("contents-change")
	if stopped:return
	var stale:=await read_contents(int(expected.building_id),1,int(page.revision),true)
	if stopped:return
	if not check(stale.is_empty(),"stale continuation retained authority"):return
	await native("contents-restore")
	if stopped:return
	var restored:=await read_contents(int(expected.building_id))
	if stopped:return
	if not check(restored==page,"restored contents receipt differs"):return
	write_json("contents-read-results.json",{"page":page,"row_count":all_rows.size(),"stale_rejected":true,"restored":true})

func exercise() -> void:
	await seed_catalog()
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var observed: Dictionary={}
	for season in [0,1,2,3,3,1,0,2]:
		step="native farm season "+str(season)
		var farm:=await read_farm(int(fixture.id),season)
		if stopped:return
		if not check(farm.get("building_id")==int(fixture.id) and farm.get("selected_season")==season and farm.get("current_season")==int(fixture.current_season),"farm identity differs"):return
		if not check(typeof(farm.revision)==TYPE_INT and farm.revision>0,"missing exact farm revision"):return
		var selected: Array=[]
		for crop in fixture.seasons:selected.append(int(crop))
		if not check(farm.seasonal_crops==selected,"seasonal selections differ"):return
		var expected: Array=[]
		for row in fixture.choices[season]:
			expected.append({"id":int(row.crop_id),"name":row.name,"raw_id":row.raw_id,"seeds_available":row.seeds_available,"current_season_warning":row.current_season_warning})
		if not check(farm.custom_name==fixture.header.custom_name and farm.header_name==fixture.header.header_name and farm.removing==fixture.header.removing and farm.removal_suspended==fixture.header.suspended and farm.removal_has_worker==fixture.header.has_worker,"header facts differ"):return
		if not check(farm.choices==expected,"native choice order/name/flags differ"):return
		if observed.has(season) and not check(farm==observed[season],"farm read depends on tab request history"):return
		observed[season]=farm
	step="farm content revision"
	var change:=await native("change")
	if stopped:return
	var changed:=await read_farm(int(fixture.id),1)
	if stopped:return
	if not check(changed.revision!=observed[1].revision and changed.seasonal_crops[0]==int(change.crop),"changed selection retained stale revision"):return
	await native("restore")
	if stopped:return
	var restored:=await read_farm(int(fixture.id),1)
	if stopped:return
	if not check(restored==observed[1],"restored farm content did not recover its revision"):return
	step="farm header revision"
	var header_change:=await native("header-change")
	if stopped:return
	var renamed:=await read_farm(int(fixture.id),1)
	if stopped:return
	if not check(renamed.revision!=restored.revision and renamed.custom_name==header_change.header.custom_name and renamed.header_name==header_change.header.header_name,"name change retained stale revision"):return
	await native("header-restore")
	if stopped:return
	var header_restored:=await read_farm(int(fixture.id),1)
	if stopped:return
	if not check(header_restored==restored,"name restoration did not restore receipt"):return
	step="invalid farm targets"
	for id in [int(fixture.nonfarm),2147483647]:
		var absent:=await read_farm(id,0,true)
		if stopped:return
		if not check(absent.is_empty(),"rejected target retained farm authority"):return
	await exercise_contents()
	if stopped:return
	await native("final")
	write_json("farm-read-results.json",{"snapshots":observed,"read_count":12,"renamed_header":renamed,"rejected_targets":2,"changed_revision":changed.revision,"restored_revision":restored.revision})
