extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "nobles-native.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func commit_handoff(expected: Dictionary) -> bool:
	var target: Dictionary=expected.pickers[0].selected
	var index:=-1;var setting:=-1
	for i in owner.state.rows.size():
		var row: Dictionary=owner.state.rows[i]
		if row.entity_id==int(target.entity_id) and row.assignment_id==int(target.assignment_id):index=i
		if row.get("help",{}).has("accounting"):setting=row.help.accounting.setting
	if not check(index>=0 and setting>=0,"Main appointment target missing"):return false
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(200,owner.panel.list_top()+index*36+18))
	await drain()
	if not check(owner.state.phase==owner.state.Phase.CandidatesReady,"Main appointment picker unavailable"):return false
	var chosen:=-1;index=-1
	for i in owner.state.candidates.size():
		if owner.state.candidates[i].unit_id>=0:chosen=owner.state.candidates[i].unit_id;index=i;break
	if not check(index>=0 and index<owner.panel.capacity(),"Main appointment candidate not visible"):return false
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,owner.panel.list_top()+index*36+18))
	if not await settle(owner.state):return false
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(352,24))
	var ticket: int=owner.state.ticket
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(352,24))
	check(ticket>0 and owner.state.ticket==ticket and owner.state.phase==owner.state.Phase.Applying and scene._ui.host.active==owner,"Main handoff did not retain one pending commit")
	await drain()
	var destination=scene._ui.controller("workshop")
	if not check(scene._ui.host.active==destination and destination.global_orders_mode and owner.state.phase==owner.state.Phase.Closed,"Confirmed main appointment did not open global Work orders"):return false
	var file=FileAccess.open(directory+"/nobles-commit-wire.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit_id":chosen,"entity_id":int(target.entity_id),"assignment_id":int(target.assignment_id),"accounting_values":[],"accounting_restored":setting,"main_scene_handoff":true}));file.close()
	owner.open_panel()
	return await settle(owner.state)
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("nobles");owner.open_panel()
	if not await settle(owner.state):return
	check(owner.state.rows.size()==expected.rows.size(),"Composed Nobles rows differ")
	check(scene._interaction.construction_active,"Nobles does not own world input")
	for dimensions in [Vector2i(912,552),Vector2i(1600,900)]:
		root.size=dimensions;await process_frame;await process_frame
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(136,24));await drain()
		var tasks=scene._ui.controller("tasks")
		check(scene._ui.host.active==tasks and not owner.panel.visible,"Nobles header failed to reach Tasks")
		await pointer(tasks.panel.get_global_transform_with_canvas()*Vector2(24 if dimensions.x<1240 else 456,24))
		if not await settle(owner.state):return
		check(scene._ui.host.active==owner and not tasks.panel.visible,"Tasks failed to return to Nobles")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-main-"+str(dimensions.x)+".png")
	scene._fortress_hud.toggle_game_menu();await process_frame
	check(scene._ui.host.overlay_blocked,"Nobles overlay gate missing")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(136,24))
	check(scene._ui.host.active==owner,"Overlay allowed Nobles header navigation")
	scene._fortress_hud.close_menus();await process_frame
	if OS.get_environment("DF3D_NOBLES_SCENE_COMMIT")=="1" and not await commit_handoff(expected):return
	key(KEY_F10);await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible and not scene._interaction.construction_active,"Nobles reset did not release map input")
	await drain();exercised=true
