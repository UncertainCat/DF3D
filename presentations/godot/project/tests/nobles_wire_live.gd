extends "res://tests/item_carrier_wire_live.gd"
func normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=normalize(value[key])
		return result
	if value is Array:return value.map(normalize)
	return int(value) if typeof(value)==TYPE_FLOAT else value
func page(offset: int,revision: int) -> Dictionary:
	return await request("nobles",{"action":C.ManagementAction.NoblesRead,"offset":offset,"limit":4,"expected_list_revision":revision})
func check_candidates(revision: int,rows: Array) -> void:
	var native: Dictionary=normalize(JSON.parse_string(FileAccess.get_file_as_string(directory+"/nobles-native.json")))
	for picker in native.pickers:
		var selected: Dictionary=picker.selected
		var target: Dictionary={"entity_id":selected.entity_id,"position_id":selected.position_id,"assignment_id":selected.assignment_id,"draft_slot":0}
		var intent: Dictionary={"action":C.ManagementAction.NoblesCandidates,"offset":0,"limit":64,"expected_list_revision":revision,"target":target,"expected_candidate_revision":0}
		var candidates: Array=[]
		while candidates.size()<picker.candidates.size():
			var reply:=await request("nobles",intent)
			if not check(reply.get("status")==C.ManagementStatus.Ok,"Nobles candidates rejected"):return
			var state: Dictionary=reply.nobles
			check(state.target==target and state.list_revision==revision,"Candidate office identity differs")
			check(state.offset==candidates.size() and state.total==picker.candidates.size(),"Candidate page bounds differ")
			if not check(not state.candidates.is_empty(),"Candidate paging stalled"):return
			if intent.expected_candidate_revision:check(state.candidate_revision==intent.expected_candidate_revision,"Candidate continuation changed")
			candidates.append_array(state.candidates);intent.offset=candidates.size();intent.expected_candidate_revision=state.candidate_revision
		for i in candidates.size():
			for key in ["unit_id","value","caption","no_skills","skills"]:
				check(candidates[i].get(key)==picker.text_reference.rows[i].get(key),"Candidate field differs: "+key)
		intent.offset=0;intent.expected_candidate_revision=intent.expected_candidate_revision ^ 1
		var stale:=await request("nobles",intent)
		check(stale.get("nobles",{}).get("outcome")==C.NoblesOutcome.Stale,"Stale candidate list accepted")
		if picker.position!="manager":continue
		var unit_id: int=-1
		for candidate in candidates:
			if candidate.unit_id>=0 and candidate.unit_id!=selected.unit_id:unit_id=candidate.unit_id;break
		if not check(unit_id>=0,"Manager fixture lacks replacement candidate"):return
		var choices: Array=[{"target":target,"expected_unit_id":selected.unit_id,"unit_id":unit_id}]
		var draft: Dictionary={"action":C.ManagementAction.NoblesRead,"offset":0,"limit":64,"expected_list_revision":revision,"choices":choices}
		var preview:=await request("nobles",draft)
		if not check(preview.get("status")==C.ManagementStatus.Ok,"Owned draft rejected"):return
		var found:=false
		for row in preview.nobles.rows:
			if row.entity_id==target.entity_id and row.position_id==target.position_id and row.assignment_id==target.assignment_id:
				found=true;check(row.unit_id==unit_id,"Owned draft did not select candidate")
		check(found,"Draft office missing")
		draft.action=C.ManagementAction.NoblesCommit;draft.limit=32;draft.expected_list_revision=revision ^ 1
		stale=await request("nobles",draft)
		check(stale.get("nobles",{}).get("outcome")==C.NoblesOutcome.Stale,"Stale appointment commit accepted")
		var fresh:=await request("nobles",{"action":C.ManagementAction.NoblesRead,"offset":0,"limit":64,"expected_list_revision":revision})
		check(fresh.get("nobles",{}).get("rows")==rows,"Draft or stale commit changed simulation overview")
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/nobles-wire-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Nobles attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var rows: Array=[];var revision:=0;var pages:=0
	while pages==0 or rows.size()<reference.size():
		var reply:=await page(rows.size(),revision)
		if not check(reply.get("status")==C.ManagementStatus.Ok,"Nobles read rejected"):quit(1);return
		var state: Dictionary=reply.get("nobles",{})
		check(state.get("offset")==rows.size() and state.get("total")==reference.size(),"Nobles page bounds differ")
		if not check(not state.get("rows",[]).is_empty() or rows.size()==reference.size(),"Nobles paging stalled"):quit(1);return
		if revision:check(state.list_revision==revision,"Nobles continuation revision changed")
		revision=state.list_revision;rows.append_array(state.rows);pages+=1
	for i in rows.size():
		var expected: Dictionary=reference[i];var row: Dictionary=rows[i]
		for key in ["entity_id","position_id","assignment_id","unit_id","nemesis_id","title","squad_caption","holder_caption","can_appoint","has_room_assessment","required_rooms","actual_rooms","required_furniture","actual_furniture","demand_status","mandate_status","help"]:
			var wanted: Variant=normalize(expected.get(key))
			if wanted is Array:wanted=wanted.map(func(value):return int(value))
			check(row.get(key)==wanted,"Nobles field differs: "+key)
		check(row.priority==expected.value,"Nobles priority differs")
	var stale:=await page(0,revision ^ 1)
	check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("nobles",{}).get("outcome")==C.NoblesOutcome.Stale,"Nobles stale revision accepted")
	var end_page:=await page(rows.size(),revision)
	check(end_page.get("status")==C.ManagementStatus.Ok and end_page.get("nobles",{}).get("rows",[1]).is_empty(),"Nobles end page differs")
	await check_candidates(revision,rows)
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var model=preload("res://scripts/nobles_state.gd").new();model.configure(actions);model.open()
	deadline=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	check(model.phase==model.Phase.Ready and model.rows==rows,"Live Nobles controller differs from transport")
	var native: Dictionary=normalize(JSON.parse_string(FileAccess.get_file_as_string(directory+"/nobles-native.json")))
	var manager: Dictionary=native.pickers[0].selected
	var target: Dictionary={"entity_id":manager.entity_id,"position_id":manager.position_id,"assignment_id":manager.assignment_id,"draft_slot":0}
	model.begin_appointment(target)
	deadline=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.CandidatesReading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	if not check(model.phase==model.Phase.CandidatesReady and model.candidates.size()==native.pickers[0].candidates.size(),"Live picker controller did not finish native pages"):quit(1);return
	var chosen: int=-1
	for candidate in model.candidates:
		if candidate.unit_id>=0 and candidate.unit_id!=manager.unit_id:chosen=candidate.unit_id;break
	model.choose_candidate(chosen)
	deadline=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	check(model.phase==model.Phase.Ready and model.choices.size()==1,"Live draft controller rejected selection")
	var selected:=false
	for row in model.rows:
		if model.office(row)==target:selected=row.unit_id==chosen
	check(selected,"Live controller failed to project selected holder")
	model.open()
	deadline=Time.get_ticks_msec()+5000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	check(model.phase==model.Phase.Ready and model.rows==rows and model.choices.is_empty(),"Abandoned draft changed fresh overview")
	if OS.get_environment("DF3D_NOBLES_RENDER")=="1":
		if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Nobles assets unavailable"):quit(1);return
		root.size=Vector2i(1200,800)
		var view=preload("res://scripts/nobles_view.gd").new();root.add_child(view);view.configure_nobles(world,model);view.layout(Vector2(1200,800))
		model.begin_appointment(target)
		deadline=Time.get_ticks_msec()+5000
		while model.phase==model.Phase.CandidatesReading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		check(model.phase==model.Phase.CandidatesReady,"Rendered picker did not load")
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-picker-view.png")
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=view.position+Vector2(100,view.list_top()+54);click.pressed=true
		root.push_input(click,true);click=click.duplicate();click.pressed=false;root.push_input(click,true)
		deadline=Time.get_ticks_msec()+5000
		while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		check(model.phase==model.Phase.Ready and model.choices.size()==1,"Picker pointer did not stage candidate")
		model.begin_appointment(target)
		deadline=Time.get_ticks_msec()+5000
		while model.phase==model.Phase.CandidatesReading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true)
		check(model.phase==model.Phase.Ready and model.choices.size()==1,"Picker Escape discarded prior draft or failed to return")
		model.open()
		deadline=Time.get_ticks_msec()+5000
		while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		check(model.rows==rows,"Picker pointer draft changed simulation")
		for token in ["NOBLES_ADD","NOBLES_ASSIGN_SYMBOL","NOBLES_OFFICE_GOOD","NOBLES_FURN_MISSING","NOBLES_DEMANDS_NA","NOBLES_MANDATES_TIME_WARN_1"]:check(view.art.texture(token)!=null,"Missing native Nobles artwork: "+token)
		for row in model.rows:
			if row.unit_id>=0:check(row.has("appearance") and view.portraits.get(row.unit_id,{}).get("texture")!=null,"Nobles holder portrait unavailable")
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-view.png")
		view.set_process(false)
		for sample in [["rooms",Vector2(552,126)],["furniture",Vector2(680,126)],["mandates",Vector2(760,126)],["description",Vector2(24,342)]]:
			view.hovered=view.hover_at(sample[1]);check(view.hovered.get("kind")==sample[0],"Nobles live hover selection differs: "+sample[0]);view.queue_redraw()
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/nobles-help-"+sample[0]+".png")
		root.size=Vector2i(1600,900);view.layout(Vector2(1600,900));view.hovered={};view.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-wide.png")
		var accounting_row:=-1
		for index in model.rows.size():
			if model.rows[index].get("help",{}).has("accounting"):accounting_row=index;break
		check(accounting_row>=0,"Live fixture lacks accounting holder")
		if accounting_row>=0:
			view.hovered=view.hover_at(Vector2(view.status_x()+320,view.list_top()+accounting_row*36+18));check(view.hovered.get("kind")=="accounting","Nobles accounting hover missing")
			view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/nobles-help-accounting.png")
		view.queue_free();await process_frame
	model.refresh();model.close()
	for frame in 5:world.poll();await process_frame
	check(model.phase==model.Phase.Closed and model.rows.is_empty() and model.ticket==0,"Closed Nobles controller accepted live read")
	model.dispose();actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"controller_ready":true,"closed_read_retired":true,"success":not failed,"rows":rows.size(),"pages":pages,"stale_rejected":true,"empty_end_page":true}));result.close()
	quit(1 if failed else 0)
