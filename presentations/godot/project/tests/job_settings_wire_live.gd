extends "res://tests/item_carrier_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-job-settings-reference.json"))
	var expected: Dictionary=reference.provider
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Job settings bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var intent: Dictionary={"action":C.ManagementAction.JobSettingsRead,"job_id":int(reference.job_id),"building_id":int(reference.building_id),"unit_id":int(reference.unit_id),"option":-1,"query":"","cursor":0}
	var rows: Array=[]
	for page_index in 256:
		var result:=await request("job_settings",intent)
		var page: Dictionary=result.get("job_settings",{})
		if not check(result.get("status")==C.ManagementStatus.Ok and not page.is_empty(),"Job settings page rejected"):quit(1);return
		check(page.job_id==intent.job_id and page.building_id==intent.building_id and page.unit_id==intent.unit_id,"Job settings reply identity differs")
		check(str(page.revision)==expected.revision and str(page.choices_revision)==expected.choices_revision,"Job settings revisions changed")
		check(page.caption==expected.caption and page.selected_option==int(expected.selected),"Job settings native title/selection differs")
		check(page.cursor==intent.cursor and page.total==expected.materials.size(),"Job settings page extent differs")
		rows.append_array(page.choices)
		if page.next_cursor==0:break
		intent.cursor=int(page.next_cursor)
	check(rows.size()==expected.materials.size(),"Job settings pagination lost choices")
	for i in mini(rows.size(),expected.materials.size()):
		for field in ["id","caption","estimated"]:check(rows[i][field]==expected.materials[i][field],"Job settings choice differs: "+field)
		check(rows[i].get("count_caption")==expected.materials[i].get("count_caption"),"Job settings count caption differs")
	intent.cursor=0;intent.option=0;intent.query="Dolomite"
	var filtered:=await request("job_settings",intent)
	var choices: Array=filtered.get("job_settings",{}).get("choices",[])
	check(choices.size()==1 and choices[0].caption=="Dolomite","Native job material filter failed")
	intent.query=""
	for field in ["job_id","building_id","unit_id"]:
		var stale:=intent.duplicate();stale[field]=2147483647
		var rejected:=await request("job_settings",stale)
		check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("job_settings"),"Stale job setting retained choices: "+field)
	var unrelated:=await request("construction",{"action":C.ManagementAction.Catalog})
	check(not unrelated.has("job_settings"),"Unrelated reply retained job settings")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"choices":rows.size(),"filtered":choices}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
