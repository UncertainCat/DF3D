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
func drag_scrollbar(bar, bottom: bool) -> void:
	var grip: Vector2i=bar.thumb()
	var start: Vector2=bar.get_global_transform_with_canvas()*Vector2(8,(grip.x+grip.y*0.5)*12)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;press.global_position=start
	Input.parse_input_event(press);Input.flush_buffered_events();await process_frame
	check(bar.dragging,"Scrollbar thumb did not capture pointer")
	var finish: Vector2=bar.get_global_transform_with_canvas()*Vector2(8,bar.size.y-18 if bottom else 18)
	var motion:=InputEventMouseMotion.new();motion.position=finish;motion.global_position=finish
	Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=finish;release.global_position=finish
	Input.parse_input_event(release);Input.flush_buffered_events();await process_frame
	check(not bar.dragging,"Scrollbar retained pointer after release")

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if OS.get_environment("DF3D_STANDING_ORDERS_WIRE")=="1":
		await standing_orders_wire();return
	if OS.get_environment("DF3D_WORK_DETAILS_FAULT_WIRE")=="1":
		await work_detail_fault();return
	if OS.get_environment("DF3D_WORK_DETAILS_RENAME_RENDER")=="1":
		await work_detail_name_scene();return
	if OS.get_environment("DF3D_WORK_DETAILS_RENAME_WIRE")=="1":
		await work_detail_name_session();return
	if OS.get_environment("DF3D_WORK_DETAILS_DELETE_WIRE")=="1":
		await work_detail_delete_scene();return
	if OS.get_environment("DF3D_WORK_DETAILS_SETTINGS_RENDER")=="1":
		await work_detail_settings_scene();return
	if OS.get_environment("DF3D_WORK_DETAILS_SETTINGS_CONTROLLER")=="1":
		await work_detail_settings_controller();return
	if OS.get_environment("DF3D_WORK_DETAILS_SETTINGS_WIRE")=="1":
		await work_detail_settings();return
	if OS.get_environment("DF3D_WORK_DETAILS_RENDER")=="1":
		await work_detail_scene();return
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

func work_detail_scene() -> void:
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Work Details viewer assets unavailable"):quit(1);return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/work_details_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	var state=owner.state;var view=owner.panel
	if not check(await ready(state),"Work Details viewer roster failed"):quit(1);return
	view.ticks_override=250;view.queue_redraw()
	for frame in 3:world.poll();await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/work-details-view.png")==OK,"Work Details capture failed")
	var initial_count: int=state.ids.size()
	await pointer(view,view.detail_rect(1).get_center());check(await ready(state) and state.selected.index==1,"Work Details sidebar selection failed")
	await pointer(view,view.detail_rect(0).get_center());check(await ready(state) and state.selected.index==0,"Work Details selection return failed")
	await pointer(view,Vector2(38*8+16,view.list_top()-18));check(await ready(state) and state.sort==C.WorkDetailWorkerSort.Name,"Work Details sort click failed")
	await pointer(view,Vector2(69*8+16,view.list_top()-18));check(await ready(state) and state.sort==C.WorkDetailWorkerSort.Skills,"Work Details Skills return failed")
	await pointer(view,view.search.position+Vector2(24,18))
	for character in "MINER":
		var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);Input.parse_input_event(key);await process_frame
	check(await ready(state) and state.ids.size()==4,"Work Details search typing failed")
	for index in 5:
		var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_BACKSPACE;Input.parse_input_event(key);await process_frame
	check(await ready(state) and state.ids.size()==initial_count,"Work Details search clear failed")
	var original_mode:=int(state.selected.mode)
	await pointer(view,view.mode_rect(2).get_center());check(await ready(state) and int(state.selected.mode)==2,"Visible Nobody button did not apply")
	await pointer(view,view.mode_rect([1,3,2].find(original_mode)).get_center());check(await ready(state) and int(state.selected.mode)==original_mode,"Visible assignment mode restore failed")
	var unit_id:=int(state.ids[0]);var original_member: bool=state.row_at(0).member
	await pointer(view,view.member_rect(0).get_center());check(await ready(state) and state.selected.assigned_units.has(unit_id)!=original_member,"Visible membership checkbox did not apply")
	state.seek(state.ids.find(unit_id),view.page_rows);check(await ready(state),"Edited worker could not be located")
	await pointer(view,view.member_rect(state.ids.find(unit_id)-state.first).get_center());check(await ready(state) and state.selected.assigned_units.has(unit_id)==original_member,"Visible membership restore failed")
	state.seek(state.ids.find(unit_id),view.page_rows);check(await ready(state),"Specialization worker unavailable")
	var original_scope: bool=state.rows[unit_id].specialization.only_assigned
	await pointer(view,Vector2(736,view.list_top()+(state.ids.find(unit_id)-state.first)*36+18));check(await ready(state),"Visible specialization did not finish")
	state.seek(state.ids.find(unit_id),view.page_rows);check(await ready(state) and state.rows[unit_id].specialization.only_assigned!=original_scope,"Visible specialization did not apply")
	await pointer(view,Vector2(736,view.list_top()+(state.ids.find(unit_id)-state.first)*36+18));check(await ready(state),"Visible specialization restore did not finish")
	state.seek(state.ids.find(unit_id),view.page_rows);check(await ready(state) and state.rows[unit_id].specialization.only_assigned==original_scope,"Visible specialization restore failed")
	var details_before: int=state.details.size()
	await pointer(view,view.add_rect().get_center());check(await ready(state) and state.details.size()==details_before+1 and state.selected.index==details_before,"Visible Add new work detail failed")
	owner.handle_back();check(not view.visible,"Work Details Back did not close")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"initial_workers":initial_count,"sidebar_sort_search_back":true,"mode_membership_specialization_restored":true,"created_index":details_before}));file.close()
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

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
		if int(reference.step)==4:
			await work_detail_reset_scene(index)
			response={"status":C.ManagementStatus.Ok}
		else:response=await request("citizens",intent)
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

func work_detail_settings() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	var expected: Dictionary=reference.settings_effects
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Settings wire attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var inspected:=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":int(expected.index)})
	var detail: Dictionary=inspected.get("citizen",{}).get("details",[{}])[0]
	if not check(int(detail.get("revision",0))>0,"Settings detail missing"):quit(1);return
	var intent: Dictionary={"action":C.ManagementAction.WorkDetailSettingsRead,"detail_index":int(expected.index),"expected_revision":int(detail.revision)}
	var result:=await request("work_detail_settings",intent)
	var value: Dictionary=result.get("work_detail_settings",{})
	if not check(not value.is_empty(),"Settings read failed"):quit(1);return
	check(value.catalog.size()==expected.provider.catalog.size(),"Native settings catalog size differs on wire")
	for index in mini(value.catalog.size(),expected.provider.catalog.size()):
		var actual: Dictionary=value.catalog[index];var native: Dictionary=expected.provider.catalog[index]
		check(int(actual.id)==int(native.id) and actual.caption==native.caption,"Native settings catalog differs on wire at "+str(index))
	if reference.get("settings_wire_phase","")=="locked":
		check(not value.editable,"External controller did not disable edits")
		intent.action=C.ManagementAction.WorkDetailSettingsToggle;intent.setting_id=11
		result=await request("work_detail_settings",intent)
		check(result.get("status")==C.ManagementStatus.Rejected and not result.has("work_detail_settings"),"External controller toggle accepted")
	else:
		for patch in [{"expected_revision":int(detail.revision)^1},{"detail_index":127}]:
			var invalid:=intent.duplicate();invalid.merge(patch,true)
			result=await request("work_detail_settings",invalid)
			check(result.get("status")==C.ManagementStatus.Rejected and not result.has("work_detail_settings"),"Stale/missing settings target retained data")
		intent.action=C.ManagementAction.WorkDetailSettingsToggle;intent.setting_id=10
		result=await request("work_detail_settings",intent)
		check(result.get("status")==C.ManagementStatus.Rejected and not result.has("work_detail_settings"),"Labor outside native picker accepted")
		for step: Dictionary in expected.provider.steps:
			intent.setting_id=int(step.id)
			var previous: int=int(intent.expected_revision)
			result=await request("work_detail_settings",intent);value=result.get("work_detail_settings",{})
			if not check(not value.is_empty(),"Settings toggle failed"):break
			check(value.labors==PackedInt32Array(step.labors),"Native toggle definition differs on wire")
			check(int(value.revision)!=previous,"Settings mutation retained old receipt")
			var stale:=await request("work_detail_settings",intent)
			check(stale.get("status")==C.ManagementStatus.Rejected and not stale.has("work_detail_settings"),"Old toggle receipt replayed")
			intent.expected_revision=int(value.revision)
			inspected=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":int(expected.index)})
			check(inspected.get("citizen",{}).get("details",[{}])[0].get("revision")==value.revision,"Predicted settings receipt differs from authoritative receipt")
	result=await request("construction",{"action":C.ManagementAction.Catalog})
	check(not result.has("work_detail_settings"),"Settings result leaked into another domain")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"phase":reference.settings_wire_phase,"catalog_count":value.catalog.size()}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_settings_controller() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	var expected: Dictionary=reference.settings_effects
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Settings controller attach failed"):quit(1);return
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var state=preload("res://scripts/work_details_state.gd").new();state.configure(service);state.open()
	if not check(await ready(state),"Settings controller initial roster failed"):quit(1);return
	state.select_detail(int(expected.index))
	if not check(await ready(state),"Settings controller selection failed"):quit(1);return
	state.open_settings()
	if not check(await ready(state) and state.settings.catalog.size()==91,"Settings controller catalog failed"):quit(1);return
	if reference.settings_wire_phase=="locked":
		check(not state.settings.editable,"Settings controller lost read-only state")
		state.toggle_setting(11);check(state.ticket==0 and state.phase==state.Phase.Ready,"Read-only settings submitted a toggle")
	else:
		state.seek_settings(30,15)
		for step: Dictionary in expected.provider.steps:
			state.toggle_setting(int(step.id))
			if not check(await ready(state),"Controller native settings toggle failed"):break
			check(state.editing_settings and state.settings_first==30 and state.settings.labors==PackedInt32Array(step.labors),"Settings refresh lost native result or scroll")
		state.close_settings()
		check(await ready(state) and not state.editing_settings and state.roster_ready,"Done did not return to refreshed roster")
	state.close();check(state.settings.is_empty() and not state.editing_settings,"Close retained settings authority")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"controller":true,"phase":reference.settings_wire_phase}));file.close()
	state.dispose();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_settings_scene() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	var expected: Dictionary=reference.settings_effects
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Settings scene assets unavailable"):quit(1);return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world);help.layout(Vector2(1200,800))
	var composition=preload("res://scripts/fortress_ui.gd").new();root.add_child(composition)
	composition.world=world;composition.actions=service;composition.host=host
	composition.view={"_fortress_hud":{"native_help":help}}
	var owner=composition.controller("work_details")
	check(composition.controller("work_details")==owner,"Work Details factory duplicated its owner")
	owner.open_panel()
	var state=owner.state;var view=owner.panel
	if not check(await ready(state),"Settings scene roster failed"):quit(1);return
	await pointer(view,view.detail_rect(int(expected.index)).get_center())
	if not check(await ready(state),"Settings scene detail selection failed"):quit(1);return
	if reference.settings_wire_phase=="normal":
		for extent in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
			root.size=extent;await create_timer(0.15).timeout
			if not check(await ready(state),"Resized worker rows did not settle"):quit(1);return
			check(view.page_rows==({912:4,1600:14,1200:10}[extent.x]),"Resized roster differs from native row capacity")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/work-details-roster-resize-"+str(extent.x)+".png")
		check(not view.detail_scrollbar.visible,"Expanded sidebar retained an unnecessary scrollbar")
		root.size=Vector2i(912,552);await create_timer(0.15).timeout
		check(await ready(state) and view.detail_scrollbar.visible,"Minimum-height sidebar did not scroll")
		var selected: int=state.selected.index
		await pointer(view.detail_scrollbar,Vector2(8,view.detail_scrollbar.size.y-18))
		check(view.detail_first>0 and state.selected.index==selected,"Sidebar track changed selection or did not scroll")
		await drag_scrollbar(view.detail_scrollbar,false)
		check(view.detail_first==0,"Sidebar drag did not reach first row")
		await drag_scrollbar(view.detail_scrollbar,true)
		check(view.detail_first==state.details.size()-view.detail_capacity(),"Sidebar drag did not reach last row")
		root.size=Vector2i(1600,900);await create_timer(0.15).timeout
		check(await ready(state) and view.detail_first==0 and not view.detail_scrollbar.visible and state.selected.index==selected,"Sidebar resize retained stale offset or changed selection")
		root.size=Vector2i(1200,800);await create_timer(0.15).timeout
		check(await ready(state),"Sidebar resize did not settle")
		var worker: Dictionary=state.row_at(state.first+1)
		check(not worker.is_empty(),"Portrait fixture needs a second worker")
		var selected_detail: int=state.selected.index
		await pointer(view,Vector2(280,view.list_top()+54))
		check(view.worker_selected==int(worker.id) and state.selected.index==selected_detail and state.ticket==0 and view.visible,"Portrait did not select locally")
		var leave:=InputEventMouseMotion.new();leave.position=Vector2.ZERO;Input.parse_input_event(leave);Input.flush_buffered_events();await process_frame
		check(view.worker_selected==int(worker.id),"Worker selection did not survive pointer departure")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/work-details-worker-selected.png")
	for entry in [["name",Vector2(316,view.list_top()-18)],["category",Vector2(396,view.list_top()-18)],["profession",Vector2(468,view.list_top()-18)],["skills",Vector2(568,view.list_top()-18)],["filter",view.search.get_rect().get_center()]]:
		var motion:=InputEventMouseMotion.new();motion.position=view.get_global_transform_with_canvas()*entry[1];motion.global_position=motion.position;Input.parse_input_event(motion);Input.flush_buffered_events()
		await create_timer(0.15).timeout
		check(help.displayed==("owner_filter" if entry[0]=="filter" else "detail_widget_"+entry[0]),"Roster widget help did not follow actual pointer: "+str(entry[0])+" observed "+help.displayed+" at "+str(view.pointer_position))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/work-details-widget-"+entry[0]+"-"+str(reference.settings_wire_phase)+".png")
	var departure:=InputEventMouseMotion.new();departure.position=Vector2.ZERO;Input.parse_input_event(departure);Input.flush_buffered_events();await create_timer(0.15).timeout
	check(not help.visible,"Roster widget help survived pointer departure")
	await pointer(view,Vector2(656,view.header_top()+18))
	if not check(await ready(state) and state.editing_settings,"Settings gear failed"):quit(1);return
	for frame in 3:world.poll();await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/work-details-settings-view-"+str(reference.settings_wire_phase)+".png")==OK,"Settings screenshot failed")
	var hovered:=false
	for index in mini(view.settings_capacity(),state.settings.catalog.size()):
		var icons: Array=view.setting_icons(int(state.settings.catalog[index].id),view.settings_rect(index).position.y)
		if icons.is_empty():continue
		var motion:=InputEventMouseMotion.new();motion.position=view.get_global_transform_with_canvas()*icons[0].rect.get_center();Input.parse_input_event(motion)
		await create_timer(0.65).timeout
		check(help.displayed=="staff_work_detail" and help.visible,"Visible settings badge did not show native help")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/work-details-settings-hover-view-"+str(reference.settings_wire_phase)+".png")
		motion=InputEventMouseMotion.new();motion.position=Vector2.ZERO;Input.parse_input_event(motion);await process_frame;await process_frame
		check(not help.visible,"Settings help survived pointer departure")
		hovered=true;break
	check(hovered,"Settings fixture has no visible work-detail badges")
	if reference.settings_wire_phase=="normal":
		for extent in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
			root.size=extent;await create_timer(0.15).timeout
			check(state.editing_settings and state.phase==state.Phase.Ready,"Resize changed settings authority")
			check(view.settings_capacity()==({912:8,1600:18,1200:15}[extent.x]),"Resized settings differs from native row capacity")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/work-details-settings-resize-"+str(extent.x)+".png")
	if reference.settings_wire_phase=="normal":
		root.size=Vector2i(912,552);await create_timer(0.15).timeout
		await pointer(view.scrollbar,Vector2(8,view.scrollbar.size.y-18))
		check(state.settings_first>0,"Settings track did not scroll")
		await drag_scrollbar(view.scrollbar,true)
		check(state.settings_first==state.settings.catalog.size()-view.settings_capacity(),"Settings drag did not reach last row")
		root.size=Vector2i(1600,900);await create_timer(0.15).timeout
		check(state.settings_first==state.settings.catalog.size()-view.settings_capacity() and view.scrollbar.first==state.settings_first,"Growing Settings did not clamp the bottom offset")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/work-details-settings-bottom-wide.png")
		await drag_scrollbar(view.scrollbar,false)
		check(state.settings_first==0,"Settings drag did not return to first row")
		root.size=Vector2i(1200,800);await create_timer(0.15).timeout
	if reference.settings_wire_phase=="locked":
		await pointer(view,view.settings_rect(1).get_center())
		check(state.ticket==0 and state.phase==state.Phase.Ready and not state.settings.editable,"Read-only settings click submitted mutation")
	else:
		for step: Dictionary in expected.provider.steps:
			await pointer(view,view.settings_rect(0 if int(step.id)<0 else 1).get_center())
			if not check(await ready(state),"Visible setting toggle failed"):break
			check(state.settings.labors==PackedInt32Array(step.labors),"Visible setting differs from native effect")
		await pointer(view,view.settings_rect(2).get_center(),MOUSE_BUTTON_WHEEL_DOWN)
		check(state.settings_first==1,"Settings wheel did not scroll")
		await pointer(view,Vector2(500,view.settings_top()+18),MOUSE_BUTTON_WHEEL_UP)
		check(state.settings_first==0,"Settings wheel did not return")
		await pointer(view,view.done_rect().get_center())
		check(await ready(state) and not state.editing_settings and view.search.visible,"Visible Done did not return to roster")
	owner.handle_back();check(not view.visible,"Settings owner Back failed")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"rendered_settings":true,"phase":reference.settings_wire_phase}));file.close()
	composition.queue_free();help.queue_free();host.queue_free();interaction.queue_free();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_reset_scene(index: int) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Reset scene assets unavailable"):return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/work_details_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	if check(await ready(owner.state),"Reset roster failed"):
		await pointer(owner.panel,owner.panel.detail_rect(index).get_center())
		if check(await ready(owner.state),"Reset detail selection failed"):
			await pointer(owner.panel,Vector2(656,owner.panel.header_top()+18))
			if check(await ready(owner.state) and owner.state.settings.get("no_modify",false),"Reset gear failed"):
				if OS.get_environment("DF3D_WORK_DETAILS_RESET_RENDER")=="1":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(directory+"/work-details-reset-view-before.png")
				await pointer(owner.panel,owner.panel.settings_action_rect().get_center())
				check(await ready(owner.state) and owner.state.editing_settings and owner.state.settings.labors==PackedInt32Array([58]),"Reset button did not refresh native defaults")
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();await process_frame

func work_detail_delete_scene() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json")).deletion
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Delete scene assets unavailable"):quit(1);return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/work_details_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	if check(await ready(owner.state),"Delete roster failed"):
		await pointer(owner.panel,owner.panel.detail_rect(int(reference.index)).get_center())
		if check(await ready(owner.state),"Delete detail selection failed"):
			await pointer(owner.panel,Vector2(656,owner.panel.header_top()+18))
			if check(await ready(owner.state) and not owner.state.settings.get("no_modify",true),"Delete gear failed"):
				await pointer(owner.panel,owner.panel.settings_action_rect().get_center())
				check(await ready(owner.state) and not owner.state.editing_settings and owner.state.selected.get("index",-1)==0 and owner.state.details.size()==reference.after.details.size(),"Delete did not return to first detail roster")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"delete_owner":true}));file.close()
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_name_session() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json")).rename
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Rename attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var response: Dictionary=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":int(reference.index)})
	var rows: Array=response.get("citizen",{}).get("details",[])
	if not check(rows.size()==1,"Rename detail unavailable"):quit(1);return
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	var naming=preload("res://scripts/work_detail_name_session.gd").new();service.add_child(naming);naming.configure(service,rows[0])
	var outcome: Dictionary={"finished":false,"failed":false}
	naming.finished.connect(func():outcome.finished=true)
	naming.failed.connect(func(_result):outcome.failed=true)
	# Queue explicit native-observed names while the first write is outstanding,
	# then finish. The service owns draining even after the editor would close.
	for step: Dictionary in reference.steps:check(naming.edit(step.name),"Native rename text rejected")
	naming.finish();deadline=Time.get_ticks_msec()+8000
	while not outcome.finished and not outcome.failed and Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
	check(outcome.finished and not outcome.failed,"Buffered rename session did not finish")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"rename_session":true}));file.close()
	service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

func name_key(code: int,unicode: int=0) -> void:
	var key:=InputEventKey.new();key.keycode=code;key.unicode=unicode;key.pressed=true;Input.parse_input_event(key);await process_frame
	key=key.duplicate();key.pressed=false;Input.parse_input_event(key);await process_frame
func name_text(value: String) -> void:
	for character in value:await name_key(0,character.unicode_at(0))
func work_detail_name_scene() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json")).rename
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach() and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Name scene assets unavailable"):quit(1);return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/work_details_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
	if not check(await ready(owner.state),"Name roster failed"):quit(1);return
	await pointer(owner.panel,owner.panel.detail_rect(int(reference.index)).get_center())
	if not check(await ready(owner.state),"Name detail failed"):quit(1);return
	await pointer(owner.panel,owner.panel.name_rect().get_center());await name_text(" a Z09-_.")
	check(owner.panel.name_entry.editing and owner.panel.name_entry.value==reference.steps[1].name,"Visible immediate name differs from native")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-details-name-view-typed.png")
	await name_key(KEY_ENTER)
	check(await ready(owner.state) and not owner.panel.name_entry.editing and owner.state.selected.name==reference.steps[1].name,"Name Enter did not finish with native text")
	await pointer(owner.panel,owner.panel.name_rect().get_center());await name_text("a")
	await pointer(owner.panel,Vector2(656,owner.panel.header_top()+18))
	check(await ready(owner.state),"Name navigation refresh failed")
	for frame in 3:world.poll();await process_frame
	check(await ready(owner.state) and owner.state.editing_settings,"Gear click during naming was lost")
	await pointer(owner.panel,owner.panel.done_rect().get_center());check(await ready(owner.state),"Name settings Done failed")
	await pointer(owner.panel,owner.panel.name_rect().get_center())
	for count in 40:await name_key(KEY_BACKSPACE)
	await name_text("q".repeat(45));await name_key(KEY_BACKSPACE);await name_text("é")
	check(owner.panel.name_entry.value==reference.expected_name,"Visible byte limit differs from native")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/work-details-name-view-limit.png")
	await name_key(KEY_ESCAPE)
	check(not owner.panel.visible,"Name Escape did not close panel")
	var deadline:=Time.get_ticks_msec()+8000
	while is_instance_valid(owner.name_session) and Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
	check(not is_instance_valid(owner.name_session),"Closing name editor did not drain explicit typing")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"rename_view":true}));file.close()
	owner.queue_free();host.queue_free();interaction.queue_free();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)

func work_detail_fault() -> void:
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Work Details fault attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	if not check(world.poll_management().get("transport_alive",false),"Work Details fault transport unavailable"):quit(1);return
	await request("construction",{"action":C.ManagementAction.Catalog})
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	var index:=int(reference.created.index)
	var reply: Dictionary=await request("citizens",{"action":C.ManagementAction.WorkDetailInspect,"detail_index":index})
	if not check(reply.get("citizen",{}).get("details",[]).size()==1,"Fault target missing"):quit(1);return
	var revision: int=reply.citizen.details[0].revision
	var intent: Dictionary={"action":C.ManagementAction.WorkDetailEdit,"detail_index":index,"edit":1,"name":"DF3D receipt fault","expected_revision":revision+1}
	reply=await request("citizens",intent)
	check(reply.get("status")==C.ManagementStatus.Rejected and not reply.get("citizen",{}).get("outcome_unknown",false),"Pre-write refusal became uncertain")
	intent.expected_revision=revision
	reply=await request("citizens",intent)
	check(reply.get("status")==C.ManagementStatus.Rejected and reply.get("outcome")=="unknown","Post-write fault lost uncertainty")
	var citizen: Dictionary=reply.get("citizen",{})
	check(citizen.get("outcome_unknown",false) and citizen.get("details",[]).is_empty() and citizen.get("citizens",[]).is_empty(),"Uncertain reply retained rows")
	check(citizen.get("selected_detail",-1)==-1 and citizen.get("selected_unit",-1)==-1 and citizen.get("detail_list_revision",0)==0 and citizen.get("next_cursor",0)==0,"Uncertain reply retained authority")
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"uncertain":reply}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)

func standing_orders_wire() -> void:
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Standing orders attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog: Dictionary=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Standing orders session initialization failed"):quit(1);return
	var reply: Dictionary=await request("standing_orders",{"action":C.ManagementAction.StandingOrdersRead,"category":0})
	if not check(reply.get("standing_orders",{}).get("settings",[]).size()==11,"Standing orders snapshot missing"):quit(1);return
	for row: Dictionary in reply.standing_orders.settings:check(row.available==(int(row.id)<8),"Standing orders availability differs")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/standing-orders-native.json"))
	var count:=0
	for step: Dictionary in reference.wire_steps:
		reply=await request("standing_orders",{"action":C.ManagementAction.StandingOrdersSet,"category":0,"setting_id":int(step.id),"expected_value":int(step.expected),"value":int(step.value)})
		var applied: bool=int(step.outcome)==int(C.StandingOrdersOutcome.Applied)
		if not check(reply.get("status")== (C.ManagementStatus.Ok if applied else C.ManagementStatus.Rejected) and reply.get("standing_orders",{}).get("outcome")==int(step.outcome),"Standing orders edit outcome differs"):quit(1);return
		if applied:check(reply.standing_orders.settings[int(step.id)].value==int(step.value),"Standing orders receipt value differs")
		else:check(reply.standing_orders.settings.is_empty(),"Rejected standing orders retained authority")
		count+=1
		var file:=FileAccess.open(directory+"/standing-wire-step",FileAccess.WRITE);file.store_string(str(count));file.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/standing-wire-ack") and FileAccess.get_file_as_string(directory+"/standing-wire-ack")==str(count):break
			await create_timer(0.01).timeout
		if not check(FileAccess.get_file_as_string(directory+"/standing-wire-ack")==str(count),"Native standing orders readback missing; no replay"):quit(1);return
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"steps":count}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
