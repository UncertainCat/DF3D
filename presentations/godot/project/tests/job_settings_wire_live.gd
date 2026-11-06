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
	if OS.get_environment("DF3D_WORK_DETAILS_ROWS_WIRE")=="1":
		await work_detail_rows();return
	if OS.get_environment("DF3D_WORK_DETAILS_QUERY_WIRE")=="1":
		await work_detail_query();return
	if OS.get_environment("DF3D_WORK_DETAILS_DEFAULTS")=="1" or OS.get_environment("DF3D_WORK_DETAILS_MEMBERSHIP")=="1" or OS.get_environment("DF3D_WORK_DETAILS_EDITS")=="1":
		await work_detail_defaults();return
	if OS.get_environment("DF3D_RESIDENTS_JOB_PRODUCTION_WIRE")=="1":
		await production_read();return
	if OS.get_environment("DF3D_RESIDENTS_JOB_ART_WIRE")=="1":
		await artwork_read();return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-job-settings-reference.json"))
	var expected: Dictionary=reference.provider
	var choice_caption: String=expected.materials[1].caption
	var searchable: bool=int(expected.options[int(expected.selected)].kind)!=3
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
	intent.cursor=0;intent.option=0;intent.query=choice_caption if searchable else ""
	var filtered:=await request("job_settings",intent)
	var choices: Array=filtered.get("job_settings",{}).get("choices",[])
	check((choices.size()==1 and choices[0].caption==choice_caption) if searchable else choices.size()==expected.materials.size(),"Native job choices/filter failed")
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

func work_detail_rows() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Work Details rows attach failed"):quit(1);return
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var state=preload("res://scripts/work_details_state.gd").new();state.configure(service);state.open()
	if not check(await ready(state),"Work Details rows owner failed"):quit(1);return
	var rows: Array=[]
	for index in reference.worker_skill_rows.size():
		var expected: Dictionary=reference.worker_skill_rows[index]
		var row: Dictionary=state.row_at(index)
		if not check(row.get("id")==int(expected.unit_id),"Worker row identity/order differs"):break
		var captions: Array=[]
		for skill in row.skills:captions.append(skill.caption)
		check(captions==expected.native and row.member==expected.member,"Worker skill list or membership differs")
		check(not row.first_line.is_empty() and row.has("sheet_icon") and row.has("assignments") and int(row.specialization.revision)>0,"Shared worker row observations missing")
		check(not row.has("happiness") and not row.has("activity_target") and row.activity.caption.is_empty(),"Work Details row invented Residents observations")
		rows.append({"id":row.id,"skills":row.skills,"member":row.member,"first_line":row.first_line,"second_line":row.second_line})
	var revision: int=state.selected.revision
	state.close();state.dispose();service.queue_free();await process_frame
	var intent: Dictionary={"action":C.ManagementAction.WorkDetailRowsRead,"detail_index":0,"expected_revision":revision,"unit_ids":PackedInt32Array([int(reference.worker_skill_rows[0].unit_id)]),"columns":30,"show_gender":false}
	for patch in [{"detail_index":-1},{"expected_revision":0},{"expected_revision":1.0},{"unit_ids":[7]},{"columns":31},{"extra":true}]:
		var invalid:=intent.duplicate(true);invalid.merge(patch,true);check(world.management_request("work_detail_rows",invalid)==0,"Invalid worker row request was sent")
	intent.expected_revision=revision^1
	var rejected:=await request("work_detail_rows",intent)
	check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("residents_rows"),"Stale worker content retained rows")
	intent.expected_revision=revision;intent.unit_ids=PackedInt32Array([2147483647])
	rejected=await request("work_detail_rows",intent)
	check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("residents_rows"),"Missing worker retained rows")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"rows":rows,"revision":str(revision),"stale_rejected":true,"missing_rejected":true}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_query() -> void:
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Work Details query attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var inspected:=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":0})
	var rows: Array=inspected.get("citizen",{}).get("details",[])
	if not check(rows.size()==1,"Query detail missing"):quit(1);return
	var revision: int=rows[0].revision
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	var captures: Array=[]
	for query in reference.queries:
		var intent: Dictionary={"action":C.ManagementAction.WorkDetailWorkersQuery,"detail_index":0,"expected_revision":revision,"sort":int(query.sort),"descending":bool(query.direction),"query_bytes":str(query.query).to_utf8_buffer()}
		var response:=await request("work_detail_workers",intent)
		var ids: PackedInt32Array=response.get("residents",{}).get("unit_ids",PackedInt32Array())
		check(response.get("status")==C.ManagementStatus.Ok and ids==PackedInt32Array(query.native),"Work Details native query differs: "+query.name)
		captures.append({"name":query.name,"ids":Array(ids)})
		if failed:break
	var stale: Dictionary={"action":C.ManagementAction.WorkDetailWorkersQuery,"detail_index":0,"expected_revision":revision^1,"sort":3,"descending":false,"query_bytes":PackedByteArray()}
	# Keep the malformed-revision test inside the supported positive domain.
	if stale.expected_revision==0:stale.expected_revision=2
	var rejected:=await request("work_detail_workers",stale)
	check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("residents"),"Stale Work Detail retained worker rows")
	stale.detail_index=127;stale.expected_revision=revision
	rejected=await request("work_detail_workers",stale)
	check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("residents"),"Missing Work Detail retained worker rows")
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var state=preload("res://scripts/work_details_state.gd").new();state.configure(service);state.open()
	check(await ready(state),"Work Details owner did not open")
	var owner_queries: Array=[]
	for query in reference.queries:
		if failed:break
		if state.sort!=int(query.sort) or state.directions[state.sort]!=bool(query.direction):state.select_sort(int(query.sort))
		state.set_query(str(query.query).to_utf8_buffer())
		check(await ready(state) and state.ids==PackedInt32Array(query.native),"Work Details owner query differs: "+query.name)
		owner_queries.append({"name":query.name,"ids":Array(state.ids)})
	check(state.details.size()==reference.details.size() and state.selected.index==0,"Work Details owner list differs")
	state.close();state.dispose();service.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"revision":str(revision),"queries":captures,"owner_queries":owner_queries,"stale_rejected":not rejected.has("residents")}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_defaults() -> void:
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Work Details defaults attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var response: Dictionary
	if OS.get_environment("DF3D_WORK_DETAILS_EDITS")=="1":
		var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json")).edits
		var index:=int(reference.index)
		response=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":index})
		var rows: Array=response.get("citizen",{}).get("details",[])
		if not check(rows.size()==1,"Edit detail missing"):quit(1);return
		var intent: Dictionary={"detail_index":index,"expected_revision":int(rows[0].revision)}
		if int(reference.step)==4:
			intent.merge({"action":C.ManagementAction.WorkDetailEdit,"edit":3})
		else:
			intent.merge({"action":C.ManagementAction.WorkDetailMode,"mode":int(reference.modes[int(reference.step)-1].mode)})
		response=await request("citizens",intent)
	elif OS.get_environment("DF3D_WORK_DETAILS_MEMBERSHIP")=="1":
		var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
		response=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":0})
		var rows: Array=response.get("citizen",{}).get("details",[])
		if not check(rows.size()==1,"Membership detail missing"):quit(1);return
		response=await request("citizens",{"action":C.ManagementAction.WorkDetailMembership,"detail_index":0,"unit_id":int(reference.membership.unit_id),"member":0,"expected_revision":int(rows[0].revision)})
	else:
		response=await request("citizens",{"action":C.ManagementAction.WorkDetailList,"cursor":0,"expected_list_revision":0})
		var revision: int=response.get("citizen",{}).get("detail_list_revision",0)
		if not check(revision>0,"Work Details list receipt missing"):quit(1);return
		response=await request("citizens",{"action":C.ManagementAction.WorkDetailCreate,"expected_revision":revision})
	check(response.get("status")==C.ManagementStatus.Ok,"Work Details edit failed")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"work_detail":response.get("citizen",{})}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func production_read() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-job-production-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Production bridge/assets unavailable"):quit(1);return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/residents_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	check(await ready(owner.state),"Production roster failed")
	var index: int=owner.state.ids.find(int(reference.unit_id));owner.state.seek(index,owner.state.capacity);check(await ready(owner.state),"Production resident row failed")
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-owner.state.first)*36+18))
	var state=owner.job_state;var view=owner.job_panel
	check(await ready(state) and state.selected==-1 and state.snapshot.get("options",[]).size()==2,"Production Details root failed")
	await capture_draft("production-root")
	await pointer(view,Vector2(120,66));check(await ready(state) and state.selected==0 and state.rows.size()==83,"Production material option failed")
	var expected: Array=reference.pages[0].provider.materials
	for i in mini(expected.size(),state.rows.size()):check(state.rows[i].caption==expected[i].caption and state.rows[i].get("count_caption")==expected[i].get("count_caption"),"Production material choices differ")
	await capture_draft("production-materials")
	await pointer(view,Vector2(120,180),MOUSE_BUTTON_RIGHT);check(await ready(state) and state.selected==-1,"Production material Back failed")
	await pointer(view,Vector2(120,102));check(await ready(state) and state.has_art() and state.art_page()==-1,"Production image option failed")
	await capture_draft("production-image")
	await pointer(view,Vector2(120,180),MOUSE_BUTTON_RIGHT)
	check(state.phase==state.Phase.Closed and owner.panel.visible,"Production image Back did not restore Residents")
	if OS.get_environment("DF3D_RESIDENTS_JOB_PRODUCTION_EDIT")=="1":
		await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-owner.state.first)*36+18));check(await ready(state),"Production edit reopen failed")
		await pointer(view,Vector2(120,66));check(await ready(state) and state.selected==0,"Production edit material option failed")
		await pointer(view,Vector2(120,view.list_top()+54));await production_applied(owner)
		await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-owner.state.first)*36+18));check(await ready(state),"Production artwork reopen failed")
		await pointer(view,Vector2(120,102));check(await ready(state) and state.has_art(),"Production artwork edit entry failed")
		await pointer(view,Vector2(120,114));check(await ready(state) and state.art_page()==1 and state.rows[0].id==int(reference.native_figure),"Production artwork figure differs")
		await pointer(view,Vector2(120,view.list_top()+18));await production_applied(owner)
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"production":{"source_job":reference.source_job_id,"options":2,"materials":expected.size(),"image":true,"back":true}}));file.close()
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

func production_applied(owner) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while owner.job_state.phase==owner.job_state.Phase.Applying and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
	check(owner.job_state.phase==owner.job_state.Phase.Closed and await ready(owner.state) and owner.panel.visible,"Production edit did not refresh Residents")

func ready(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and state.phase in [state.Phase.Reading,state.Phase.Applying]:
		world.poll();await create_timer(0.01).timeout
	return state.phase==state.Phase.Ready

func composed_read(reference: Dictionary) -> Dictionary:
	var choice_caption: String=reference.provider.materials[1].caption
	var searchable: bool=int(reference.provider.options[int(reference.provider.selected)].kind)!=3
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
	check(state.first==(1 if count>state.visible_rows else 0),"Job settings wheel did not match visible list extent")
	var filtered:=false
	if searchable:
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=view.position+Vector2(120,100);click.global_position=click.position
		Input.parse_input_event(click);await process_frame
		click=click.duplicate();click.pressed=false;Input.parse_input_event(click);await process_frame
		for character in choice_caption:
			var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);Input.parse_input_event(key)
			await process_frame
		filtered=await ready(state)
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
	return {"choices":count,"filtered":filtered,"closed":closed,"returned_to_roster":returned,"resident_id":int(reference.unit_id),"material_applied":edited,"filter_supported":searchable}

func artwork_read() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-job-art-reference.json"))
	var fixture_path:=ProjectSettings.globalize_path("res://../../../fixtures/residents/native_job_settings.json")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Job artwork bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var intent: Dictionary={"action":C.ManagementAction.JobSettingsRead,"job_id":int(reference.job_id),"building_id":int(reference.building_id),"unit_id":int(reference.unit_id),"option":0,"query":"","cursor":0,"art_page":-1,"expected_list_revision":0,"hovered":-1,"preview_columns":0}
	var response:=await request("job_settings",intent)
	var value: Dictionary=response.get("job_settings",{})
	check(response.get("status")==C.ManagementStatus.Ok and value.get("art",{}).get("caption")==reference.artwork.header,"Typed job artwork root/header differs")
	check(value.get("art",{}).get("rows",[]).size()==6 and value.get("choices",[]).is_empty(),"Artwork payload mixed ordinary choices")
	if OS.get_environment("DF3D_RESIDENTS_JOB_ART_DRAFT_WIRE")=="1":
		await artwork_draft(reference,value);return
	var pages: Array=[]
	for expected: Dictionary in fixture.artwork_pages_reference.pages:
		intent.art_page=int(expected.page);intent.cursor=0;intent.expected_list_revision=0;intent.hovered=-1;intent.preview_columns=0
		response=await request("job_settings",intent);value=response.get("job_settings",{})
		var art: Dictionary=value.get("art",{})
		check(response.get("status")==C.ManagementStatus.Ok and art.get("total")==int(expected.total) and art.get("rows",[]).size()==int(expected.rows),"Typed artwork first page differs")
		if art.is_empty():continue
		var revision: int=art.list_revision
		if int(art.next_cursor)>0:
			intent.cursor=int(art.next_cursor);intent.expected_list_revision=revision
			var second:=await request("job_settings",intent)
			check(second.get("job_settings",{}).get("art",{}).get("list_revision")==revision,"Artwork second page lost receipt")
		intent.cursor=0;intent.expected_list_revision=revision;intent.hovered=int(art.rows[0].id);intent.preview_columns=int(expected.columns)
		var hover:=await request("job_settings",intent)
		check(hover.get("job_settings",{}).get("art",{}).get("preview",[])==expected.preview,"Typed artwork preview differs from native")
		intent.expected_list_revision=1
		var stale:=await request("job_settings",intent)
		check(stale.get("status")==C.ManagementStatus.Rejected and not stale.has("job_settings"),"Stale artwork reply retained page")
		pages.append({"page":expected.page,"total":art.total,"preview":true})
	intent.art_page=-1;intent.cursor=0;intent.expected_list_revision=0;intent.hovered=-1;intent.preview_columns=0
	for key: String in ["job_id","building_id","unit_id"]:
		var invalid:=intent.duplicate();invalid[key]=2147483647
		var rejected:=await request("job_settings",invalid)
		check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("job_settings"),"Wrong artwork target retained page")
	var unrelated:=await request("construction",{"action":C.ManagementAction.Catalog})
	check(not unrelated.has("job_settings"),"Unrelated reply retained artwork")
	var composed:=await composed_artwork(reference)
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"artwork_pages":pages,"composed":composed}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func composed_artwork(reference: Dictionary) -> Dictionary:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Artwork assets unavailable"):return {}
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/residents_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	check(await ready(owner.state),"Artwork Residents roster failed")
	var index: int=owner.state.ids.find(int(reference.unit_id));owner.state.seek(index,owner.state.capacity)
	check(await ready(owner.state),"Artwork resident row failed")
	var first: int=owner.state.first
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-first)*36+18))
	var state=owner.job_state;var view=owner.job_panel
	check(await ready(state),"Resident job settings did not load")
	var began:=false
	if not state.has_art():
		check(int(state.snapshot.options[state.selected].kind)==3,"Expected improvement type picker")
		await pointer(view,Vector2(120,view.list_top()+18));began=await ready(state)
	check(state.has_art() and state.art_page()==-1 and state.rows.size()==6,"Resident job button did not open artwork root")
	check(view.visible and not owner.panel.visible and host.active==owner,"Artwork lost owner/input boundary")
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;Input.parse_input_event(escape);await process_frame
	check(state.has_art() and state.phase==state.Phase.Ready,"Escape left native artwork root")
	await pointer(view,Vector2(120,114));check(await ready(state) and state.art_page()==1 and state.rows.size()==128,"Artwork figure button did not open first page")
	var motion:=InputEventMouseMotion.new();motion.position=view.get_global_transform_with_canvas()*Vector2(120,view.list_top()+18);motion.global_position=motion.position
	Input.parse_input_event(motion);await process_frame
	var deadline:=Time.get_ticks_msec()+5000
	while state.preview_ticket!=0 and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
	check(not state.preview_lines.is_empty(),"Artwork pointer hover did not populate native preview")
	state.seek(128);check(await ready(state) and state.row_base()==128,"Artwork owner did not fetch later page")
	await pointer(view,Vector2(120,114))
	for character in "zzzznomatch":
		var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);Input.parse_input_event(key);await process_frame
	check(await ready(state) and state.query=="zzzznomatch" and state.rows.is_empty(),"Artwork search did not replace the page")
	await pointer(view,Vector2(120,180),MOUSE_BUTTON_RIGHT)
	check(await ready(state) and state.art_page()==-1 and state.query.is_empty(),"Artwork Back did not clear search and restore root")
	await pointer(view,Vector2(120,180),MOUSE_BUTTON_RIGHT)
	check(state.phase==state.Phase.Closed and owner.panel.visible and owner.state.first==first and host.active==owner,"Artwork root Back did not restore same roster")
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-first)*36+18));host.reset_local_views()
	for frame in 5:world.poll();await process_frame
	check(state.phase==state.Phase.Closed and not view.visible and host.active==null,"Owner reset retained pending artwork")
	owner.open_panel();check(await ready(owner.state),"Artwork edit roster reopen failed")
	index=owner.state.ids.find(int(reference.unit_id));owner.state.seek(index,owner.state.capacity);check(await ready(owner.state),"Artwork edit row failed")
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-owner.state.first)*36+18));check(await ready(state),"Artwork edit entry failed")
	if not state.has_art():await pointer(view,Vector2(120,view.list_top()+18));check(await ready(state),"Repeated Image entry failed")
	await pointer(view,Vector2(120,114));check(await ready(state) and state.art_page()==1,"Artwork edit figure page failed")
	var chosen: int=state.rows[0].id
	await pointer(view,Vector2(120,view.list_top()+18))
	deadline=Time.get_ticks_msec()+5000
	while state.phase==state.Phase.Applying and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
	check(state.phase==state.Phase.Closed and await ready(owner.state) and owner.panel.visible,"Confirmed artwork assignment did not refresh roster")
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame
	return {"root":true,"category":true,"hover":true,"paging":true,"search":true,"back":true,"reset":true,"began_image":began,"assigned_figure":chosen}

func artwork_draft(reference: Dictionary,root_value: Dictionary) -> void:
	var intent: Dictionary={"action":C.ManagementAction.JobSettingsRead,"job_id":int(reference.job_id),"building_id":int(reference.building_id),"unit_id":int(reference.unit_id),"option":0,"expected_revision":int(root_value.revision),"art":{"page":6,"draft":{"value":{"elements":[],"relationships":[]},"columns":118}}}
	var reply:=await request("job_settings",intent)
	var art: Dictionary=reply.get("job_settings",{}).get("art",{})
	if not check(reply.get("status")==C.ManagementStatus.Ok and art.get("rows",[]).size()==9,"Job draft root rejected"):world.queue_free();await process_frame;quit(1);return
	intent.art.page=7
	reply=await request("job_settings",intent);art=reply.get("job_settings",{}).get("art",{})
	if not check(art.get("total")==2394 and not art.get("rows",[]).is_empty(),"Job draft creature list differs"):world.queue_free();await process_frame;quit(1);return
	var row: Dictionary=art.rows[0]
	intent.art.draft.action=1;intent.art.draft.element={"kind":7,"id":row.id,"secondary":row.secondary,"quantity":1}
	reply=await request("job_settings",intent);art=reply.get("job_settings",{}).get("art",{})
	if not check(art.get("draft",{}).get("elements",[]).size()==1 and not art.get("draft_description",[]).is_empty(),"Job draft addition lost value/description"):world.queue_free();await process_frame;quit(1);return
	var description: Array=art.draft_description
	intent.action=C.ManagementAction.JobSettingsApply;intent.art={"page":6,"draft":{"value":art.draft,"columns":118,"action":4}}
	reply=await request("job_settings",intent);art=reply.get("job_settings",{}).get("art",{})
	if not check(reply.get("job_settings_edit",{}).get("outcome")==C.JobSettingsEditOutcome.Applied and art.get("draft",{}).has("name"),"Job draft name generation failed"):world.queue_free();await process_frame;quit(1);return
	var draft: Dictionary=art.draft
	intent.action=C.ManagementAction.JobSettingsRead;intent.art={"page":18,"draft":{"value":draft,"columns":118,"name_query":{"component":0,"query_bytes":PackedByteArray(),"cursor":0}}}
	reply=await request("job_settings",intent);art=reply.get("job_settings",{}).get("art",{})
	check(art.get("name",{}).has("native_header") and not art.get("name",{}).get("choices",[]).is_empty(),"Job draft native name page missing")
	intent.action=C.ManagementAction.JobSettingsApply;intent.art={"page":6,"draft":{"value":draft,"columns":118,"action":5}}
	var stale:=intent.duplicate(true);stale.expected_revision=1
	reply=await request("job_settings",stale);check(reply.get("job_settings_edit",{}).get("outcome")==C.JobSettingsEditOutcome.Stale,"Stale job draft commit was not rejected")
	reply=await request("job_settings",intent)
	check(reply.get("status")==C.ManagementStatus.Ok and reply.get("job_settings_edit",{}).get("outcome")==C.JobSettingsEditOutcome.Applied and not reply.has("job_settings"),"Job draft Done failed")
	var owner_result:=await composed_draft(reference)
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"owner":owner_result,"draft":{"race":row.id,"caste":row.secondary,"description":description,"name_page":true,"done":reply.get("job_settings_edit",{})}}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func composed_draft(reference: Dictionary) -> Dictionary:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Draft owner assets unavailable"):return {}
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/residents_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	check(await ready(owner.state),"Draft owner roster failed")
	var index: int=owner.state.ids.find(int(reference.unit_id));owner.state.seek(index,owner.state.capacity);check(await ready(owner.state),"Draft owner row failed")
	await pointer(owner.panel,Vector2(540,owner.panel.list_top()+(index-owner.state.first)*36+18))
	var state=owner.job_state;var view=owner.job_panel
	if not check(await ready(state) and state.art_page()==-1 and state.draft_value.has("name"),"Artwork root did not initialize native draft name"):
		owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame;return {}
	await pointer(view,Vector2(120,258));check(await ready(state) and state.art_page()==6,"Specify new image did not open draft")
	await capture_draft("empty")
	await pointer(view,Vector2(48,114));check(await ready(state) and state.art_page()==7,"Draft Creature control failed")
	await capture_draft("creatures")
	await pointer(view,Vector2(300,view.list_top()+18));check(await ready(state) and state.art_page()==6 and state.draft_value.elements.size()==1,"Draft creature selection failed")
	await capture_draft("populated",true,state)
	await pointer(view,Vector2(152,378));check(state.draft_discard,"Dirty draft Back did not ask to discard")
	await capture_draft("discard")
	await pointer(view,Vector2(120,150));check(not state.draft_discard and state.draft_value.elements.size()==1,"Keep working lost draft")
	await pointer(view,Vector2(152,378));await pointer(view,Vector2(120,102));check(await ready(state) and state.art_page()==-1 and state.draft_value.elements.is_empty(),"Discard did not return to artwork root")
	await pointer(view,Vector2(120,258));check(await ready(state),"Draft reopen failed")
	await pointer(view,Vector2(48,114));check(await ready(state),"Creature list reopen failed")
	await pointer(view,Vector2(300,view.list_top()+18));check(await ready(state) and state.draft_value.elements.size()==1,"Creature re-add failed")
	var extended: Dictionary={}
	if OS.get_environment("DF3D_RESIDENTS_JOB_ART_EXTENDED")=="1":extended=await extended_draft(state,view)
	await pointer(view,Vector2(40,378));check(await ready(state) and view.name_state.active and view.name_state.phase==view.name_state.Phase.Ready,"Native name editor did not open")
	await capture_draft("name",true)
	var word: int=view.name_state.rows[0].word
	await pointer(view.name_view,view.name_view.row_rect(0).get_center());check(await ready(state) and state.draft_value.name.words[0]==word,"Native name word selection failed")
	await pointer(view.name_view,Vector2(view.name_view.size.x-64,30));check(await ready(state) and state.art_page()==6 and not view.name_state.active,"Name Done did not restore draft")
	await pointer(view,Vector2(96,378))
	var deadline:=Time.get_ticks_msec()+5000
	while state.phase==state.Phase.Applying and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
	check(state.phase==state.Phase.Closed and await ready(owner.state) and owner.panel.visible,"Draft Done did not return to refreshed Residents")
	var result: Dictionary={"initialized_name":true,"discard":true,"kept":true,"named_word":word,"done":state.phase==state.Phase.Closed,"extended":extended}
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame
	return result

func extended_draft(state,view) -> Dictionary:
	var chosen: Array=[]
	for category in [[8,Vector2(80,150)],[9,Vector2(40,186)],[10,Vector2(104,186)],[11,Vector2(40,222)],[12,Vector2(104,222)],[13,Vector2(48,258)]]:
		await pointer(view,category[1]);check(await ready(state) and state.art_page()==category[0],"Draft category failed")
		if not check(not state.rows.is_empty(),"Draft category has no fixture choices"):return {}
		chosen.append(state.rows[0].duplicate(true))
		await pointer(view,Vector2(300,view.list_top()+18));check(await ready(state) and state.art_page()==6,"Draft category add failed")
	await pointer(view,Vector2(80,294));check(await ready(state) and state.art_page()==14,"Relationship list failed")
	var relationship: Dictionary=state.rows[0].duplicate(true)
	await pointer(view,Vector2(300,view.list_top()+18));check(await ready(state) and state.art_page()==15,"Relationship actor list failed")
	await pointer(view,Vector2(300,view.list_top()+18));check(await ready(state),"Relationship actor selection failed")
	if int(relationship.secondary)==1:
		check(state.art_page()==16 and state.rows[0].id!=0,"Relationship target retained actor")
		await pointer(view,Vector2(300,view.list_top()+18));check(await ready(state),"Relationship target selection failed")
	check(state.art_page()==6 and state.draft_value.relationships.size()==1,"Relationship addition failed")
	var related: Array=state.snapshot.art.draft_description.duplicate()
	await capture_draft("related",true,state)
	await pointer(view,Vector2(80,330));check(await ready(state) and state.art_page()==17,"Delete element list failed")
	await pointer(view,Vector2(view.size.x-32,view.list_top()+18));check(await ready(state) and state.draft_value.elements.size()==6 and state.draft_value.relationships.is_empty(),"Deleting actor did not remove dependent relationship")
	var deleted: Array=state.snapshot.art.draft_description.duplicate()
	await capture_draft("deleted")
	await pointer(view,Vector2(64,378));check(await ready(state) and state.art_page()==6,"Stop deleting did not restore draft")
	return {"chosen":chosen,"relationship":relationship,"related":related,"deleted":deleted,"elements":state.draft_value.elements.duplicate(true)}

func capture_draft(label: String,resize: bool=false,state=null) -> void:
	if OS.get_environment("DF3D_RESIDENTS_JOB_ART_RENDER")!="1":return
	if not check(DisplayServer.get_name()!="headless","Draft capture needs a renderer"):return
	var sizes: Array[Vector2i]=[Vector2i(1200,800)]
	if resize:sizes=[Vector2i(960,600),Vector2i(1600,900),Vector2i(1200,800)]
	for dimensions in sizes:
		root.size=dimensions
		for frame in 3:await process_frame
		if state!=null:
			check(await ready(state),"Resized draft did not refresh")
			check(state.draft_formatted_columns==int((dimensions.x-272)/8),"Resized draft retained old formatting width")
			for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory+"/job-draft-"+label+"-"+str(dimensions.x)+".png")==OK,"Draft capture failed")
