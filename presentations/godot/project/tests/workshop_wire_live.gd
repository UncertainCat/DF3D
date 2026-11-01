extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var expected: Dictionary=reference.reaction_reference
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Workshop bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Workshop bootstrap failed"):quit(1);return
	var intent: Dictionary={"action":C.ManagementAction.ProductionInspect,"building_id":int(expected.building_id)}
	var response:=await request("production",intent)
	if not check(response.get("status")==C.ManagementStatus.Ok,"Workshop read failed: "+str(response)):quit(1);return
	var before: Dictionary=response.production
	check(before.recipes.size()==reference.task_reference.rows.size(),"Native Still task count differs")
	for i in mini(before.recipes.size(),reference.task_reference.rows.size()):
		var actual: Dictionary=before.recipes[i];var native: Dictionary=reference.task_reference.rows[i]
		check(actual.key==native.key and actual.name==native.name and actual.get("availability",{})==native.availability,"Native Still task order/availability differs")
	var unavailable: Dictionary={}
	for row in expected.rows:
		var matched:=false
		for recipe in before.recipes:
			if recipe.key=="reaction:"+row.code:
				matched=true;check(recipe.name==row.caption,"Native reaction caption changed in transport")
				check(recipe.get("availability",{})=={"available":row.available,"objection":row.objection},"Native reaction availability changed in transport")
		check(matched,"Native reaction missing from adapter")
		if not row.available and unavailable.is_empty():unavailable=row
	if not check(not unavailable.is_empty(),"Fixture lacks an unavailable reaction"):quit(1);return
	var rejected:=await request("production",{"action":C.ManagementAction.ProductionQueue,"building_id":int(expected.building_id),"recipe":"reaction:"+unavailable.code})
	check(rejected.get("status")==C.ManagementStatus.Rejected and rejected.get("message")==unavailable.objection,"Unavailable task did not retain native objection")
	var after:=await request("production",intent)
	check(after.get("status")==C.ManagementStatus.Ok and after.get("production",{}).get("jobs") == before.jobs,"Rejected task changed queue")
	var added:=await request("production",{"action":C.ManagementAction.ProductionQueue,"building_id":int(expected.building_id),"recipe":"builtin:149:-1"})
	var created: int=added.get("production",{}).get("created_job",-1)
	if not check(added.get("status")==C.ManagementStatus.Ok and created>=0,"Extract task creation failed"):quit(1);return
	var observed:=await request("production",intent)
	var found:=false
	for job in observed.get("production",{}).get("jobs",[]):
		if job.id==created and job.job_type==149 and job.name=="Extract from plants":found=true
	check(found,"Created extraction task missing from authoritative reread")
	var cancelled:=await request("production",{"action":C.ManagementAction.ProductionJobEdit,"building_id":int(expected.building_id),"job_id":created,"cancel":true})
	check(cancelled.get("status")==C.ManagementStatus.Ok,"Extract task cancellation failed")
	var restored:=await request("production",intent)
	check(restored.get("production",{}).get("jobs")==before.jobs,"Queue/cancel failed to restore original jobs")
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"reaction_count":expected.rows.size(),"task_count":before.recipes.size(),"created_and_cancelled":created,"rejected_code":unavailable.code,"objection":rejected.get("message")}));file.close()
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)
