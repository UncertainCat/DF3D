extends "res://tests/item_carrier_wire_live.gd"
const State=preload("res://scripts/stone_use_state.gd")
var actions
var main_scene
func pointer(view,point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
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
	check(completed==4,"Stone use edits incomplete")
	if owner!=null:
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
		await pointer(details.panel,details.panel.stone_use_rect().get_center())
		if not await ready_state(state):quit(1);return
		check(main_scene._ui.host.active==owner and owner.stone_active and state.category==1,"Direct Work Details Stone use return failed")
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/stone-use-view.png")
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"steps":completed,"rows":value.rows.size(),"controller":true,"rendered":rendered,"main":main_scene!=null}));output.close()
	if owner!=null:owner.close_panel()
	else:
		if view!=null:view.queue_free();await process_frame
		state.dispose()
	quit(1 if failed else 0)
