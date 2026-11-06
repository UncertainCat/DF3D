extends "res://tests/item_carrier_wire_live.gd"
class Interaction extends Node:
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=true
	var panel:=Control.new()
	func _ready() -> void:add_child(panel)
	func cancel_selection() -> void:pass
	func set_play_enabled(_value: bool) -> void:pass
func pointer(view,point: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
	var click:=InputEventMouseButton.new();click.button_index=button;click.pressed=true
	click.position=view.get_global_transform_with_canvas()*point;click.global_position=click.position
	Input.parse_input_event(click);await process_frame
	click=click.duplicate();click.pressed=false;Input.parse_input_event(click);await process_frame
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-job-settings-reference.json"))
	var expected: Dictionary=reference.provider
	var choice_caption: String=expected.materials[1].caption
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
		if expected.has("current_value"):check(page.get("current_value")==expected.current_value,"Job settings current size caption differs")
		check(page.cursor==intent.cursor and page.total==expected.materials.size(),"Job settings page extent differs")
		rows.append_array(page.choices)
		if page.next_cursor==0:break
		intent.cursor=int(page.next_cursor)
	check(rows.size()==expected.materials.size(),"Job settings pagination lost choices")
	for i in mini(rows.size(),expected.materials.size()):
		for field in ["id","caption","estimated"]:check(rows[i][field]==expected.materials[i][field],"Job settings choice differs: "+field)
		check(rows[i].get("count_caption")==expected.materials[i].get("count_caption"),"Job settings count caption differs")
	intent.cursor=0;intent.option=0;intent.query=choice_caption
	var filtered:=await request("job_settings",intent)
	var choices: Array=filtered.get("job_settings",{}).get("choices",[])
	check(choices.size()==1 and choices[0].caption==choice_caption,"Native job material filter failed")
	intent.query=""
	for field in ["job_id","building_id","unit_id"]:
		var stale:=intent.duplicate();stale[field]=2147483647
		var rejected:=await request("job_settings",stale)
		check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("job_settings"),"Stale job setting retained choices: "+field)
	var edit_intent: Dictionary={"action":C.ManagementAction.JobSettingsApply,"job_id":int(reference.job_id),"building_id":int(reference.building_id),"unit_id":int(reference.unit_id),"option":0,"expected_revision":int(expected.revision),"expected_choices_revision":int(expected.choices_revision),"choice":1}
	for field in ["job_id","building_id","unit_id","expected_revision","expected_choices_revision"]:
		var stale:=edit_intent.duplicate();stale[field]=2147483647
		var rejected:=await request("job_settings",stale)
		check(rejected.get("status")==C.ManagementStatus.Rejected and rejected.get("job_settings_edit",{}).get("outcome")==C.JobSettingsEditOutcome.Stale,"Stale job edit not rejected: "+field)
	var unchanged:=await request("job_settings",intent)
	check(str(unchanged.get("job_settings",{}).get("revision"))==expected.revision,"Rejected edits changed the job")
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
	var choice_caption: String=reference.provider.materials[1].caption
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Job settings assets unavailable"):return {}
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/residents_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	if not check(await ready(owner.state),"Residents owner did not load roster"):
		owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame;return {}
	var row_index: int=owner.state.ids.find(int(reference.unit_id))
	if not check(row_index>=0,"Job resident absent from native roster"):
		owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame;return {}
	owner.state.seek(row_index,owner.state.capacity)
	check(await ready(owner.state),"Job resident row did not load")
	var roster_first: int=owner.state.first
	var roster_order: PackedInt32Array=owner.state.ids.duplicate()
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(row_index-roster_first)*36+18))
	var state=owner.job_state
	var view=owner.job_panel
	var opened:=await ready(state)
	check(opened and state.rows.size()==reference.provider.materials.size(),"Composed job settings pagination failed")
	check(host.active==owner and interaction.construction_active and view.visible and not owner.panel.visible,"Job entry lost modal ownership")
	check(state.unit_id==int(reference.unit_id) and state.job_id==int(reference.job_id),"Job button opened another resident job")
	var count: int=state.rows.size()
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=view.position+Vector2(120,180);wheel.global_position=wheel.position
	Input.parse_input_event(wheel);await process_frame
	check(state.first==1,"Job settings wheel did not scroll")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=view.position+Vector2(120,100);click.global_position=click.position
	Input.parse_input_event(click);await process_frame
	click=click.duplicate();click.pressed=false;Input.parse_input_event(click);await process_frame
	for character in choice_caption:
		var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);Input.parse_input_event(key)
		await process_frame
	var filtered:=await ready(state)
	check(filtered and state.query==choice_caption and state.rows.size()==1 and state.rows[0].caption==choice_caption,"Composed native job filter failed")
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;Input.parse_input_event(escape);await process_frame
	check(state.phase==state.Phase.Closed and not view.visible,"Job settings Escape did not retire the page")
	var returned: bool=owner.panel.visible and host.active==owner and owner.state.first==roster_first and owner.state.ids==roster_order
	check(returned,"Job Escape failed to restore the same roster")
	# Reopen through the visible row, then dismiss the entire owner while reading.
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(row_index-roster_first)*36+18))
	host.reset_local_views()
	for frame in 5:world.poll();await process_frame
	check(not owner.job_open() and not owner.panel.visible and not view.visible and host.active==null and not interaction.construction_active,"Owner reset retained job details or world-input lock")
	# Submit the actual material choice through the assembled owner after the
	# read/navigation checks. The native oracle verifies the final job fields.
	owner.open_panel();check(await ready(owner.state),"Reopen roster for material edit failed")
	row_index=owner.state.ids.find(int(reference.unit_id));owner.state.seek(row_index,owner.state.capacity)
	check(await ready(owner.state),"Material edit row load failed")
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(row_index-owner.state.first)*36+18))
	check(await ready(state),"Material edit Details load failed")
	check(state.rows.size()>1 and state.rows[1].caption==choice_caption,"Material edit choice changed")
	await pointer(view,Vector2(120,view.list_top()+36+18))
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and state.phase==state.Phase.Applying:
		world.poll();await create_timer(0.01).timeout
	check(state.phase==state.Phase.Closed and await ready(owner.state) and owner.panel.visible,"Confirmed material edit did not return to refreshed roster")
	var edited: bool=state.phase==state.Phase.Closed
	var closed: bool=state.phase==state.Phase.Closed
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame
	return {"choices":count,"filtered":filtered,"closed":closed,"returned_to_roster":returned,"resident_id":int(reference.unit_id),"material_applied":edited}
