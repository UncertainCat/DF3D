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
	var published:=await request("residents_rows",{"action":C.ManagementAction.ResidentsRowsRead,"unit_ids":PackedInt32Array([int(reference.unit_id)]),"columns":30,"show_gender":false})
	var published_rows: Array=published.get("residents_rows",{}).get("rows",[])
	check(published_rows.size()==1 and published_rows[0].get("job_target",{}).get("job_id")==int(reference.job_id) and published_rows[0].get("job_target",{}).get("building_id")==int(reference.building_id),"Resident row lost native job button target")
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
	var composed:=await composed_read(reference)
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"choices":rows.size(),"filtered":choices,"composed":composed}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func ready(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and state.phase==state.Phase.Reading:
		world.poll();await create_timer(0.01).timeout
	return state.phase==state.Phase.Ready

func composed_read(reference: Dictionary) -> Dictionary:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Job settings assets unavailable"):return {}
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var state=preload("res://scripts/job_settings_state.gd").new();state.configure(service)
	var view=preload("res://scripts/work_order_details_view.gd").new();view.job_context=true;root.add_child(view);view.configure_details(world,state)
	view.cancelled.connect(state.close)
	state.open(int(reference.building_id),int(reference.job_id),int(reference.unit_id));view.show();view.layout(Vector2(1200,800))
	var opened:=await ready(state)
	check(opened and state.rows.size()==reference.provider.materials.size(),"Composed job settings pagination failed")
	var count: int=state.rows.size()
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=view.position+Vector2(120,180);wheel.global_position=wheel.position
	Input.parse_input_event(wheel);await process_frame
	check(state.first==1,"Job settings wheel did not scroll")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=view.position+Vector2(120,100);click.global_position=click.position
	Input.parse_input_event(click);await process_frame
	click=click.duplicate();click.pressed=false;Input.parse_input_event(click);await process_frame
	for character in "Dolomite":
		var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);Input.parse_input_event(key)
		await process_frame
	var filtered:=await ready(state)
	check(filtered and state.query=="Dolomite" and state.rows.size()==1 and state.rows[0].caption=="Dolomite","Composed native job filter failed")
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;Input.parse_input_event(escape);await process_frame
	check(state.phase==state.Phase.Closed and not view.visible,"Job settings Escape did not retire the page")
	state.dispose();view.queue_free();service.queue_free();await process_frame
	return {"choices":count,"filtered":filtered,"closed":state.phase==state.Phase.Closed}
