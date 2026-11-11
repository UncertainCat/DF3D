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
func symbol_step(action: int,token: int) -> Dictionary:
	return {"action":action,"offset":0,"limit":32,"expected_list_revision":0,"step_token":token}
func wait_symbol(model,phase: int) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if model.phase==phase and not model.busy():return true
		await create_timer(0.01).timeout
	return false
func click_at(point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=true;root.push_input(event,true)
	event=event.duplicate();event.pressed=false;root.push_input(event,true)
func type_name_key(code: int,unicode: int=0) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=true;root.push_input(event,true)
func drag_symbol_scrollbar(bar,to_bottom: bool) -> void:
	var grip: Vector2i=bar.thumb()
	var start: Vector2=bar.get_global_transform_with_canvas()*Vector2(8,grip.x*12+6)
	var finish: Vector2=bar.get_global_transform_with_canvas()*Vector2(8,bar.size.y-13 if to_bottom else 13)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;root.push_input(press,true)
	var motion:=InputEventMouseMotion.new();motion.position=finish;motion.relative=finish-start;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	press=press.duplicate();press.pressed=false;press.position=finish;root.push_input(press,true)
	await process_frame
func resize_symbol_picker(owner) -> bool:
	var evidence: Array=[]
	for extent in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=extent;await process_frame;await process_frame
		var panel=owner.panel;var symbols=owner.state.symbols
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-symbol-size-%dx%d.png"%[extent.x,extent.y])
		await drag_symbol_scrollbar(panel.scrollbar,true)
		if not check(symbols.first==symbols.rows.size()-panel.capacity() and not panel.scrollbar.dragging,"Symbol scrollbar failed to reach last row or release drag"):return false
		evidence.append({"width":extent.x,"height":extent.y,"capacity":panel.capacity(),"last_first":symbols.first})
		await drag_symbol_scrollbar(panel.scrollbar,false)
		if not check(symbols.first==0 and not panel.scrollbar.dragging,"Symbol scrollbar failed to return to first row"):return false
	var output=FileAccess.open(directory+"/nobles-symbol-resize.json",FileAccess.WRITE);output.store_string(JSON.stringify(evidence));output.close()
	return true
func exercise_symbol_name(symbols,name_view) -> bool:
	click_at(name_view.position+name_view.component_rect(1).get_center())
	if not check(await wait_symbol(symbols,symbols.Phase.Naming) and symbols.naming.component==1,"Name component selection failed"):return false
	click_at(name_view.position+Vector2(400,90))
	type_name_key(KEY_A,97);type_name_key(KEY_B,98)
	if not check(await wait_symbol(symbols,symbols.Phase.Naming) and symbols.naming.query==PackedByteArray([65,66]),"Rapid name search dropped input"):return false
	type_name_key(KEY_BACKSPACE)
	if not check(await wait_symbol(symbols,symbols.Phase.Naming) and symbols.naming.phase==symbols.naming.Phase.Ready and not symbols.naming.rows.is_empty(),"Filtered word list unavailable"):return false
	type_name_key(KEY_ENTER)
	var word: Dictionary=symbols.naming.rows[0].duplicate(true)
	click_at(name_view.position+name_view.row_rect(0).get_center())
	if not check(await wait_symbol(symbols,symbols.Phase.Naming) and symbols.naming.snapshot.value.words[1]==word.word,"Selected word did not reach native name"):return false
	click_at(name_view.position+name_view.random_rect(1).get_center())
	if not check(await wait_symbol(symbols,symbols.Phase.Naming) and symbols.naming.phase==symbols.naming.Phase.Ready,"Component Random failed"):return false
	var selected: int=symbols.naming.snapshot.value.words[1]
	if not check(symbols.naming.rows.any(func(row):return row.word==selected),"Component Random escaped native filtered choices"):return false
	click_at(name_view.position+Vector2(name_view.size.x-144,30))
	if not check(await wait_symbol(symbols,symbols.Phase.Naming) and symbols.naming.phase==symbols.naming.Phase.Ready,"Whole name Random failed"):return false
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/nobles-symbol-name-controls.png")
	return true
func check_symbol_panel() -> void:
	var reference: Dictionary=normalize(JSON.parse_string(FileAccess.get_file_as_string(directory+"/nobles-symbol-wire-reference.json")))
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Symbol panel assets unavailable"):return
	root.size=Vector2i(1200,800)
	var actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	var interaction=preload("res://tests/ui_host_test.gd").Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();root.add_child(host);host.interaction=interaction
	var owner=preload("res://scripts/nobles_panel.gd").new();root.add_child(owner);owner.configure(world,actions,host);owner.open_panel()
	var deadline:=Time.get_ticks_msec()+5000
	while owner.state.phase==owner.state.Phase.Reading and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
	if not check(owner.state.phase==owner.state.Phase.Ready,"Symbol overview not ready"):return
	var index: int=-1
	for i in owner.state.rows.size():
		if owner.state.office(owner.state.rows[i])==reference.target:index=i;break
	if not check(index>=0,"Symbol office missing"):return
	var panel=owner.panel
	click_at(panel.position+Vector2(panel.status_x()+16,panel.list_top()+index*36+18))
	var symbols=owner.state.symbols
	if not check(await wait_symbol(symbols,symbols.Phase.Ready),"Symbol icon did not open picker"):return
	var artwork_facts:=FileAccess.open(directory+"/nobles-symbol-artwork.json",FileAccess.WRITE)
	artwork_facts.store_string(JSON.stringify(symbols.rows.slice(0,15),"\t"));artwork_facts.close()
	for row in symbols.rows.slice(0,15):check(row.has("appearance") and panel.symbol_icons.get(row.item_id,{}).get("texture")!=null,"Symbol artwork unavailable for item %s: %s"%[row.item_id,row.get("appearance",{})])
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/nobles-symbol-picker-view.png")
	if OS.get_environment("DF3D_NOBLES_SYMBOL_RESIZE")=="1":
		if not await resize_symbol_picker(owner):return
	if OS.get_environment("DF3D_NOBLES_SYMBOL_NAVIGATION")=="1":
		var handoffs: Array=[]
		owner.information_requested.connect(func(caption):handoffs.append(caption);owner.close_panel())
		symbols.toggle(reference.items[0])
		click_at(Vector2(170,75));await process_frame
		if not check(handoffs==["Tasks"] and owner.state.phase==owner.state.Phase.Closed,"Symbol header did not discard draft and hand off"):return
		owner.open_panel();deadline=Time.get_ticks_msec()+10000
		while owner.state.phase==owner.state.Phase.Reading and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
		if not check(owner.state.phase==owner.state.Phase.Ready,"Header handoff blocked reopening"):return
		owner.state.begin_symbols(reference.target)
		if not check(await wait_symbol(symbols,symbols.Phase.Ready),"Header handoff left a pending symbol sequence"):return
		check(symbols.selected.is_empty(),"Header handoff retained discarded checks")
	for item in reference.items:
		var ordinal: int=-1
		for i in symbols.rows.size():
			if symbols.rows[i].item_id==item:ordinal=i;break
		if not check(ordinal>=0,"Symbol row missing"):return
		symbols.seek(maxi(0,ordinal-5),panel.capacity());await process_frame
		click_at(panel.position+Vector2(100,panel.list_top()+(ordinal-symbols.first)*36+18))
	check(symbols.selected.size()==3,"Symbol pointer toggles failed")
	for row in symbols.rows:
		if row.item_id in reference.items:check(symbols.office_caption(row)==symbols.target_caption and not symbols.target_caption.is_empty(),"Selected symbol office caption missing")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/nobles-symbol-selected-view.png")
	click_at(panel.position+Vector2(panel.size.x-48,panel.list_top()-30))
	var artifacts: Array=[]
	var first_name: Dictionary={}
	for i in 3:
		if not check(await wait_symbol(symbols,symbols.Phase.Naming),"Symbol name did not open"):return
		check(symbols.naming.phase==symbols.naming.Phase.Ready,"Name word pages incomplete")
		artifacts.append(symbols.step.naming_artifact_id)
		var name_view=owner.name_panel
		await process_frame
		if i==0:
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/nobles-symbol-name-view.png")
			if OS.get_environment("DF3D_NOBLES_SYMBOL_NAME_CONTROLS")=="1":
				if not await exercise_symbol_name(symbols,name_view):return
			click_at(name_view.position+name_view.clear_rect(0).get_center())
			if not check(await wait_symbol(symbols,symbols.Phase.Naming),"Symbol name edit did not settle"):return
			check(symbols.naming.snapshot.value.words[0]==-1,"Name Clear pointer failed")
			first_name=symbols.naming.snapshot.value.duplicate(true)
			if OS.get_environment("DF3D_NOBLES_SYMBOL_RETIRE")=="1":
				owner.close_panel();owner.open_panel();deadline=Time.get_ticks_msec()+10000
				while owner.state.phase==owner.state.Phase.Reading and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
				if not check(owner.state.phase==owner.state.Phase.Ready,"Retired naming tail blocked reopened overview"):return
				owner.state.begin_symbols(reference.target)
				if not check(await wait_symbol(symbols,symbols.Phase.Ready),"Retired naming tail blocked new symbol picker"):return
				for item in reference.items.slice(1):symbols.toggle(item)
				symbols.dismiss();continue
		click_at(name_view.position+Vector2(name_view.size.x-64,30))
	deadline=Time.get_ticks_msec()+10000
	while owner.state.phase!=owner.state.Phase.Ready and Time.get_ticks_msec()<deadline:world.poll();await create_timer(0.01).timeout
	check(owner.state.phase==owner.state.Phase.Ready and not owner.name_panel.visible and owner.panel.visible,"Symbol Done did not restore overview")
	var output=FileAccess.open(directory+"/nobles-symbol-wire.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"artifacts":artifacts,"items":reference.items,"success":not failed,"pointer_workflow":true,"first_name":first_name}));output.close()
	owner.free();host.free();interaction.free();actions.queue_free();await process_frame
func check_symbols(revision: int) -> void:
	var reference: Dictionary=normalize(JSON.parse_string(FileAccess.get_file_as_string(directory+"/nobles-symbol-wire-reference.json")))
	var intent: Dictionary={"action":C.ManagementAction.NoblesSymbolsRead,"offset":0,"limit":64,"expected_list_revision":revision,"target":reference.target,"expected_candidate_revision":0}
	var symbols: Array=[]
	while symbols.size()<reference.rows.size():
		var reply:=await request("nobles",intent)
		if not check(reply.get("status")==C.ManagementStatus.Ok,"Symbol page rejected"):return
		var state: Dictionary=reply.nobles
		if not check(not state.symbols.is_empty(),"Symbol paging stalled"):return
		symbols.append_array(state.symbols);intent.offset=symbols.size();intent.expected_candidate_revision=state.candidate_revision
	for i in symbols.size():
		for key in ["item_id","value","current_office","selected_office"]:check(symbols[i].get(key)==reference.rows[i].get(key),"Symbol native facts differ: "+key)
	intent.action=C.ManagementAction.NoblesSymbolsApply;intent.offset=0;intent.limit=32;intent.symbol_choices=[]
	for item in reference.items:intent.symbol_choices.push_front({"item_id":item,"selected":true})
	var applied:=await request("nobles",intent)
	if not check(applied.get("nobles",{}).get("outcome")==C.NoblesOutcome.Applied,"Symbol apply failed"):return
	var step: Dictionary=applied.nobles.step
	var duplicate:=await request("nobles",intent)
	check(duplicate.get("nobles",{}).get("outcome")==C.NoblesOutcome.Rejected,"Initial Apply advanced pending sequence")
	var artifacts: Array=[];var old_token:=0
	for index in 3:
		check(step.remaining==2-index,"Symbol tail count differs")
		var naming:=symbol_step(C.ManagementAction.NoblesSymbolNameRead,step.token)
		naming.name_query={"component":0,"query_bytes":[],"cursor":0}
		var named:=await request("nobles",naming)
		if not check(named.get("status")==C.ManagementStatus.Ok,"Symbol name read rejected"):return
		check(named.nobles.name.item_id==reference.items[index],"Symbol elevation order differs")
		check(named.nobles.step==step,"Naming step identity differs")
		artifacts.append(step.naming_artifact_id)
		if index==0:
			var edit:=symbol_step(C.ManagementAction.NoblesSymbolNameEdit,step.token)
			edit.expected_name_revision=named.nobles.name.revision
			edit.name_edit={"mode":0,"target":0,"displayed":0,"word":-1,"part":-1,"query_bytes":[]}
			var edited:=await request("nobles",edit)
			check(edited.get("nobles",{}).get("outcome")==C.NoblesOutcome.Applied,"Symbol name edit rejected")
			named=await request("nobles",naming)
			check(named.get("nobles",{}).get("name",{}).get("value",{}).get("words",[0])[0]==-1,"Symbol name edit did not apply")
		if old_token:
			var stale:=await request("nobles",symbol_step(C.ManagementAction.NoblesSymbolsContinue,old_token))
			check(stale.get("nobles",{}).get("outcome")==C.NoblesOutcome.Stale,"Old symbol step advanced tail")
		old_token=step.token
		var continued:=await request("nobles",symbol_step(C.ManagementAction.NoblesSymbolsContinue,step.token))
		if not check(continued.get("nobles",{}).get("outcome")==C.NoblesOutcome.Applied,"Symbol continuation rejected"):return
		if index<2:step=continued.nobles.step
		else:check(not continued.nobles.has("step"),"Completed symbol sequence retained a step")
	var refreshed:=await page(0,revision)
	check(refreshed.get("status")==C.ManagementStatus.Ok,"Completed symbols blocked overview")
	var output=FileAccess.open(directory+"/nobles-symbol-wire.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"artifacts":artifacts,"items":reference.items,"success":not failed}));output.close()
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
	if OS.get_environment("DF3D_NOBLES_COMMIT_WIRE")=="1":
		if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Owner assets unavailable"):quit(1);return
		var interaction=preload("res://tests/ui_host_test.gd").Interaction.new();root.add_child(interaction)
		var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
		var owner=preload("res://scripts/nobles_panel.gd").new();root.add_child(owner);owner.configure(world,actions,host)
		var destination=preload("res://tests/ui_host_test.gd").View.new();root.add_child(destination);host.register(destination)
		var committing=owner.state
		owner.open_panel();deadline=Time.get_ticks_msec()+5000
		while committing.phase==committing.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		committing.begin_appointment(target);deadline=Time.get_ticks_msec()+5000
		while committing.phase==committing.Phase.CandidatesReading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		if not check(committing.phase==committing.Phase.CandidatesReady,"Commit picker unavailable"):quit(1);return
		committing.choose_candidate(chosen);deadline=Time.get_ticks_msec()+5000
		while committing.phase==committing.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		if not check(committing.phase==committing.Phase.Ready,"Commit draft unavailable"):quit(1);return
		root.size=Vector2i(1600,900);owner._layout();await process_frame
		var accounting_index: int=-1
		for index in committing.rows.size():
			if committing.rows[index].get("help",{}).has("accounting"):accounting_index=index;break
		if not check(accounting_index>=0,"Accounting office missing"):quit(1);return
		var accounting_target: Dictionary=committing.office(committing.rows[accounting_index])
		var original_setting: int=committing.rows[accounting_index].help.accounting.setting
		var accounting_values: Array=[]
		for setting in [0,1,2,3,4,original_setting]:
			var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			click.position=owner.panel.position+Vector2(owner.panel.status_x()+320+setting*32,owner.panel.list_top()+accounting_index*36+18)
			root.push_input(click,true);click=click.duplicate();click.pressed=false;root.push_input(click,true)
			if not check(committing.phase==committing.Phase.Accounting,"Accounting pointer did not submit mutation"):quit(1);return
			deadline=Time.get_ticks_msec()+5000
			while committing.phase in [committing.Phase.Accounting,committing.Phase.Reading] and Time.get_ticks_msec()<deadline:
				world.poll();await create_timer(0.01).timeout
			if not check(committing.phase==committing.Phase.Ready and committing.rows[accounting_index].help.accounting.setting==setting and committing.choices.size()==1,"Accounting did not confirm or lost appointment draft"):quit(1);return
			accounting_values.append(setting)
		var stale_accounting:=await request("nobles",{"action":C.ManagementAction.NoblesAccounting,"offset":0,"limit":32,"expected_list_revision":committing._revision,"choices":committing.choices,"target":accounting_target,"expected_setting":(original_setting+1)%5,"setting":original_setting})
		check(stale_accounting.get("nobles",{}).get("outcome")==C.NoblesOutcome.Stale,"Stale accounting expected setting accepted")
		destination.open_panel();var commit_ticket: int=committing.ticket;destination.open_panel()
		check(host.active==owner and not destination.panel.visible,"Destination opened before receipt")
		check(commit_ticket>0 and committing.ticket==commit_ticket,"Dismissal did not retain one commit")
		deadline=Time.get_ticks_msec()+5000
		while committing.phase==committing.Phase.Applying and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		if not check(committing.phase==committing.Phase.Closed,"Typed appointment commit did not confirm"):quit(1);return
		check(host.active==destination and destination.panel.visible,"Applied appointment did not finish handoff")
		owner.queue_free();destination.queue_free();host.queue_free();interaction.queue_free();await process_frame
		var effect=FileAccess.open(directory+"/nobles-commit-wire.json",FileAccess.WRITE)
		effect.store_string(JSON.stringify({"unit_id":chosen,"entity_id":target.entity_id,"assignment_id":target.assignment_id,"accounting_values":accounting_values,"accounting_restored":original_setting}));effect.close()
	model.dispose();actions.queue_free();await process_frame
	if OS.get_environment("DF3D_NOBLES_SYMBOL_PANEL")=="1":await check_symbol_panel()
	elif OS.get_environment("DF3D_NOBLES_SYMBOL_WIRE")=="1":await check_symbols(revision)
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"controller_ready":true,"closed_read_retired":true,"success":not failed,"rows":rows.size(),"pages":pages,"stale_rejected":true,"empty_end_page":true}));result.close()
	quit(1 if failed else 0)
