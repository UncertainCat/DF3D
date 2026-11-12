extends "res://tests/item_carrier_wire_live.gd"
func page(tab: int,offset: int,revision: int) -> Dictionary:
	return await request("justice",{"action":C.ManagementAction.JusticeRead,"tab":tab,"offset":offset,"limit":4,"expected_list_revision":revision})
func details(tab: int,id: int,offset: int,list_revision: int,case_revision: int) -> Dictionary:
	return await request("justice",{"action":C.ManagementAction.JusticeCaseRead,"tab":tab,"crime_id":id,"offset":offset,"limit":8,"expected_list_revision":list_revision,"expected_case_revision":case_revision})
func settle_controller(controller) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while controller.phase in [controller.Phase.Reading,controller.Phase.DetailReading] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
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
				check(d.get("crime_id")==id and d.get("caption")==rows[i].caption and d.get("status")==facts.summary.status,"Justice summary differs")
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
	for tab in 3:
		if tab>0:controller.select_tab(tab)
		await settle_controller(controller)
		if not check(controller.phase==controller.Phase.Ready,"Justice controller read did not settle"):quit(1);return
		check(controller.rows.size()==reference.lists[tab].size(),"Justice controller list differs")
		if not controller.rows.is_empty():
			var id: int=controller.rows[0].crime_id
			check(controller.selected_id==id and controller.detail.get("witnesses")==reference.details[str(id)].witnesses,"Justice controller initial detail differs")
	controller.open();controller.close()
	await create_timer(0.1).timeout;world.poll()
	check(controller.phase==controller.Phase.Closed and controller.rows.is_empty() and controller.detail.is_empty(),"Closed Justice controller revived")
	controller.dispose();actions.queue_free();await process_frame
	var result=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"counts":counts,"witnesses":report_count,"stale_tabs":3,"controller_tabs":3,"closed_read_retired":true}));result.close()
	quit(1 if failed else 0)
