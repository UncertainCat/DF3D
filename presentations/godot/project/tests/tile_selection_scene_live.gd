extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "workshop-native.json"
func result_filename() -> String:return "workshop-wire-result.json"
func selection_ready(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Selection did not reach Ready: "+str(model.phase))
func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.tile_selection_reference.cases[2]
	var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
	var ui=scene._ui
	ui.focus_tile(point)
	var visible_deadline:=Time.get_ticks_msec()+10000
	var building: Dictionary={}
	while building.is_empty() and Time.get_ticks_msec()<visible_deadline:
		world.poll();building=world.inspect_entity(3,int(sample.native.active_id))
		await create_timer(0.01).timeout
	print("Selection building metadata: ",building)
	if not check(not building.is_empty(),"Selected tile has not streamed its visible building"):return
	ui.open_tile_selection(point)
	var selection=ui.tile_selection
	var model=selection.navigation.state
	if not await selection_ready(model):return
	owner=ui.controller("inspector")
	check(ui.host.active==owner and owner.selected.get("id")==int(sample.native.active_id),"Default floodgate destination differs")
	await pointer(Vector2(920,104))
	if not await selection_ready(model):return
	check(ui.host.active==selection and model.snapshot.kind==7,"Item-group tab lost selection ownership")
	await panel_capture("selection-group","workshop-selection-item-group")
	await pointer(Vector2(600,118))
	if not await selection_ready(model):return
	var item=ui.controller("farm").item_owner
	if not await settle(item.state):return
	check(ui.host.active==item and item.state.item_id==int(sample.native.items[0]),"Group row opened wrong item")
	check(selection.tabs.visible and selection.tabs.selected==-1,"Member did not retain unselected side tabs")
	await pointer(Vector2(920,104))
	if not await selection_ready(model):return
	check(ui.host.active==selection and not item.panel.visible,"Item-to-group handoff retained detail panel")
	await pointer(Vector2(920,68))
	if not await selection_ready(model):return
	check(ui.host.active==owner and owner.selected.get("id")==int(sample.native.active_id),"Building tab did not restore floodgate")
	key(KEY_ESCAPE);await process_frame
	check(ui.host.active==null and model.snapshot.is_empty() and not selection.tabs.visible,"Escape retained selection context")
	ui.open_tile_selection(point);actions.poll(0.01);ui.host.reset_local_views()
	await drain()
	check(ui.host.active==null and model.snapshot.is_empty(),"Late selection reopened reset main scene")
	exercised=true
