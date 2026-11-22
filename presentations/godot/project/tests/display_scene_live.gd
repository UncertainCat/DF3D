extends "res://tests/furniture_map_scene_live.gd"
func expected_filename() -> String:return "display-wire-expected.json"
func result_filename() -> String:return "display-wire-result.json"
func display_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await process_frame
		if owner.display.phase!=owner.display.Phase.Ready or owner.display.ticket!=0:continue
		var ready:=true
		if owner.display_mode:
			if owner.display_view.requested:continue
			for row in owner.display_view.page:
				if row.has("id") and not owner.display.items.has(row.id):ready=false
		else:
			if owner.panel._details_pending:continue
			for row in owner.display.body:
				if row.resolved and (not owner.display.items.has(row.id) or owner.panel.display_icons.get(row.id,{}).get("texture")==null):ready=false
		if ready:return true
	return check(false,"Display visible facts/art did not settle")
func exercise(expected: Dictionary) -> void:
	Engine.max_fps=30;owner=scene._ui.controller("furniture")
	if not await open_furniture(expected) or not await display_ready():return
	await panel_capture("display-initial","display-scene-initial")
	if not await rename_to(expected.custom_name+"x"):return
	await panel_capture("display-renamed","display-scene-renamed")
	if not await rename_to(expected.custom_name):return
	await panel_capture("display-restored","display-scene-restored")
	await pointer(Vector2(832,82));if not await chest_ready():return
	check(owner.state.snapshot.removing,"Display removal was not queued")
	await panel_capture("display-removing","display-scene-removing")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await chest_ready() or not await display_ready():return
	await panel_capture("display-cancelled","display-scene-cancelled")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.assign_rect().get_center())
	if not await display_ready():return
	check(owner.display_mode and not owner.panel.visible and not scene._ui.host.allows_minimap_input(),"Display picker did not own input")
	await pointer(owner.display_view.get_global_transform_with_canvas()*Vector2(128,78))
	if not await display_ready():return
	check(owner.display.category==37,"Display category click failed")
	var selected_ids: Array=expected.get("item_ids",[expected.item_id]).map(func(value):return int(value))
	for id in selected_ids:
		var index: int=owner.display_view.page.find_custom(func(row):return row.get("id",-1)==id)
		if not check(index>=0,"Display selected item is not visible"):return
		await pointer(owner.display_view.get_global_transform_with_canvas()*(owner.display_view.item_canvas.position+owner.display_view.checkbox_rect(index).get_center()))
		check(owner.display.selected.has(id),"Display checkbox click failed")
	key(KEY_ESCAPE);await drain();await process_frame
	check(scene._ui.host.active==null and not owner.display_view.visible and not scene._interaction.construction_active,"Display close retained modal selection")
	if not await open_furniture(expected) or not await display_ready():return
	check(owner.display.body.map(func(row):return row.id)==expected.get("assigned_ids",[expected.item_id]).map(func(value):return int(value)),"Display assignment membership/order differs from native")
	await panel_capture("display-assigned","display-selected-parent")
	for remaining in range(selected_ids.size()-1,-1,-1):
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.display_check(0).get_center())
		if not await display_ready():return
		check(owner.display.body.size()==remaining,"Display parent removal affected the wrong number of items")
	await panel_capture("display-removed","display-removed-parent")
	key(KEY_ESCAPE);await drain()
	scene._ui.open_building_holder(53,int(expected.id))
	if not await chest_ready() or not await display_ready():return
	check(owner.state.building_id==int(expected.id),"Display holder route failed")
	key(KEY_ESCAPE);await drain();exercised=true
