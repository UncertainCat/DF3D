extends "res://tests/item_carrier_wire_live.gd"
func page(tab: int,offset: int,revision: int) -> Dictionary:
	return await request("justice",{"action":C.ManagementAction.JusticeRead,"tab":tab,"offset":offset,"limit":4,"expected_list_revision":revision})
func details(tab: int,id: int,offset: int,list_revision: int,case_revision: int) -> Dictionary:
	return await request("justice",{"action":C.ManagementAction.JusticeCaseRead,"tab":tab,"crime_id":id,"offset":offset,"limit":8,"expected_list_revision":list_revision,"expected_case_revision":case_revision})
func pointer_click(point: Vector2,shift:=false,ctrl:=false) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.shift_pressed=shift;event.ctrl_pressed=ctrl
		Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func settle_controller(controller) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while controller.phase in [controller.Phase.Reading,controller.Phase.DetailReading] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
func settle_picker(controller) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
		if controller.candidates.phase not in [controller.candidates.Phase.Reading,controller.candidates.Phase.Applying] and controller.phase not in [controller.Phase.Reading,controller.Phase.DetailReading]:return
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Justice attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var counts: Array=[];var report_count:=0
	for tab in 3:
		var expected: Array=reference.lists[tab];var rows: Array=[];var revision:=0;var first:=true
		while first or rows.size()<expected.size():
			first=false;var reply:=await page(tab,rows.size(),revision)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Justice list rejected"):quit(1);return
			var state: Dictionary=reply.get("justice",{})
			check(state.get("offset")==rows.size() and state.get("total")==expected.size() and state.get("tab")==tab,"Justice list identity differs")
			revision=state.get("list_revision",0)
			if not check(not state.get("rows",[]).is_empty() or rows.size()==expected.size(),"Justice list stalled"):quit(1);return
			rows.append_array(state.rows)
		counts.append(rows.size())
		for i in rows.size():
			check(rows[i].crime_id==expected[i].id and rows[i].caption==expected[i].caption,"Justice case order/caption differs")
			var id: int=rows[i].crime_id;var facts: Dictionary=reference.details[str(id)];var witnesses: Array=[];var case_revision:=0;first=true
			while first or witnesses.size()<facts.witnesses.size():
				first=false;var reply:=await details(tab,id,witnesses.size(),revision,case_revision)
				if not check(reply.get("status")==C.ManagementStatus.Ok,"Justice detail rejected"):quit(1);return
				var d: Dictionary=reply.get("justice",{}).get("detail",{})
				check(d.get("crime_id")==id and d.get("caption")==rows[i].caption and d.get("status")==facts.summary.status and d.get("resolution")==facts.summary.resolution,"Justice summary differs")
				check(d.has("injured_party")==facts.summary.has("injured_party") and d.get("injured_party")==facts.summary.get("injured_party"),"Justice injured party differs")
				check(d.get("offset")==witnesses.size() and d.get("total")==facts.witnesses.size(),"Justice witness page identity differs")
				case_revision=d.get("revision",0)
				if not check(not d.get("witnesses",[]).is_empty() or witnesses.size()==facts.witnesses.size(),"Justice witnesses stalled"):quit(1);return
				witnesses.append_array(d.witnesses)
			check(witnesses==facts.witnesses,"Justice witness order or paired captions differs");report_count+=witnesses.size()
			var stale:=await details(tab,id,0,revision,case_revision+1)
			check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale and not stale.get("justice",{}).has("detail"),"Justice stale detail accepted")
		var stale:=await page(tab,0,revision+1)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Justice stale list accepted")
		var missing:=await details(tab,2147483647,0,revision,0)
		check(missing.get("status")==C.ManagementStatus.Rejected and missing.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Justice missing target accepted")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open()
	var view
	if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
		root.size=Vector2i(1200,800)
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Justice assets unavailable")
		view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
	for tab in 3:
		if tab>0:
			if view!=null:await pointer_click(view.position+view.tab_rect(tab).get_center())
			else:controller.select_tab(tab)
		await settle_controller(controller)
		if not check(controller.phase==controller.Phase.Ready,"Justice controller read did not settle"):quit(1);return
		check(controller.rows.size()==reference.lists[tab].size(),"Justice controller list differs")
		if not controller.rows.is_empty():
			var id: int=controller.rows[0].crime_id
			check(controller.selected_id==id and controller.detail.get("witnesses")==reference.details[str(id)].witnesses,"Justice controller initial detail differs")
		if view!=null:
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/justice-view-%d.png"%tab)
			if tab==0:
				await pointer_click(view.position+view.case_rect(1).get_center());await settle_controller(controller)
				check(controller.selected_id==controller.rows[1].crime_id,"Justice case click selected wrong row")
				await pointer_click(view.position+view.case_rect(0).get_center());await settle_controller(controller)
				await pointer_click(view.position+view.convict_rect().get_center());await settle_picker(controller)
				check(controller.candidates.phase==controller.candidates.Phase.Ready,"Convict button did not open picker")
				check(view.portraits.size()==view.picker_capacity(),"Visible candidate artwork missing")
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-picker-view.png")
				for gesture in [[0,false,false,0],[3,true,false,7],[0,true,false,-1],[0,true,false,8],[0,false,true,5]]:
					await pointer_click(view.position+view.sort_rect(gesture[0]).get_center(),gesture[1],gesture[2]);await settle_picker(controller)
					check(controller.candidates.phase==controller.candidates.Phase.Ready,"Sort header read did not settle")
					if gesture[3]>=0:
						var expected_sort: Dictionary=reference.sorts[gesture[3]]
						check(controller.candidates.rows.map(func(row):return row.unit_id)==expected_sort.rows.map(func(row):return int(row.unit_id)),"Header gesture produced wrong native order")
				for header in [2,2,3,3]:
					await pointer_click(view.position+view.sort_rect(header).get_center());await settle_picker(controller)
				for _step in 2:
					await pointer_click(view.position+view.sort_rect(1).get_center());await settle_picker(controller)
				check(controller.candidates.rows.map(func(row):return row.unit_id)==reference.sorts[2].rows.map(func(row):return int(row.unit_id)),"Category reverse order differs")
				check(view.portraits.size()==view.picker_capacity(),"Sorted candidate artwork missing")
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-picker-sorted-view.png")
				await pointer_click(view.position+view.search.position+Vector2(24,18))
				for letter in "zznomatch":
					var key:=InputEventKey.new();key.pressed=true;key.unicode=letter.unicode_at(0);key.keycode=letter.unicode_at(0)
					Input.parse_input_event(key);Input.flush_buffered_events();await process_frame
				await settle_picker(controller)
				check(controller.candidates.phase==controller.candidates.Phase.Ready and controller.candidates.rows.is_empty(),"Picker search input failed")
				controller.candidates.close()
				var wheel:=InputEventMouseButton.new();wheel.position=view.position+Vector2(view.detail_x()+20,view.list_top()+100);wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
				Input.parse_input_event(wheel);Input.flush_buffered_events();await process_frame
				check(controller.witness_first==1,"Justice witness wheel did not advance")
				await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-view-witness-scroll.png")
	if view!=null:view.queue_free();await process_frame
	controller.open();controller.close()
	await create_timer(0.1).timeout;world.poll()
	check(controller.phase==controller.Phase.Closed and controller.rows.is_empty() and controller.detail.is_empty(),"Closed Justice controller revived")
	controller.dispose();actions.queue_free();await process_frame
	var list_reply:=await page(0,0,0)
	var list_revision: int=list_reply.justice.list_revision
	var case_reply:=await details(0,9,0,list_revision,0)
	var case_revision: int=case_reply.justice.detail.revision
	var candidate_revision:=0;var candidate_count:=0
	for sample in reference.candidates:
		var rows: Array=[];var revision:=0;var first:=true
		while first or rows.size()<sample.rows.size():
			first=false
			var intent: Dictionary={"action":C.ManagementAction.JusticeCandidatesRead,"tab":0,"offset":rows.size(),"limit":64,
				"expected_list_revision":list_revision,"crime_id":9,"expected_case_revision":case_revision,
				"query":sample.query,"expected_candidate_revision":revision}
			var reply:=await request("justice",intent)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Justice candidates rejected"):quit(1);return
			var c: Dictionary=reply.justice.candidates
			check(c.crime_id==9 and c.offset==rows.size() and c.total==sample.rows.size(),"Justice candidate identity differs")
			revision=c.revision
			if not check(not c.rows.is_empty() or rows.size()==sample.rows.size(),"Justice candidates stalled"):quit(1);return
			rows.append_array(c.rows)
		for i in rows.size():
			var native: Dictionary=sample.rows[i]
			check(rows[i].unit_id==native.unit_id and rows[i].rank==native.rank and rows[i].interrogation_pending==bool(int(native.flags)&1)
				and rows[i].counterintelligence==bool(int(native.flags)&2),"Justice candidate order/facts differ")
			if reference.presentation.has(str(native.unit_id)):
				var p: Dictionary=reference.presentation[str(native.unit_id)];var d: Dictionary=rows[i].display
				check(d.columns==28 and d.name==p.name and d.witness_label==p.witness_label and d.witness_count==p.witness_count
					and d.witness_color==p.witness_color and d.deceased==p.deceased,"Justice candidate display differs")
				check(d.name_color.color==p.color and d.name_color.alternate==p.alternate and d.name_color.effect==p.effect,"Justice candidate name color differs")
		if sample.query=="":candidate_revision=revision;candidate_count=rows.size()
	for sample in reference.sorts:
		var sorted_rows: Array=[];var revision:=0
		while sorted_rows.size()<sample.rows.size():
			var sorts: Array=[]
			for sort in sample.sorts:sorts.append({"column":int(sort.column),"reverse":sort.reverse})
			var reply:=await request("justice",{"action":C.ManagementAction.JusticeCandidatesRead,"tab":0,"offset":sorted_rows.size(),"limit":64,
				"expected_list_revision":list_revision,"crime_id":9,"expected_case_revision":case_revision,"query":"","expected_candidate_revision":revision,"sorts":sorts})
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Sorted candidate page rejected"):quit(1);return
			var c: Dictionary=reply.justice.candidates;revision=c.revision
			if not check(not c.rows.is_empty(),"Sorted candidates stalled"):quit(1);return
			sorted_rows.append_array(c.rows)
		check(sorted_rows.map(func(row):return row.unit_id)==sample.rows.map(func(row):return int(row.unit_id)),"Transport changed native sorted order")
	var intent: Dictionary={"action":C.ManagementAction.JusticeConvict,"tab":0,"offset":0,"limit":32,
		"expected_list_revision":list_revision,"crime_id":9,"expected_case_revision":case_revision,
		"query":"","expected_candidate_revision":candidate_revision,"unit_id":5698}
	for patch in [{"expected_list_revision":list_revision+1},{"expected_case_revision":case_revision+1},
		{"expected_candidate_revision":candidate_revision+1},{"unit_id":2147483647},{"sorts":[{"column":1,"reverse":true}]}]:
		var stale:=intent.duplicate(true);stale.merge(patch,true)
		var reply:=await request("justice",stale)
		check(reply.get("status")==C.ManagementStatus.Rejected and reply.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,
			"Stale conviction was not rejected")
	var closed_reply:=await page(1,0,0)
	var closed_id: int=closed_reply.justice.rows[0].crime_id
	var closed_detail:=await details(1,closed_id,0,closed_reply.justice.list_revision,0)
	var closed: Dictionary=intent.duplicate(true);closed.action=C.ManagementAction.JusticeCandidatesRead;closed.erase("unit_id")
	closed.tab=1;closed.crime_id=closed_id;closed.expected_list_revision=closed_reply.justice.list_revision
	closed.expected_case_revision=closed_detail.justice.detail.revision;closed.expected_candidate_revision=0
	var closed_result:=await request("justice",closed)
	check(closed_result.get("status")==C.ManagementStatus.Rejected,"Closed case exposed Convict candidates")
	var applied:=false
	if OS.get_environment("DF3D_JUSTICE_WIRE_CONVICT")=="1":
		var picker_actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(picker_actions);picker_actions.configure(world,true)
		var owner=preload("res://scripts/justice_state.gd").new();owner.configure(picker_actions);owner.open()
		var picker_view
		if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
			picker_view=preload("res://scripts/justice_view.gd").new();root.add_child(picker_view);picker_view.configure_justice(world,owner);picker_view.layout(Vector2(1200,800))
		await settle_controller(owner);owner.open_candidates();await settle_picker(owner)
		if not check(owner.candidates.phase==owner.candidates.Phase.Ready and owner.candidates.rows.size()==candidate_count,"Live picker failed to read candidates"):quit(1);return
		owner.candidates.search("zznomatch");await settle_picker(owner)
		check(owner.candidates.phase==owner.candidates.Phase.Ready and owner.candidates.rows.is_empty(),"Live picker search failed")
		owner.candidates.search("");await settle_picker(owner)
		var commits: Array=[];owner.candidates.convicted.connect(func(id,unit):commits.append([id,unit]))
		if picker_view!=null:
			await process_frame;await pointer_click(picker_view.position+picker_view.picker_rect(0).get_center())
		else:owner.candidates.convict(5698)
		await settle_picker(owner)
		applied=commits==[[9,5698]]
		check(applied and owner.phase==owner.Phase.Ready and not owner.rows.any(func(row):return row.crime_id==9),"Live picker conviction did not refresh parent cases")
		if picker_view!=null:picker_view.queue_free();await process_frame
		owner.dispose();picker_actions.queue_free();await process_frame
		var repeated:=await request("justice",intent)
		check(repeated.get("status")==C.ManagementStatus.Rejected and repeated.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,
			"Repeated old conviction was not rejected")
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"counts":counts,"witnesses":report_count,"stale_tabs":3,"controller_tabs":3,
		"closed_read_retired":true,"candidate_count":candidate_count,"candidate_queries":3,"sort_scopes":reference.sorts.size(),"convicted":applied,"picker_controller":applied}));result.close()
	quit(1 if failed else 0)
