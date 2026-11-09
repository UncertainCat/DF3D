extends "res://tests/item_carrier_wire_live.gd"
const State=preload("res://scripts/stone_use_state.gd")
var actions
var main_scene
var modified_sort_steps:=0
func pointer(view,point: Vector2,shift: bool=false,control: bool=false) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.shift_pressed=shift;event.ctrl_pressed=control
	event.position=view.get_global_transform_with_canvas()*point;event.global_position=event.position
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func request(domain: String,data: Dictionary) -> Dictionary:
	if actions==null:return await super.request(domain,data)
	var ticket: int=actions.submit(domain,data,Callable())
	if not check(ticket>0,"Stone use request not queued"):return {}
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		var result: Dictionary=actions.result(ticket)
		if not result.is_empty():return result
		await create_timer(0.01).timeout
	check(false,"Stone use request outcome unknown");return {}
func ready_state(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while state.phase in [State.Phase.Reading,State.Phase.Applying] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	return check(state.phase==State.Phase.Ready,"Stone use controller failed to obtain fresh authority")
func run() -> void:
	Engine.max_fps=30
	root.size=Vector2i(1200,800)
	var rendered: bool=OS.get_environment("DF3D_STONE_USE_RENDER")=="1"
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/stone-use-native.json"))
	if OS.get_environment("DF3D_STONE_USE_MAIN")=="1":
		var preferences=preload("res://scripts/presentation_settings.gd")
		preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
		OS.set_environment("DF3D_FIXTURE","")
		main_scene=load("res://scenes/main.tscn").instantiate();root.add_child(main_scene);world=main_scene.world
		var startup:=Time.get_ticks_msec()+90000
		while not main_scene._loader.entered and Time.get_ticks_msec()<startup:await create_timer(0.05).timeout
		if not check(main_scene._loader.entered,"Stone use main scene failed to enter fortress"):quit(1);return
		actions=main_scene._ui.actions
	else:
		world=Df3dWorld.new();root.add_child(world)
		if not check(world.attach(),"Stone use bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	if actions==null:
		actions=preload("res://scripts/semantic_action_service.gd").new();root.add_child(actions);actions.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var state:=State.new();var owner
	if main_scene!=null:
		owner=main_scene._ui.controller("standing_orders");owner.open_panel()
		await pointer(owner.panel,owner.panel.stone_use_rect().get_center());state=owner.stone_state
		check(owner.stone_active and main_scene._ui.host.active==owner,"Stone use main owner handoff failed")
	else:state.configure(actions);state.open()
	if not await ready_state(state):quit(1);return
	var view
	if rendered:
		if owner!=null:view=owner.stone_panel
		else:
			if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Stone use installed assets unavailable"):quit(1);return
			view=preload("res://scripts/stone_use_view.gd").new();root.add_child(view)
			view.configure_stone_use(world,state);view.layout(Vector2(1200,800));await process_frame
	var value: Dictionary={"rows":state.rows,"restrictions":state.restrictions}
	check(value.rows.size()==reference.provider.size(),"Stone use row count differs")
	for i in mini(value.rows.size(),reference.provider.size()):
		var expected_row: Dictionary=reference.provider[i].duplicate(true)
		expected_row.category=int(expected_row.category);expected_row.index=int(expected_row.index)
		check(value.rows[i]==expected_row,"Stone use metadata differs at row "+str(i))
	var expected_flags: Array=[]
	for flag in reference.edits.before:expected_flags.append(int(flag))
	check(value.restrictions==expected_flags,"Stone use full restriction receipt differs")
	var completed:=0
	for step in reference.edits.steps:
		if failed:break
		var intent: Dictionary={"action":C.ManagementAction.StoneUseApply,"category":int(step.category),"index":int(step.index),"expected":state.restrictions.duplicate()}
		if rendered:
			await pointer(view,view.category_rect(int(step.category)).get_center())
			check(state.category==int(step.category),"Stone use category pointer failed")
			if step.get("resized",false):
				root.size=Vector2i(1200,800);await process_frame;await process_frame
				if owner==null:view.layout(Vector2(1200,800))
				state.seek(38,view.capacity())
				root.size=Vector2i(1600,900);await process_frame;await process_frame
				if owner==null:view.layout(Vector2(1600,900))
				check(state.first[1]==38 and view.visible_first()==35 and int(state.category_rows()[35].index)==int(step.index),"Resized visible target differs from native")
			await pointer(view,view.restriction_rect(0).get_center())
		else:
			state.select_category(int(step.category));state.toggle(int(step.index))
			check(state.phase==State.Phase.Applying and state.rows.is_empty() and state.restrictions.is_empty(),"Stone use pending edit retained authority")
		if not await ready_state(state):break
		check(state.category==int(step.category),"Stone use edit lost local category")
		var stale:=await request("stone_use",intent)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("stone_use",{}).get("outcome")==C.StoneUseOutcome.Stale,"Stone use stale receipt accepted")
		value={"rows":state.rows,"restrictions":state.restrictions}
		check(value.restrictions[int(step.index)]==int(step.restricted),"Stone use refresh differs")
		completed+=1
		var f:=FileAccess.open(directory+"/stone-use-wire-step",FileAccess.WRITE);f.store_string(str(completed));f.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/stone-use-wire-ack") and FileAccess.get_file_as_string(directory+"/stone-use-wire-ack").strip_edges()==str(completed):break
			await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/stone-use-wire-ack").strip_edges()==str(completed),"Stone use independent effect not acknowledged")
	check(completed==reference.edits.steps.size(),"Stone use edits incomplete")
	if owner!=null:
		root.size=Vector2i(1200,800);await process_frame;await process_frame;state.seek(0,view.capacity())
		await pointer(view,view.kitchen_rect().get_center())
		check(owner.kitchen_active and not owner.stone_active and state.rows.is_empty(),"Main Kitchen handoff retained Stone use authority")
		await pointer(owner.kitchen_panel,owner.kitchen_panel.stone_use_rect().get_center())
		if not await ready_state(state):quit(1);return
		check(state.category==1,"Main Kitchen return lost Stone use category")
		await pointer(view,view.work_details_rect().get_center())
		var details=main_scene._ui.controller("work_details")
		deadline=Time.get_ticks_msec()+5000
		while details.state.phase!=details.state.Phase.Ready and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
		check(main_scene._ui.host.active==details and state.rows.is_empty(),"Main Work Details handoff failed")
		await keyboard(KEY_F,true);check(not details.panel.search.has_focus(),"Filter bypassed initial right-panel gate")
		await keyboard(KEY_RIGHT);await keyboard(KEY_F,true);check(details.panel.search.has_focus(),"Right then Filter did not focus search")
		await keyboard(KEY_LEFT);await keyboard(KEY_A,false,97)
		check(details.state.query.is_empty() and details.panel.search.has_focus(),"Disabled right panel accepted typing or lost native textbox focus")
		await keyboard(KEY_RIGHT);await keyboard(KEY_ENTER);check(not details.panel.search.has_focus(),"Enabled Enter did not release filter")
		if OS.get_environment("DF3D_WORK_DETAILS_MAIN_MODSORT")=="1":
			var native: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_work_details.json")).modified_sort_reference
			for observation: Dictionary in native.observations:
				if not observation.label.begins_with("controlled-"):continue
				var parts: PackedStringArray=observation.label.split("-")
				var column: int=["Cat","Name","Prof","Skills"].find(parts[2])
				var header: int=details.panel.DETAIL_SORTS.find(column)
				await pointer(details.panel,Vector2(details.panel.DETAIL_SORT_X[header]*8+4,details.panel.list_top()-18),int(parts[1])==1,int(parts[1])==2)
				if not await details_ready(details):quit(1);return
				check(main_scene._ui.host.active==details and details.state.ids==PackedInt32Array(observation.ids),"Main modified sort differs: "+observation.label)
				modified_sort_steps+=1
			check(modified_sort_steps==11,"Main modified sort sequence incomplete")
		await pointer(details.panel,Vector2(details.panel.DETAIL_SORT_X[0]*8+16,details.panel.list_top()-18))
		if not await details_ready(details):quit(1);return
		await keyboard(KEY_F,true)
		check(details.panel.search.has_focus(),"Right-panel sort click did not enable Filter")
		var typed:=InputEventKey.new();typed.pressed=true;typed.keycode=KEY_A;typed.unicode=97;Input.parse_input_event(typed);await process_frame
		if not await details_ready(details):quit(1);return
		check(details.state.sort==C.WorkDetailWorkerSort.Name and details.state.query=="a".to_ascii_buffer(),"Work Details pointer sort/search setup failed")
		await pointer(details.panel.scrollbar,Vector2(8,details.panel.scrollbar.size.y-6))
		if not await details_ready(details):quit(1);return
		var roster_first: int=details.state.first
		check(roster_first>0,"Work Details roster did not scroll")
		for destination in ["standing_orders_rect","kitchen_rect","stone_use_rect"]:
			await pointer(details.panel,details.panel.call(destination).get_center())
			check(details.state.rows.is_empty() and details.state.selected.is_empty(),"Labor switch retained Work Details authority")
			var target=owner.stone_panel if owner.stone_active else owner.kitchen_panel if owner.kitchen_active else owner.panel
			await pointer(target,target.work_details_rect().get_center())
			if not await details_ready(details):quit(1);return
			check(main_scene._ui.host.active==details and details.state.sort==C.WorkDetailWorkerSort.Name and details.state.query=="a".to_ascii_buffer() and details.panel.search.value==details.state.query,"Labor return lost Work Details search/sort")
			check(details.state.first==roster_first,"Labor return lost roster scroll")
			await keyboard(KEY_F,true);check(not details.panel.search.has_focus(),"Labor return retained old keyboard focus gate")
		await pointer(details.panel,Vector2(656,details.panel.header_top()+18))
		if not await details_ready(details):quit(1);return
		check(details.state.editing_settings,"Work Details gear did not open settings")
		await pointer(details.panel.scrollbar,Vector2(8,details.panel.scrollbar.size.y-18))
		var settings_first: int=details.state.settings_first
		check(settings_first>0,"Work Details settings did not scroll")
		for destination in ["standing_orders_rect","kitchen_rect","stone_use_rect"]:
			await pointer(details.panel,details.panel.call(destination).get_center())
			check(details.state.settings.is_empty(),"Labor switch retained settings authority")
			var target=owner.stone_panel if owner.stone_active else owner.kitchen_panel if owner.kitchen_active else owner.panel
			await pointer(target,target.work_details_rect().get_center())
			if not await details_ready(details):quit(1);return
			check(details.state.editing_settings and details.state.settings_first==settings_first and not details.state.settings.is_empty(),"Labor return lost settings page/scroll or fresh authority")
		var settings_snapshot:=FileAccess.open(directory+"/work-details-settings-return.json",FileAccess.WRITE)
		settings_snapshot.store_string(JSON.stringify({"settings":details.state.settings,"first":details.state.settings_first}));settings_snapshot.close()
		for frame in 4:
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/work-details-settings-frame-"+str(frame)+".png")
		await create_timer(0.2).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/work-details-settings-return.png")

		await pointer(details.panel,details.panel.done_rect().get_center())
		if not await details_ready(details):quit(1);return
		await process_frame;await process_frame
		var roster:=FileAccess.open(directory+"/work-details-labor-rows.json",FileAccess.WRITE)
		roster.store_string(JSON.stringify(details.state.rows));roster.close()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/work-details-labor-return.png")
		await pointer(details.panel,details.panel.stone_use_rect().get_center())
		if not await ready_state(state):quit(1);return
		check(main_scene._ui.host.active==owner and owner.stone_active and state.category==1,"Direct Work Details Stone use return failed")
		owner.handle_back();await process_frame
		check(not view.visible and state.rows.is_empty() and state.restrictions.is_empty() and main_scene._ui.host.active!=owner,"Closing Stone use retained authority or input ownership")
		owner.open_from_labor(false,true)
		if not await ready_state(state):quit(1);return
		check(state.category==0 and state.first==[0,0],"Reopen after close retained old navigation")
		await pointer(view,view.category_rect(1).get_center())
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/stone-use-view.png")
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"steps":completed,"rows":value.rows.size(),"controller":true,"rendered":rendered,"main":main_scene!=null,"modified_sort_steps":modified_sort_steps}));output.close()
	if owner!=null:owner.close_panel()
	else:
		if view!=null:view.queue_free();await process_frame
		state.dispose()
	quit(1 if failed else 0)

func details_ready(owner) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while owner.state.phase in [owner.state.Phase.Reading,owner.state.Phase.Applying] and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
	return check(owner.state.phase==owner.state.Phase.Ready,"Work Details failed to refresh after Labor navigation")

func keyboard(code: int,control: bool=false,unicode_value: int=0) -> void:
	var event:=InputEventKey.new();event.pressed=true;event.keycode=code;event.ctrl_pressed=control;event.unicode=unicode_value
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
