extends "res://tests/item_carrier_wire_live.gd"

class Interaction:
	extends RefCounted
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=false
	var panel:=Control.new()
	func cancel_selection() -> void:pass
	func set_play_enabled(_enabled: bool) -> void:pass

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)

func composed_sheet(id: int) -> void:
	if not check(DisplayServer.get_name()!="headless" and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Workshop renderer unavailable"):return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var owner=preload("res://scripts/workshop_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
	owner.open_workshop(id,"BUILDING_ICON_WORKSHOP_STILL")
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01)
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready:break
		await create_timer(0.01).timeout
	check(owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready,"Composed workshop did not load all three sources")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-sheet-live.png")
	click(Vector2(752,154))
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/workshop-picker-live.png")
	check(not owner.panel.contents.visible,"Workshop picker retained contents")
	click(Vector2(848,118))
	check(owner.panel.contents.visible and not owner.panel.tasks.picking,"Workshop Cancel did not restore contents")
	owner.close_panel()
	check(owner.state.building_id==-1 and owner.tasks.building_id==-1 and owner.contents.building_id==-1 and host.active==null,"Workshop close retained target authority")
	owner.queue_free();host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame

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
	var header_response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(expected.building_id),"building_header":true})
	var header: Dictionary=header_response.get("production",{}).get("building_header",{}).get("snapshot",{})
	if not check(header_response.get("status")==C.ManagementStatus.Ok and not header.is_empty(),"Workshop header read failed"):quit(1);return
	for field in ["id","type","stage","max_stage","custom_name","native_name"]:
		check(header.get(field)==reference.sheet_reference[field],"Workshop native header differs: "+field)
	check(header.header_name=="Still","Workshop visible title differs")
	var contents_response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(expected.building_id),"contents":true})
	var contents: Dictionary=contents_response.get("production",{}).get("contents",{})
	if not check(contents_response.get("status")==C.ManagementStatus.Ok and not contents.is_empty(),"Workshop contents read failed"):quit(1);return
	check(contents.total==reference.sheet_reference.contents.size(),"Workshop contents count differs")
	for index in contents.rows.size():
		check(contents.rows[index].id==reference.sheet_reference.contents[index].id and contents.rows[index].role==reference.sheet_reference.contents[index].role,"Workshop contents identity/order differs")
	check(before.recipes.size()==reference.task_reference.rows.size(),"Native Still task count differs")
	for i in mini(before.recipes.size(),reference.task_reference.rows.size()):
		var actual: Dictionary=before.recipes[i];var native: Dictionary=reference.task_reference.rows[i]
		check(actual.key==native.key and actual.name==native.name and actual.get("availability",{})==native.availability,"Native Still task order/availability differs")
	for sample in reference.search_reference.cases:
		var searched:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(expected.building_id),"query":sample.query})
		var names: Array=[]
		for row in searched.get("production",{}).get("recipes",[]):names.append(row.name)
		check(searched.get("status")==C.ManagementStatus.Ok and names==sample.names,"Native workshop search differs for "+sample.query)
	var full_query:=String.chr(0x2592).repeat(46)
	var bounded:=await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":int(expected.building_id),"query":full_query})
	check(full_query.to_utf8_buffer().size()==138 and bounded.get("status")==C.ManagementStatus.Ok and bounded.get("production",{}).get("recipes",[]).is_empty(),"Full native-byte query rejected by transport")
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
	await composed_sheet(int(expected.building_id))
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"reaction_count":expected.rows.size(),"task_count":before.recipes.size(),"search_cases":reference.search_reference.cases.size(),"full_query_bytes":full_query.to_utf8_buffer().size(),"created_and_cancelled":created,"rejected_code":unavailable.code,"objection":rejected.get("message")}));file.close()
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)
