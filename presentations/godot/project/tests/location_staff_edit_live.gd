extends "res://tests/areas_acceptance_live.gd"
# Actual Details state/service/transport; native semantic readback on an owned clone.
# Native-button parity of the primitive has separate recorded fixtures. No GUI claim.
const Model = preload("res://scripts/location_details_state.gd")
const Service = preload("res://scripts/semantic_action_service.gd")
var actions
var model

func settle(expected_phase: int = Model.Phase.Ready) -> bool:
	var deadline := Time.get_ticks_msec()+30000
	while not stopped and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if model.ticket==0: return check(model.phase==expected_phase,"Details edit/entry phase differs: "+str(model.phase))
		await create_timer(0.01).timeout
	incomplete("staff service wait cap; no replay",true)
	return false

func rejected(intent: Dictionary, outcome: int) -> void:
	if stopped: return
	var sequence: int=world.area_request(intent)
	if not check(sequence>0,"refusal request not sent"): return
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();var reply: Dictionary=world.poll_management()
		if int(reply.get("request_seq",0))==sequence and int(reply.get("status",S.Idle)) not in [S.Idle,S.Pending]:
			var area: Dictionary=reply.get("area",{})
			check(reply.status==S.Rejected and area.get("operation")==Contract.AreaOperation.LocationStaffEdit
				and area.get("location_edit_outcome")==outcome and not area.has("location_details")
				and str(reply.get("message",""))=="","staff refusal outcome/presence/copy differs")
			return
		await create_timer(0.01).timeout
	incomplete("staff refusal wait cap; no replay",true)

func exercise() -> void:
	actions=Service.new();actions.configure(world);root.add_child(actions);actions.set_process(false)
	actions.completed.connect(func(ticket,result):print("STAFF_EDIT_RECEIPT ",ticket," ",result))
	# configure reconnects the client; discover its epoch after that reset.
	var reconnect_deadline:=Time.get_ticks_msec()+30000
	while not world.poll_management().get("transport_alive",false) and Time.get_ticks_msec()<reconnect_deadline:
		world.poll();await create_timer(0.02).timeout
	await seed_catalog()
	if stopped: return
	model=Model.new();model.configure(actions)
	var locations:=await native("staff_edit_locations")
	var count:=0
	for location in locations.get("locations",[]):
		step="staff Details entry "+str(int(location.id))
		model.open({"site_id":int(location.site_id),"id":int(location.id)})
		if not await settle(): return
		var seen: Dictionary={}
		var rows: Array=model.snapshot.get("staff",{}).get("rows",[]).duplicate(true)
		for row in rows:
			if int(row.source)!=0 or int(row.unit_id)!=-1 or int(row.histfig_id)!=-1 or seen.has(int(row.role)): continue
			seen[int(row.role)]=true
			step="staff edit location %d role %d" % [int(location.id),int(row.role)]
			var read_intent: Dictionary={"action":Contract.ManagementAction.AreaInspect,"kind":1,
				"operation":Contract.AreaOperation.LocationStaffCandidates,"location_site_id":int(location.site_id),
				"location_id":int(location.id),"occupation_id":int(row.occupation_id)}
			var candidates:=await request(read_intent)
			if stopped: return
			var page: Dictionary=candidates.location_staff_candidates
			var ids: Array=[]
			for candidate in page.rows.slice(0,16): ids.append(int(candidate.unit_id))
			var control:=await native("staff_edit_prepare",{"occupation_id":int(row.occupation_id),"location_id":int(location.id),"candidates":ids})
			if stopped: return
			var edit_intent:=read_intent.duplicate()
			edit_intent.action=Contract.ManagementAction.AreaUpdate;edit_intent.operation=Contract.AreaOperation.LocationStaffEdit
			edit_intent.expected_revision=model.snapshot.revision;edit_intent.expected_list_revision=page.revision;edit_intent.unit_id=int(control.unit_id)
			for variant in 3:
				var invalid:=edit_intent.duplicate()
				if variant==0: invalid.unit_id=2147483647
				elif variant==1: invalid.expected_revision+=1
				else: invalid.expected_list_revision+=1
				await rejected(invalid,Contract.LocationEditOutcome.Rejected if variant==0 else Contract.LocationEditOutcome.Stale)
				if stopped: return
			await native("staff_edit_unchanged")
			if stopped: return
			model.set_staff(int(row.occupation_id),int(control.unit_id),int(page.revision))
			if not await settle(): return
			var returned: Dictionary={}
			for current in model.snapshot.staff.rows:
				if int(current.occupation_id)==int(row.occupation_id): returned=current
			if not check(returned.get("unit_id")==int(control.unit_id) and returned.get("histfig_id")==int(control.histfig_id),"assigned Details holder differs"): return
			await native("staff_edit_check",{"assigned":true})
			await rejected(edit_intent,Contract.LocationEditOutcome.Stale)
			await native("staff_edit_unchanged")
			if stopped: return
			candidates=await request(read_intent)
			if stopped: return
			page=candidates.location_staff_candidates
			edit_intent.expected_revision=model.snapshot.revision;edit_intent.expected_list_revision=page.revision;edit_intent.unit_id=-1
			model.set_staff(int(row.occupation_id),-1,int(page.revision))
			if not await settle(): return
			for current in model.snapshot.staff.rows:
				if int(current.occupation_id)==int(row.occupation_id):
					if not check(int(current.unit_id)==-1 and int(current.histfig_id)==-1,"removed Details holder differs"): return
			await native("staff_edit_check",{"assigned":false})
			await rejected(edit_intent,Contract.LocationEditOutcome.Stale)
			await native("staff_edit_unchanged")
			if stopped: return
			count+=1
	if not check(count==10,"ordinary native staff matrix incomplete: "+str(count)): return
	await unknown_after_assignment()
	if not stopped and FileAccess.file_exists(directory+"/staff-scene.txt"):await viewport_edits(locations.get("locations",[]))
	model.close();actions.queue_free()
	if stopped: return
	print("LOCATION_STAFF_EDIT_LIVE_PASS cases=",count)

func unknown_after_assignment() -> void:
	step="staff edit partial publication"
	var control:=await native("staff_edit_exhaustion")
	if stopped: return
	model.refresh()
	if not await settle(): return
	var read_intent: Dictionary={"action":Contract.ManagementAction.AreaInspect,"kind":1,
		"operation":Contract.AreaOperation.LocationStaffCandidates,"location_site_id":int(control.site_id),
		"location_id":int(control.location_id),"occupation_id":int(control.occupation_id)}
	var candidates:=await request(read_intent)
	if stopped: return
	var page: Dictionary=candidates.location_staff_candidates
	var original:=read_intent.duplicate()
	original.action=Contract.ManagementAction.AreaUpdate;original.operation=Contract.AreaOperation.LocationStaffEdit
	original.unit_id=int(control.unit_id);original.expected_revision=model.snapshot.revision;original.expected_list_revision=page.revision
	model.set_staff(int(control.occupation_id),int(control.unit_id),int(page.revision))
	var ticket: int=model.ticket
	if not check(ticket>0,"partial-effect control not queued"): return
	if not await settle(Model.Phase.Unknown): return
	var receipt: Dictionary=actions.result(ticket)
	if not check(receipt.get("outcome")=="unknown" and receipt.get("area",{}).get("location_edit_outcome")==Contract.LocationEditOutcome.Unknown
		and not receipt.get("area",{}).has("location_details") and model.snapshot.is_empty(),"partial effect claimed completion or clean refusal"): return
	write_json("staff-edit-unknown-receipt.json",receipt)
	await native("staff_edit_unknown_check")
	if stopped: return
	model.set_staff(int(control.occupation_id),int(control.unit_id),int(page.revision));model.refresh()
	for i in 10:
		world.poll();actions.poll();await create_timer(0.02).timeout
	if not check(model.ticket==0 and model.phase==Model.Phase.Unknown,"unknown controller permitted replay"): return
	await rejected(original,Contract.LocationEditOutcome.Stale)
	await native("staff_edit_unchanged")
	await native("staff_edit_restore_exhaustion")
	if stopped: return
	# Explicit new observation after removing the fixture fault; never replay the
	# uncertain assignment. Remove its observed holder with freshly issued receipts.
	model.open({"site_id":int(control.site_id),"id":int(control.location_id)})
	if not await settle(): return
	candidates=await request(read_intent)
	if stopped: return
	model.set_staff(int(control.occupation_id),-1,int(candidates.location_staff_candidates.revision))
	if not await settle(): return
	await native("staff_edit_check",{"assigned":false,"evidence_suffix":"-unknown-recovery"})
	if not stopped: print("LOCATION_STAFF_EDIT_UNKNOWN_PASS")

func pointer_click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true;root.push_input(event,true);event.pressed=false;root.push_input(event,true)
	await process_frame

func keyboard_press(code: int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true
	root.push_input(event,true);event.pressed=false;root.push_input(event,true)
	await process_frame

func candidates_ready(view) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while not stopped and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if view.staff_candidates_view.visible and view.staff_candidates_view.actions_enabled:return true
		await create_timer(0.02).timeout
	return check(false,"viewport selector did not become selectable")

func staff_point(view, occupation_id: int, remove: bool) -> Vector2:
	var staff=view.staff_view
	var index: int=-1
	for i in staff.rows.size():
		if int(staff.rows[i].get("occupation_id",-1))==occupation_id:index=i;break
	if not check(index>=0,"viewport target row absent"):return Vector2.ZERO
	# Establish an already-scrolled viewport; scrollbar physical input has its
	# own native replay lane. The actions below are actual viewport clicks.
	staff.display(model.snapshot,mini(index,int(staff.geometry.max_scroll)))
	var x: float=(66 if int(staff.geometry.max_scroll)>0 else 68)*8+16 if remove else 208
	return staff.global_position+Vector2(x,(int(staff.geometry.first_y)-6+(index-staff.first)*3)*12+18)

func viewport_edits(locations: Array) -> void:
	if not check(DisplayServer.get_name()!="headless","StaffScene requires real renderer"):return
	root.size=Vector2i(1200,800)
	if not check(world.load_assets(FileAccess.get_file_as_string(directory+"/df-path.txt")),"native installed artwork unavailable"):return
	var view=preload("res://scripts/location_details_view.gd").new()
	root.add_child(view);view.configure(world,model);view.layout(Vector2(1200,800))
	var count:=0
	for location in locations:
		model.open({"site_id":int(location.site_id),"id":int(location.id)})
		if not await settle():return
		var seen: Dictionary={}
		for row in model.snapshot.staff.rows.duplicate(true):
			if int(row.source)!=0 or int(row.unit_id)!=-1 or int(row.histfig_id)!=-1 or seen.has(int(row.role)):continue
			seen[int(row.role)]=true
			step="viewport staff %d role %d" % [int(location.id),int(row.role)]
			await pointer_click(staff_point(view,int(row.occupation_id),false))
			if not await candidates_ready(view):return
			var selector=view.staff_candidates_view
			var ids: Array=[]
			for candidate in selector.rows.slice(0,16):ids.append(int(candidate.unit_id))
			var control:=await native("staff_edit_prepare",{"occupation_id":int(row.occupation_id),"location_id":int(location.id),"candidates":ids})
			if stopped:return
			var selected: int=ids.find(int(control.unit_id))
			if not check(selected>=0,"native chosen candidate outside visible control"):return
			var revision: int=model.snapshot.revision
			if count%2==0:await pointer_click(selector.global_position+Vector2(44,678))
			var cancel:=InputEventMouseButton.new();cancel.button_index=MOUSE_BUTTON_RIGHT;cancel.pressed=true
			cancel.position=Vector2(20,20);cancel.global_position=cancel.position
			root.push_input(cancel,true);cancel.pressed=false;root.push_input(cancel,true)
			await process_frame
			if not check(view.staff_workflow.mode==view.staff_workflow.Mode.Closed and not selector.visible and selector.all_rows.is_empty()
				and model.phase==Model.Phase.Ready and model.snapshot.revision==revision,"right-click cancellation changed Details or retained selector"):return
			await native("staff_edit_unchanged")
			await pointer_click(staff_point(view,int(row.occupation_id),false))
			if not await candidates_ready(view):return
			selected=-1
			for i in selector.rows.size():
				if int(selector.rows[i].unit_id)==int(control.unit_id):selected=i;break
			if not check(selected>=0,"candidate missing after cancellation/reopen"):return
			for i in selected:await keyboard_press(KEY_DOWN)
			if count%2==0:
				await pointer_click(selector.global_position+Vector2(44,678))
				await keyboard_press(KEY_ENTER)
				if not check(selector.visible and not selector.filter_focused and view.staff_workflow.mode==view.staff_workflow.Mode.Choosing,"focused Enter assigned or failed to defocus"):return
				await native("staff_edit_unchanged")
			for i in 2:await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/viewport-selector-%d-%d.png"%[int(location.id),int(row.role)])
			await keyboard_press(KEY_ENTER)
			if not await settle():return
			if not check(view.staff_workflow.mode==view.staff_workflow.Mode.Closed and not selector.visible and selector.all_rows.is_empty()
				and view.staff_view.first==0,"assignment did not close/reset native local views"):return
			await native("staff_edit_check",{"assigned":true,"evidence_suffix":"-viewport"})
			if stopped:return
			await pointer_click(staff_point(view,int(row.occupation_id),true))
			var deadline:=Time.get_ticks_msec()+30000
			while view.staff_workflow.mode!=view.staff_workflow.Mode.Closed and not stopped and Time.get_ticks_msec()<deadline:
				world.poll();actions.poll();await create_timer(0.02).timeout
			if not check(model.phase==Model.Phase.Ready and view.staff_workflow.mode==view.staff_workflow.Mode.Closed and view.staff_view.first==0,"viewport removal did not settle/reset"):return
			await native("staff_edit_check",{"assigned":false,"evidence_suffix":"-viewport"})
			if stopped:return
			for i in 2:await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/viewport-removed-%d-%d.png"%[int(location.id),int(row.role)])
			count+=1
	view.queue_free();await process_frame
	if check(count==10,"viewport role matrix incomplete"):print("LOCATION_STAFF_EDIT_VIEWPORT_PASS cases=",count)
	if not stopped:print("LOCATION_STAFF_EDIT_KEYBOARD_PASS cases=",count)
