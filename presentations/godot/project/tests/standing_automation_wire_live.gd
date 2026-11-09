extends "res://tests/item_carrier_wire_live.gd"
func pointer(view,point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=view.get_global_transform_with_canvas()*point;event.global_position=event.position
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func ready_state(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while state.phase in [state.Phase.Reading,state.Phase.Applying] and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
	return check(state.phase==state.Phase.Ready,"Standing automation failed to obtain authority")
func run() -> void:
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/standing-automation-native.json"))
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	OS.set_environment("DF3D_FIXTURE","")
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);world=main.world
	var deadline:=Time.get_ticks_msec()+90000
	while not main._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if not check(main._loader.entered,"Automation main scene failed to enter fortress"):quit(1);return
	var owner=main._ui.controller("standing_orders");owner.open_panel()
	if not await ready_state(owner.state):quit(1);return
	var state=owner.state;var view=owner.panel
	check(view.visible_ids().size()==11,"Conditional automation controls missing")
	for row in reference.enabled.settings:
		check(state.settings[int(row.id)].value==int(row.value) and state.settings[int(row.id)].editable==row.available,"Conditional automation snapshot differs")
	var completed:=0
	for cycle in reference.cycles:
		for step in cycle.states:
			var id:=int(cycle.id);var before:=int(state.settings[id].value)
			await pointer(view,view.setting_rect(id).get_center())
			if not await ready_state(state):quit(1);return
			check(state.settings[id].value==int(step.values[cycle.key]),"Conditional automation pointer effect differs")
			var ticket: int=main._ui.actions.submit("standing_orders",{"action":C.ManagementAction.StandingOrdersSet,"category":0,"setting_id":id,"expected_value":before,"value":int(step.values[cycle.key])},Callable())
			deadline=Time.get_ticks_msec()+5000;var stale: Dictionary={}
			while Time.get_ticks_msec()<deadline:
				stale=main._ui.actions.result(ticket)
				if not stale.is_empty():break
				await create_timer(0.01).timeout
			check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("standing_orders",{}).get("outcome")==C.StandingOrdersOutcome.Stale,"Stale automation receipt accepted")
			completed+=1
			var f:=FileAccess.open(directory+"/automation-wire-step",FileAccess.WRITE);f.store_string(str(completed));f.close()
			deadline=Time.get_ticks_msec()+3000
			while Time.get_ticks_msec()<deadline:
				if FileAccess.file_exists(directory+"/automation-wire-ack") and FileAccess.get_file_as_string(directory+"/automation-wire-ack").strip_edges()==str(completed):break
				await create_timer(0.01).timeout
			check(FileAccess.get_file_as_string(directory+"/automation-wire-ack").strip_edges()==str(completed),"Automation native readback missing")
			if failed:quit(1);return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/standing-automation-view.png")
	owner.handle_back();check(main._ui.host.active!=owner and not view.visible,"Automation Back retained input ownership")
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"steps":completed,"main":true}));output.close()
	quit(1 if failed else 0)
