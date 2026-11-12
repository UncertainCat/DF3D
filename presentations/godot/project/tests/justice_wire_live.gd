extends "res://tests/item_carrier_wire_live.gd"
func page(tab: int,offset: int,revision: int) -> Dictionary:
	return await request("justice",{"action":C.ManagementAction.JusticeRead,"tab":tab,"offset":offset,"limit":4,"expected_list_revision":revision})
func details(tab: int,id: int,offset: int,list_revision: int,case_revision: int) -> Dictionary:
	return await request("justice",{"action":C.ManagementAction.JusticeCaseRead,"tab":tab,"crime_id":id,"offset":offset,"limit":8,"expected_list_revision":list_revision,"expected_case_revision":case_revision})
func pointer_click(point: Vector2,shift:=false,ctrl:=false) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.shift_pressed=shift;event.ctrl_pressed=ctrl
		Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func activate_picker_key(view) -> void:
	var focused:=OS.get_environment("DF3D_JUSTICE_SELECT_FOCUSED")=="1"
	if focused:
		var focus:=InputEventKey.new();focus.pressed=true;focus.ctrl_pressed=true;focus.keycode=KEY_F;Input.parse_input_event(focus);await create_timer(0.1).timeout
	check(view.search.has_focus()==focused,"Activation filter focus differs")
	# Installed SELECT is REPEAT_NOT and excludes modifiers. Neither may submit.
	var model=view.state.candidates;var revision: int=model.candidate_revision
	for modifier in ["ctrl_pressed","shift_pressed","alt_pressed","meta_pressed","echo"]:
		var ignored:=InputEventKey.new();ignored.pressed=true;ignored.keycode=KEY_ENTER;ignored.set(modifier,true);Input.parse_input_event(ignored);await create_timer(0.1).timeout
		check(model.phase==model.Phase.Ready and model.ticket==0 and model.candidate_revision==revision,"Modified/repeated Enter activated a candidate")
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_KP_ENTER if focused else KEY_ENTER;Input.parse_input_event(key);await create_timer(0.1).timeout
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
	if OS.get_environment("DF3D_JUSTICE_ROSTER_RESIZE")=="1":await roster_resize();return
	if OS.get_environment("DF3D_JUSTICE_ROSTER_RETURN")=="1":await roster_return();return
	if OS.get_environment("DF3D_JUSTICE_LIST_NAV")=="1" or OS.get_environment("DF3D_JUSTICE_ROSTER_NAV")=="1":await candidate_list_navigation();return
	if OS.get_environment("DF3D_JUSTICE_PICKER_NAV")=="1":await picker_navigation();return
	if OS.get_environment("DF3D_JUSTICE_KEYBOARD")=="1" or OS.get_environment("DF3D_JUSTICE_ROSTER_SELECT")=="1":await keyboard_focus();return
	if OS.get_environment("DF3D_JUSTICE_CANDIDATE_HOVER")=="1":await candidate_hover();return
	if OS.get_environment("DF3D_JUSTICE_WIRE_GRAPH")=="1":await run_graph(reference.graph);return
	if OS.get_environment("DF3D_JUSTICE_WIRE_INTELLIGENCE")=="1":await run_intelligence(reference.intelligence);return
	if OS.get_environment("DF3D_JUSTICE_WIRE_CONVICTS")=="1":await run_convicts(reference.convicts);return
	if OS.get_environment("DF3D_JUSTICE_WIRE_GUARD")=="1":await run_guard(reference.guard);return
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
				var recipe_file:=FileAccess.open(directory+"/justice-picker-recipes.json",FileAccess.WRITE)
				recipe_file.store_string(JSON.stringify(controller.candidates.rows.slice(0,view.picker_capacity()),"\t"))
				recipe_file.close()
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
	var interrogated:=false
	if OS.get_environment("DF3D_JUSTICE_WIRE_INTERROGATE")=="1":
		var interview_actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(interview_actions);interview_actions.configure(world,true)
		var owner=preload("res://scripts/justice_state.gd").new();owner.configure(interview_actions);owner.open()
		var interview_view
		if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
			interview_view=preload("res://scripts/justice_view.gd").new();root.add_child(interview_view);interview_view.configure_justice(world,owner);interview_view.layout(Vector2(1200,800))
		await settle_controller(owner)
		if interview_view!=null:await pointer_click(interview_view.position+interview_view.interrogate_rect().get_center())
		else:owner.open_candidates(true)
		await settle_picker(owner)
		var picker=owner.candidates
		if not check(picker.phase==picker.Phase.Ready and picker.interrogate and picker.rows.size()==candidate_count,"Interrogate button failed"):quit(1);return
		var original: Array=picker.rows.map(func(row):return row.unit_id)
		check(original==reference.interrogation.map(func(row):return int(row.unit_id)),"Interrogate candidate order differs")
		var target: int=picker.rows[6].unit_id
		check(target==7123 and not picker.rows[6].interrogation_pending,"Interrogate baseline target differs")
		var old_intent: Dictionary=picker._intent(C.ManagementAction.JusticeInterrogate);old_intent.unit_id=target;old_intent.expected_selected=false
		if interview_view!=null and OS.get_environment("DF3D_JUSTICE_SELECT")=="1":
			for _step in 6:
				var down:=InputEventKey.new();down.pressed=true;down.keycode=KEY_DOWN;Input.parse_input_event(down);await create_timer(0.1).timeout
			check(picker.cursor_id==target,"Keyboard did not select the interview subject")
			await activate_picker_key(interview_view)
		elif interview_view!=null:await pointer_click(interview_view.position+interview_view.picker_rect(6).position+Vector2(296,18))
		else:picker.toggle_interrogation(target)
		await settle_picker(owner)
		if not check(picker.phase==picker.Phase.Ready,"Interrogate did not settle"):quit(1);return
		check(picker.rows.map(func(row):return row.unit_id)==original and picker.rows[6].interrogation_pending,"Scheduling reordered the picker or failed")
		if interview_view!=null and OS.get_environment("DF3D_JUSTICE_SELECT")=="1":check(interview_view.search.has_focus()==(OS.get_environment("DF3D_JUSTICE_SELECT_FOCUSED")=="1"),"Interview activation lost filter focus")
		if interview_view!=null:
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/justice-interrogate-view.png")
			var down:=InputEventKey.new();down.pressed=true;down.keycode=KEY_DOWN;Input.parse_input_event(down);await create_timer(0.1).timeout
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-interrogate-away-view.png")
			var up:=InputEventKey.new();up.pressed=true;up.keycode=KEY_UP;Input.parse_input_event(up);await create_timer(0.1).timeout
		var repeated:=await request("justice",old_intent)
		check(repeated.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Repeated interrogation receipt accepted")
		if interview_view!=null:await pointer_click(interview_view.position+interview_view.sort_rect(0).get_center())
		else:picker.select_sort(C.JusticeCandidateColumn.Name)
		await settle_picker(owner)
		check(picker.phase==picker.Phase.Ready and picker.rows[0].unit_id==target,"Sort failed to group scheduled interview first")
		if interview_view!=null and OS.get_environment("DF3D_JUSTICE_SELECT")=="1":await activate_picker_key(interview_view)
		elif interview_view!=null:await pointer_click(interview_view.position+interview_view.picker_rect(0).position+Vector2(296,18))
		else:picker.toggle_interrogation(target)
		await settle_picker(owner)
		interrogated=picker.phase==picker.Phase.Ready and picker.rows[0].unit_id==target and not picker.rows[0].interrogation_pending
		check(interrogated,"Interrogation cancellation failed or moved the row")
		if interview_view!=null:interview_view.queue_free();await process_frame
		owner.dispose();interview_actions.queue_free();await process_frame
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
			await process_frame
			if OS.get_environment("DF3D_JUSTICE_SELECT")=="1":await activate_picker_key(picker_view)
			else:await pointer_click(picker_view.position+picker_view.picker_rect(0).get_center())
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
		"closed_read_retired":true,"candidate_count":candidate_count,"candidate_queries":3,"sort_scopes":reference.sorts.size(),"interrogated":interrogated,"convicted":applied,"picker_controller":applied}));result.close()
	quit(1 if failed else 0)

func roster_resize() -> void:
	root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Roster resize assets unavailable")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions)
	var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller)
	var samples: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-keyboard.json"));var mode: String="";var index:=0
	for sample: Dictionary in samples:
		index+=1;root.size=Vector2i(int(sample.width),int(sample.height));view.layout(Vector2(root.size))
		var model=controller.guard if sample.tab=="Fortress guard" else controller.convicts
		if mode!=sample.tab:
			controller.open(3 if sample.tab=="Fortress guard" else 4);mode=sample.tab
			if mode=="Fortress guard":await settle_guard(model)
			else:await settle_convicts(model)
			var down:=InputEventKey.new();down.pressed=true;down.keycode=KEY_DOWN;Input.parse_input_event(down);await create_timer(0.1).timeout
		if mode=="Convicts":await settle_convicts(model)
		await create_timer(0.1).timeout
		check(model.phase==model.Phase.Ready and model.cursor_id==int(sample.ids[int(sample.cursor)]),"Resize changed roster selection")
		if mode=="Convicts":check(model.detail.get("unit_id")==model.cursor_id,"Resize changed convict detail target")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-roster-resize-view-"+str(index)+".png")
	controller.dispose();view.queue_free();actions.queue_free();world.queue_free();await process_frame
	var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"roster_resize_states":samples.size()}));result.close();quit(1 if failed else 0)

func roster_return() -> void:
	root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Roster return assets unavailable")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open(3)
	var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
	var samples: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-keyboard.json"));var attempt:=0
	for sample: Dictionary in samples:
		var next: int=int(sample.attempt);var tab:=3 if sample.tab=="Fortress guard" else 4
		if next!=attempt:
			if next==5:controller.close();controller.open(3)
			elif next>1:await pointer_click(view.position+view.tab_rect(tab).get_center())
			attempt=next
		var model=controller.guard if tab==3 else controller.convicts
		if tab==3:await settle_guard(model)
		else:await settle_convicts(model)
		if sample.label=="prepared":
			await pointer_click(view.position+view.search.position+Vector2(24,18))
			var typed:=InputEventKey.new();typed.pressed=true;typed.keycode=KEY_O;typed.unicode=111;Input.parse_input_event(typed);await create_timer(0.1).timeout
			if tab==3:await settle_guard(model)
			else:await settle_convicts(model)
			await pointer_click(view.position+view.guard_sort_rect(0).get_center())
			if tab==3:await settle_guard(model)
			else:await settle_convicts(model)
			var down:=InputEventKey.new();down.pressed=true;down.keycode=KEY_DOWN;Input.parse_input_event(down);await create_timer(0.1).timeout
			if tab==4:await settle_convicts(model)
		check(model.phase==model.Phase.Ready and model.query==sample.query and model.rows.map(func(row):return row.unit_id)==sample.ids.map(func(id):return int(id)),"Returned roster query/order differs")
		check(model.cursor_id==int(sample.ids[int(sample.cursor)]) and model.first==int(sample.scrolling[-1].scroll),"Returned roster selection/scroll differs")
		check(model.priorities==([C.JusticeCandidateColumn.Name] if sample.sorts==["Name"] else [C.JusticeCandidateColumn.Category]),"Returned roster sort differs")
		check(view.search.has_focus()==sample.focused,"Roster sort/tab filter focus differs")
		if tab==4:check(model.detail.get("unit_id")==model.cursor_id,"Returned convict details differ")
		if sample.label!="initial":
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-roster-return-view-"+str(attempt)+".png")
	controller.dispose();view.queue_free();actions.queue_free();world.queue_free();await process_frame
	var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"roster_return_states":samples.size()}));result.close();quit(1 if failed else 0)

func candidate_list_navigation() -> void:
	root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Justice list navigation assets unavailable")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open()
	var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800));await settle_controller(controller)
	var observations: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-keyboard.json"));var mode: String="";var index:=0;var checked:=0
	var keys: Dictionary={"STANDARDSCROLL_UP":KEY_UP,"STANDARDSCROLL_DOWN":KEY_DOWN,"STANDARDSCROLL_PAGEUP":KEY_PAGEUP,"STANDARDSCROLL_PAGEDOWN":KEY_PAGEDOWN}
	for observation: Dictionary in observations:
		index+=1
		if observation.tab!=mode:
			if observation.tab in ["Fortress guard","Convicts"]:
				controller.open(3 if observation.tab=="Fortress guard" else 4)
				if observation.tab=="Fortress guard":await settle_guard(controller.guard)
				else:await settle_convicts(controller.convicts)
			else:
				controller.candidates.close();controller.open_candidates(observation.tab=="Interrogate");await settle_picker(controller)
			mode=observation.tab
		if observation.label=="filter":
			var event:=InputEventKey.new();event.keycode=KEY_F;event.ctrl_pressed=true;event.pressed=true;Input.parse_input_event(event);await create_timer(0.1).timeout
		if keys.has(observation.label):
			var event:=InputEventKey.new();event.keycode=keys[observation.label];event.pressed=true;Input.parse_input_event(event);await create_timer(0.1).timeout
		if observation.label.begins_with("CONTEXT_"):continue
		if mode=="Convicts":await settle_convicts(controller.convicts)
		var model=controller.guard if mode=="Fortress guard" else controller.convicts if mode=="Convicts" else controller.candidates
		var selected: int=model.rows.find_custom(func(row):return row.unit_id==model.cursor_id)
		var native_scroll: Dictionary=observation.scrolling[-1]
		check(selected==int(observation.cursor) and model.first==int(native_scroll.scroll),"Candidate keyboard selection/scroll differs at "+str(index))
		check(view.search.has_focus()==observation.focused,"Candidate navigation filter focus differs")
		if mode=="Convicts":
			var expected: Array=[];var detail: Dictionary=model.detail
			for line in detail.get("sentence",[]):expected.append({"text":line,"color":15})
			if detail.has("officer"):expected.append({"text":detail.officer,"color":9})
			for crime in detail.get("crimes",[]):
				if not crime.caption.is_empty():expected.append({"text":crime.caption,"color":15})
				if crime.has("injured_party"):expected.append({"text":crime.injured_party,"color":7})
			var native_detail: Array=[]
			for line in observation.detail:native_detail.append({"text":line.text,"color":int(line.color)})
			check(detail.get("unit_id")==model.cursor_id and expected==native_detail,"Convict keyboard selection did not update native details: "+JSON.stringify(expected)+" versus "+JSON.stringify(native_detail))
		checked+=1
		if keys.has(observation.label):
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-list-nav-view-"+str(index)+".png")
	controller.close();controller.dispose();view.queue_free();actions.queue_free();world.queue_free();await process_frame
	var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"keyboard_states":checked}));result.close();quit(1 if failed else 0)

func picker_navigation() -> void:
	root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Justice navigation assets unavailable")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open()
	var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800));await settle_controller(controller)
	var selected: int=controller.selected_id;var detail: Dictionary=controller.detail.duplicate(true)
	for mode in 4:
		controller.open_candidates(mode%2==0);await settle_picker(controller)
		check(view.picker_open(),"Navigation picker did not open")
		if mode>=2:
			var focus:=InputEventKey.new();focus.keycode=KEY_F;focus.ctrl_pressed=true;focus.pressed=true;Input.parse_input_event(focus);await process_frame
			check(view.search.has_focus(),"Navigation filter not focused")
		for modifier in [true,false]:
			var event:=InputEventKey.new();event.keycode=KEY_LEFT;event.pressed=true;event.ctrl_pressed=modifier;Input.parse_input_event(event);await process_frame
			check(view.picker_open()==modifier,"Picker Left modifier boundary differs")
		check(controller.phase==controller.Phase.Ready and controller.selected_id==selected and controller.detail==detail and not view.search.has_focus(),"Picker return changed case or retained focus")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-nav-view-"+str(mode)+".png")
		var right:=InputEventKey.new();right.keycode=KEY_RIGHT;right.pressed=true;Input.parse_input_event(right);await process_frame
		check(not view.picker_open() and controller.detail==detail,"Right reopened returned picker")
	controller.close();controller.dispose();view.queue_free();actions.queue_free();world.queue_free();await process_frame
	var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"picker_returns":4,"case_retained":true}));result.close();quit(1 if failed else 0)

func keyboard_focus() -> void:
	root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Justice keyboard assets unavailable")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions)
	var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
	for mode in 4:
		controller.open([3,4,0,0][mode])
		if mode==0:await settle_guard(controller.guard)
		elif mode==1:await settle_convicts(controller.convicts)
		else:await settle_controller(controller);controller.open_candidates(mode==2);await settle_picker(controller)
		check(view.search.visible and not view.search.has_focus(),"Justice filter unexpectedly focused on open")
		if mode<2:await roster_enter_no_action(view,controller.guard if mode==0 else controller.convicts,false)
		for variant in ["shift","alt","meta","repeat","plain","filter"]:
			var event:=InputEventKey.new();event.keycode=KEY_F;event.pressed=true;event.ctrl_pressed=variant!="plain";event.shift_pressed=variant=="shift";event.alt_pressed=variant=="alt";event.meta_pressed=variant=="meta";event.echo=variant=="repeat"
			Input.parse_input_event(event);await process_frame
			check(view.search.has_focus()==(variant=="filter"),"Justice filter shortcut modifiers differ: "+variant)
		if mode<2:await roster_enter_no_action(view,controller.guard if mode==0 else controller.convicts,true)
		var typed:=InputEventKey.new();typed.keycode=KEY_Z;typed.unicode=122;typed.pressed=true;Input.parse_input_event(typed)
		await process_frame
		var model=controller.guard if mode==0 else controller.convicts if mode==1 else controller.candidates
		check(model.query=="z","Focused Justice filter did not submit typed query")
		if mode==0:await settle_guard(model)
		elif mode==1:await settle_convicts(model)
		else:await settle_picker(controller)
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-keyboard-view-"+str(mode)+".png")
		controller.close();await process_frame
		check(not view.search.has_focus(),"Closed Justice filter retained typing focus")
	controller.dispose();view.queue_free();actions.queue_free();world.queue_free();await process_frame
	var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"filter_modes":4,"typed_queries":4,"close_retired":true}));result.close();quit(1 if failed else 0)

func roster_enter_no_action(view,model,focused: bool) -> void:
	var id: int=model.cursor_id;var revision: int=model.revision
	for code in [KEY_ENTER,KEY_KP_ENTER]:
		var event:=InputEventKey.new();event.pressed=true;event.keycode=code;Input.parse_input_event(event);await create_timer(0.1).timeout
		check(view.search.has_focus()==focused and model.cursor_id==id and model.revision==revision and model.phase==model.Phase.Ready and model.ticket==0,"Roster Enter changed selection, focus or dispatched a read/action")

func candidate_hover() -> void:
	root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Candidate hover assets unavailable")
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open()
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world);help.layout(Vector2(1200,800))
	var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller,help);view.layout(Vector2(1200,800))
	await settle_controller(controller)
	var observations: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-candidate-hover.json"))
	var mode: String="";var index:=0
	for observation: Dictionary in observations:
		index+=1
		if mode!=observation.tab:
			controller.candidates.close();controller.open_candidates(observation.tab=="Interrogate");await settle_picker(controller);mode=observation.tab
		check(controller.candidates.phase==controller.candidates.Phase.Ready,"Candidate hover picker unavailable")
		var event:=InputEventMouseMotion.new();event.position=Vector2(observation.x,observation.y);event.global_position=event.position
		Input.parse_input_event(event);await create_timer(0.1).timeout
		var expected: String="detail_widget_"+observation.kind if observation.kind in ["name","category","profession"] else "owner_filter" if observation.kind=="filter" else ""
		check(help.displayed==expected,"Candidate hover differs: "+mode+"/"+observation.kind)
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-candidate-hover-view-"+str(index)+".png")
	view.pointer_position=view.search.get_rect().get_center();view.pointer_known=true;view.update_hover()
	check(help.widget_owner==view.get_instance_id(),"Candidate filter hover not owned")
	controller.candidates.close();await process_frame;view.update_hover()
	check(help.widget_owner==0 and help.state.owner==0,"Closing candidate picker retained hover")
	controller.close();controller.dispose();view.queue_free();help.queue_free();actions.queue_free();world.queue_free();await process_frame
	var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"candidate_hover_targets":index,"close_retired":true}));result.close()
	quit(1 if failed else 0)

func settle_guard(guard) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while guard.phase in [guard.Phase.Reading,guard.Phase.Navigating] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
func run_guard(reference: Dictionary) -> void:
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open(3)
	var guard=controller.guard;var view
	if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
		root.size=Vector2i(1200,800)
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Guard assets unavailable")
		view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
	await settle_guard(guard)
	if not check(guard.phase==guard.Phase.Ready and guard.rows.size()==reference.members.size(),"Guard roster failed to load"):quit(1);return
	check(guard.caption==reference.caption and guard.color==reference.color,"Guard capacity differs")
	for i in guard.rows.size():
		check(guard.rows[i].unit_id==reference.members[i].unit_id and guard.rows[i].rank==reference.members[i].rank,"Guard ID/rank differs")
	var baseline: Array=guard.rows.duplicate(true);var revision: int=guard.revision
	if view!=null and OS.get_environment("DF3D_JUSTICE_HOVER")=="1":await roster_hover(view,controller)
	if view!=null:
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/justice-guard-view.png")
	var stale:=await request("justice",{"action":C.ManagementAction.JusticeGuardRead,"tab":3,"offset":0,"limit":32,"expected_list_revision":revision+1,"query":"","sorts":[{"column":0,"reverse":false}]})
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Stale guard receipt accepted")
	guard.search("zznomatch");await settle_guard(guard)
	check(guard.phase==guard.Phase.Ready and guard.rows.is_empty() and guard.caption==reference.caption,"Guard empty filter failed")
	guard.search("");await settle_guard(guard)
	check(guard.rows==baseline,"Guard clear filter did not restore roster")
	if not baseline.is_empty():
		var seen: Array=[];guard.inspect_ready.connect(func(tile,id):seen.append({"tile":tile,"id":id}))
		if view!=null:await pointer_click(view.position+view.guard_rect(0).position+Vector2(332,18))
		else:guard.inspect(baseline[0].unit_id)
		await settle_guard(guard)
		check(seen.size()==1 and seen[0].id==baseline[0].unit_id,"Guard unit-sheet button failed")
		if view!=null and baseline[0].has("position"):
			var centered: Array=[];view.focus_requested.connect(func(tile):centered.append(tile))
			await pointer_click(view.position+view.guard_rect(0).position+Vector2(300,18))
			check(centered==[baseline[0].position],"Guard recenter button failed")
	controller.close();controller.dispose()
	if view!=null:view.queue_free()
	actions.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"guard_count":baseline.size(),"guard_navigation":not baseline.is_empty()}));file.close()
	world.queue_free();await process_frame
	quit(1 if failed else 0)

func settle_convicts(roster) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while roster.phase in [roster.Phase.Reading,roster.Phase.DetailReading,roster.Phase.Navigating] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout

func roster_hover(view,controller) -> void:
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world);help.layout(Vector2(1200,800));view.hover_help=help
	var observations: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-hover.json"))
	var index:=0
	for observation: Dictionary in observations:
		index+=1
		var tab:=3 if observation.tab=="Fortress guard" else 4
		if controller.tab!=tab:
			controller.select_tab(tab);await settle_convicts(controller.convicts)
		var event:=InputEventMouseMotion.new();event.position=Vector2(observation.x,observation.y);event.global_position=event.position
		Input.parse_input_event(event);await create_timer(0.65).timeout
		var expected: String="detail_widget_"+observation.kind if observation.kind in ["name","category","profession"] else "owner_filter" if observation.kind=="filter" else "residents_"+("details" if observation.kind=="view" else "recenter") if observation.kind in ["view","recenter"] else ""
		check(help.displayed==expected,"Justice hover differs: "+observation.tab+"/"+observation.kind)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/justice-hover-view-"+str(index)+".png")
	view.hide();await process_frame
	check(help.widget_owner==0 and help.state.owner==0,"Hidden Justice retained hover")
	view.show();controller.select_tab(3);await settle_guard(controller.guard)
	view.hover_help=null;help.queue_free();await process_frame
func run_convicts(reference: Array) -> void:
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open(4)
	var roster=controller.convicts;var view
	if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
		root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Convicts assets unavailable")
		view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
	await settle_convicts(roster)
	if not check(roster.phase==roster.Phase.Ready and roster.rows.size()==reference.size(),"Convicts roster failed to settle"):quit(1);return
	for i in reference.size():
		check(roster.rows[i].unit_id==reference[i].unit_id,"Convicts native order differs")
		for key in ["color","alternate","effect"]:
			var expected_color=reference[i].name_color[key]
			if expected_color is Array:expected_color=expected_color.map(func(value):return int(value))
			else:expected_color=int(expected_color)
			check(roster.rows[i].name_color[key]==expected_color,"Convicts native name color differs")
		if i>0:
			if view!=null:await pointer_click(view.position+view.guard_rect(i).position+Vector2(80,18))
			else:roster.select_unit(reference[i].unit_id)
			await settle_convicts(roster)
		var d: Dictionary=roster.detail;var r: Dictionary=reference[i]
		check(d.get("unit_id")==r.unit_id and d.get("sentence")==r.sentence and d.get("officer")==r.get("officer"),"Convict sentence differs")
		check(d.get("crimes",[]).size()==r.crimes.size(),"Convict crime count differs")
		for j in mini(d.get("crimes",[]).size(),r.crimes.size()):
			check(d.crimes[j].crime_id==r.crimes[j].id and d.crimes[j].caption==r.crimes[j].caption and d.crimes[j].get("injured_party")==r.crimes[j].get("injured_party"),"Convict crime text differs")
		if view!=null and i==0:
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/justice-convicts-view.png")
			for phase in [0,500]:
				view.ticks_override=phase;view.queue_redraw()
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-convicts-phase-%d.png"%phase)
			view.ticks_override=-1
	var prior: Array=roster.rows.duplicate(true)
	roster.search("zznomatch");await settle_convicts(roster);check(roster.rows.is_empty() and roster.detail.is_empty(),"Convicts empty search retained details")
	roster.search("");await settle_convicts(roster);check(roster.rows==prior,"Convicts clear search changed roster")
	if not prior.is_empty():
		var seen: Array=[];roster.inspect_ready.connect(func(tile,id):seen.append(id))
		if view!=null:await pointer_click(view.position+view.guard_rect(0).position+Vector2(332,18))
		else:roster.inspect(prior[0].unit_id)
		await settle_convicts(roster);check(seen==[prior[0].unit_id],"Convicts sheet navigation failed")
	var stale:=await request("justice",{"action":C.ManagementAction.JusticeConvictDetailRead,"tab":4,"offset":0,"limit":32,"expected_list_revision":roster.revision,"expected_case_revision":roster.detail.get("revision",0)+1,"unit_id":roster.cursor_id,"query":"","sorts":[{"column":0,"reverse":false}]})
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Stale convict detail accepted")
	controller.dispose();if view!=null:view.queue_free()
	actions.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"convicts":reference.size(),"selection_and_filter":true}));file.close()
	quit(1 if failed else 0)

func settle_intelligence(model) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
func run_intelligence(reference: Array) -> void:
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open(5)
	var model=controller.intelligence;var view
	if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
		root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Intelligence assets unavailable")
		view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
	await settle_intelligence(model)
	check(model.phase==model.Phase.Ready and model.rows.size()==reference.size(),"Intelligence list did not settle")
	if OS.get_environment("DF3D_JUSTICE_INTELLIGENCE_EMPTY")=="1":
		var deadline:=Time.get_ticks_msec()+5000
		while model.graph.phase==model.graph.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		check(model.empty(),"Empty Intelligence not confirmed by both native reads")
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/justice-intelligence-empty-view.png")
		controller.dispose();view.queue_free();actions.queue_free();await process_frame
		var result:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);result.store_string(JSON.stringify({"success":not failed,"empty_intelligence":true}));result.close()
		quit(1 if failed else 0);return
	for i in mini(model.rows.size(),reference.size()):check(model.rows[i].title==reference[i].title and model.rows[i].officer==reference[i].officer,"Intelligence report order or captions differ")
	if view!=null:
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/justice-intelligence-roster-view.png")
		await pointer_click(view.position+view.intelligence_rect(0).position+Vector2(80,18))
	else:model.select_report(0)
	await settle_intelligence(model)
	check(model.phase==model.Phase.Ready and model.lines==reference[0].lines,"Intelligence native report lines differ")
	if view!=null:
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/justice-intelligence-detail-view.png")
		if OS.get_environment("DF3D_JUSTICE_REPORT_SCROLL")=="1":
			var samples: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/justice-intelligence.json"))
			for step in [{"name":"report-wheel","shift":false},{"name":"report-page","shift":true},{"name":"report-arrow"}]:
				if step.has("shift"):
					var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;event.position=Vector2(200,250);event.shift_pressed=step.shift
					Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
				else:await pointer_click(Vector2(952,730))
				var expected: Dictionary=samples.filter(func(sample):return sample.name==step.name)[0]
				check(model.first==int(expected.first),"Native report scroll differs: "+step.name)
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-intelligence-"+step.name+"-view.png")
	var stale:=await request("justice",{"action":C.ManagementAction.JusticeIntelligenceRead,"tab":5,"offset":0,"limit":32,"expected_list_revision":model.revision+1,"report_index":0,"text_columns":112})
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Stale report selection accepted")
	controller.dispose();if view!=null:view.queue_free()
	actions.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"intelligence_reports":reference.size()}));file.close()
	quit(1 if failed else 0)

# JSON numbers are floats; Godot container equality distinguishes them from
# the typed transport integers even when scalar numeric equality succeeds.
func graph_reference_integers(value: Variant) -> Variant:
	if typeof(value)==TYPE_FLOAT and value==int(value):return int(value)
	if typeof(value)==TYPE_ARRAY:return value.map(graph_reference_integers)
	if typeof(value)==TYPE_DICTIONARY:
		var converted: Dictionary={}
		for key in value:converted[key]=graph_reference_integers(value[key])
		return converted
	return value
func run_graph(reference: Dictionary) -> void:
	var Service=preload("res://scripts/semantic_action_service.gd");var actions=Service.new();root.add_child(actions);actions.configure(world,true)
	var model=preload("res://scripts/justice_graph_state.gd").new();model.configure(actions);model.open()
	var deadline:=Time.get_ticks_msec()+15000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:await process_frame
	if not check(model.phase==model.Phase.Ready,"Graph controller did not settle"):model.dispose();actions.queue_free();quit(1);return
	var expected: Dictionary=graph_reference_integers(reference);expected.nodes=[]
	for i in expected.organizations.size():
		var org: Dictionary=expected.organizations[i];var first: int=expected.nodes.size();org.first_node=first;org.node_count=org.nodes.size()
		for original in org.nodes:
			var node: Dictionary=original.duplicate(true);node.erase("descendants");node.organization=i
			if node.parent>=0:node.parent+=first
			expected.nodes.append(node)
		org.erase("nodes")
	var evidence:=FileAccess.open(directory+"/justice-graph-wire.json",FileAccess.WRITE);evidence.store_string(JSON.stringify({"expected":expected,"actual":model.graph}));evidence.close()
	check(model.graph==expected,"Graph transport differs from native provider")
	# Limit1 forces the actor and node streams through continuation pages.
	for kind in [1,4]:
		var key: String=["actors","organizations","plots","nodes"][kind-1];var rows: Array=[]
		while rows.size()<expected[key].size():
			var reply:=await request("justice",{"action":C.ManagementAction.JusticeIntelligenceGraphRead,"tab":5,"offset":rows.size(),"limit":1,"expected_list_revision":model.revision,"graph_kind":kind})
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Graph continuation rejected"):break
			var part: Array=reply.justice.graph[key]
			if not check(part.size()==1,"Graph continuation stalled"):break
			rows.append_array(part)
		check(rows==expected[key],"Graph continuation changed order or links")
	var stale:=await request("justice",{"action":C.ManagementAction.JusticeIntelligenceGraphRead,"tab":5,"offset":0,"limit":32,"expected_list_revision":model.revision+1,"graph_kind":1})
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("justice",{}).get("outcome")==C.JusticeOutcome.Stale,"Changed graph receipt accepted")
	model.dispose()
	if OS.get_environment("DF3D_JUSTICE_RENDER")=="1":
		root.size=Vector2i(1200,800);check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Graph assets unavailable")
		var controller=preload("res://scripts/justice_state.gd").new();controller.configure(actions);controller.open(5)
		var view=preload("res://scripts/justice_view.gd").new();root.add_child(view);view.configure_justice(world,controller);view.layout(Vector2(1200,800))
		deadline=Time.get_ticks_msec()+15000
		while (controller.intelligence.graph.phase==model.Phase.Reading or controller.intelligence.phase==controller.intelligence.Phase.Reading) and Time.get_ticks_msec()<deadline:await process_frame
		check(controller.intelligence.graph.phase==model.Phase.Ready,"Rendered graph did not settle")
		for token in ["BUTTON_RECTANGLE","BUTTON_RECTANGLE_DARK","BUTTON_RECTANGLE_LIGHT","BUTTON_CATEGORY_RECTANGLE","BUTTON_CATEGORY_RECTANGLE_SELECTED","HOVER_RECTANGLE"]:
			var texture=view.art.texture(token)
			if texture!=null:texture.get_image().save_png(directory+"/graph-art-"+token+".png")
		for mode in [1,2,3]:
			await pointer_click(view.position+view.intelligence_tab_rect(mode).get_center())
			check(controller.intelligence.mode==mode,"Graph tab click missed")
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/justice-graph-"+["actors","organizations","plots"][mode-1]+"-view.png")
			if mode==1:
				if OS.get_environment("DF3D_JUSTICE_GRAPH_WHEEL")=="1":
					for step in [{"name":"actors-wheel","shift":false,"scroll":1},{"name":"actors-wheel-page","shift":true,"scroll":48}]:
						var event:=InputEventMouseButton.new();event.position=Vector2(200,250);event.global_position=event.position;event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;event.shift_pressed=step.shift
						Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
						check(controller.intelligence.graph_scroll==step.scroll,"Intelligence context scroll differs")
						await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-graph-"+step.name+"-view.png")
					await pointer_click(Vector2(952,730));check(controller.intelligence.graph_scroll==49,"Intelligence down arrow differs")
					await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-graph-actors-arrow-down-view.png")
					await pointer_click(view.position+view.intelligence_tab_rect(2).get_center());await pointer_click(view.position+view.intelligence_tab_rect(1).get_center())
				if OS.get_environment("DF3D_JUSTICE_GRAPH_LARGE")=="1":
					await pointer_click(Vector2(944,716))
					check(controller.intelligence.graph_scroll==47,"Actor scrollbar track step differs from native")
					await process_frame;await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(directory+"/justice-graph-actors-scroll-arrow-view.png")
					await pointer_click(view.position+view.intelligence_tab_rect(2).get_center())
					await pointer_click(view.position+view.intelligence_tab_rect(1).get_center())
				await pointer_click(view.position+view.graph_view.rect(1).position+Vector2(16,24));check(controller.intelligence.graph_selected==1,"Actor row click missed")
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-graph-actor-selected-view.png")
			if mode==2 and OS.get_environment("DF3D_JUSTICE_GRAPH_NAVIGATION")=="1":
				for step in [{"name":"node-selected","point":Vector2(496,340),"node":1},{"name":"node-blank","point":Vector2(96,220),"node":1},{"name":"node-last","point":Vector2(496,412),"node":2}]:
					await pointer_click(step.point)
					check(controller.intelligence.selected_node==step.node,"Graph node selection changed: "+step.name)
					await process_frame;await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(directory+"/justice-graph-"+step.name+"-view.png")
				await pointer_click(view.position+view.intelligence_tab_rect(1).get_center())
				check(controller.intelligence.graph_selected==0 and controller.intelligence.selected_node==-1,"Graph tab return retained selection")
				await pointer_click(view.position+view.intelligence_tab_rect(2).get_center())
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-graph-organizations-return-view.png")
			if mode==2 and OS.get_environment("DF3D_JUSTICE_GRAPH_CONNECTED")=="1":
				for step in [{"name":"organizations-scroll","point":Vector2(944,716)},{"name":"organization-last","point":Vector2(96,690)}]:
					await pointer_click(step.point)
					await process_frame;await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(directory+"/justice-graph-"+step.name+"-view.png")
		if OS.get_environment("DF3D_JUSTICE_GRAPH_MIXED")=="1":
			for step in [{"name":"reports","mode":0,"point":Vector2(96,148)},{"name":"report-detail","mode":0,"point":Vector2(120,190)},{"name":"report-to-actors","mode":1,"point":Vector2(220,148)},{"name":"reports-return","mode":0,"point":Vector2(96,148)}]:
				await pointer_click(step.point)
				deadline=Time.get_ticks_msec()+15000
				while controller.intelligence.phase==controller.intelligence.Phase.Reading and Time.get_ticks_msec()<deadline:await process_frame
				check(controller.intelligence.phase==controller.intelligence.Phase.Ready and controller.intelligence.mode==step.mode,"Mixed Intelligence navigation did not settle")
				check((controller.intelligence.selected>=0)==(step.name=="report-detail"),"Mixed Intelligence report selection differs")
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-graph-"+step.name+"-view.png")
		if OS.get_environment("DF3D_JUSTICE_GRAPH_RESIZE")=="1":
			await pointer_click(view.position+view.intelligence_tab_rect(2).get_center())
			if OS.get_environment("DF3D_JUSTICE_GRAPH_CONNECTED")=="1":
				await pointer_click(Vector2(944,716));await pointer_click(Vector2(96,690));await pointer_click(Vector2(532,568))
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/justice-graph-organization-last-node-view.png")
			root.size=Vector2i(912,552);view.layout(Vector2(912,552))
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/justice-graph-organizations-minimum-view.png")
			root.size=Vector2i(1200,800);view.layout(Vector2(1200,800))
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/justice-graph-organizations-restored-view.png")
		if OS.get_environment("DF3D_JUSTICE_GRAPH_LAYOUT_WIDE")=="1":
			await pointer_click(view.position+view.intelligence_tab_rect(2).get_center())
			# Layout-only fixture, after semantic transport assertions. Mirror the
			# native oracle's owned node inputs without changing gameplay facts.
			var baseline: Dictionary=controller.intelligence.graph.graph.duplicate(true)
			var layout: Dictionary=baseline.duplicate(true);var nodes: Array=[layout.nodes[0].duplicate(true)];var template: Dictionary=layout.nodes.back()
			for i in 32:
				var node: Dictionary=template.duplicate(true);node.parent=0;node.tier=2;nodes.append(node)
			layout.nodes=nodes;layout.organizations[0].node_count=33;controller.intelligence.graph.graph=layout;controller.intelligence.changed.emit()
			await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-graph-layout-wide-view.png")
			for step in [{"name":"layout-wide-right","point":Vector2(924,340),"node":27},{"name":"layout-wide-last","point":Vector2(896,340),"node":32},{"name":"layout-wide-left","point":Vector2(96,340),"node":12}]:
				await pointer_click(step.point);check(controller.intelligence.selected_node==step.node,"Wide chart hitbox differs")
				await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/justice-graph-"+step.name+"-view.png")
			controller.intelligence.graph.graph=baseline
		controller.dispose();view.queue_free();await process_frame
	actions.queue_free();await process_frame
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"success":not failed,"graph_actors":reference.actors.size(),"graph_organizations":reference.organizations.size(),"graph_plots":reference.plots.size(),"paged_nodes":expected.nodes.size()}));file.close()
	quit(1 if failed else 0)
