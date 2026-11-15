extends "res://tests/pending_selection_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.pending_component_selection
	var ui=scene._ui
	owner=ui.controller("pending_building")
	var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
	ui.focus_tile(point)
	var deadline:=Time.get_ticks_msec()+10000
	while world.inspect_entity(3,int(sample.building_id)).is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	ui.open_tile_selection(point)
	var selection=ui.tile_selection
	if not await selection_ready(selection.navigation.state):return
	if not await pending_ready():return
	check(ui.host.active==owner and owner.state.building_id==int(sample.building_id),"Component selection opened wrong building")
	check(selection.tabs.alternatives.size()==sample.before.tabs.size(),"Initial native tab count differs")
	await panel_capture("selection-component-before","workshop-pending-selection-component-before")
	await pointer(owner.panel.contents.get_global_transform_with_canvas()*owner.panel.contents.control_rect(0,1).get_center())
	if not await settle(owner.item_owner.state):return
	check(ui.host.active==owner.item_owner and owner.item_owner.state.item_id==int(sample.item_id),"Component inspection opened wrong item")
	check(owner.state.building_id==-1 and owner.contents.building_id==-1,"Inspection retained unfinished building authority")
	check(sample.item.tabs.is_empty() and selection.navigation.state.snapshot.is_empty() and not selection.tabs.visible,"Native component inspection tab retirement differs")
	await panel_capture("selection-component-item","workshop-pending-selection-component-item")
	await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*owner.item_owner.panel.holder_rect().get_center())
	if not await pending_ready():return
	check(ui.host.active==owner and owner.state.building_id==int(sample.building_id) and not owner.item_owner.panel.visible,"Holder View failed to restore unfinished workshop")
	check(sample.returned.tabs.is_empty() and not selection.tabs.visible,"Returned holder retained selection tabs")
	await panel_capture("selection-component-return","workshop-pending-selection-component-return")
	await key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and owner.contents.building_id==-1,"Closing returned holder retained authority")
	exercised=true
