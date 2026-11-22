extends "res://tests/furniture_map_scene_live.gd"
func expected_filename() -> String:return "chain-scene-expected.json"
func result_filename() -> String:return "chain-scene-result.json"
func chain_ready() -> bool:
	if not await chest_ready():return false
	if not await settle(owner.cage_occupants):return false
	return await chest_ready()
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	if not await open_furniture(expected) or not await chain_ready():return
	check(owner.cage_occupants.rows.is_empty(),"Chain initial occupants differ")
	await panel_capture("chain-initial","remaining-building-27")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cage_rect().get_center())
	if not check(owner.cage_mode,"Chain picker did not open") or not await settle(owner.cage):return
	await process_frame;await process_frame
	var index: int=owner.cage.rows.find_custom(func(row):return row.entity==1 and row.id==int(expected.unit_id))
	if not check(index>=0,"Chain picker lacks native candidate"):return
	await pointer(owner.cage_view.choices[index].get_global_rect().get_center())
	var deadline:=Time.get_ticks_msec()+10000
	while owner.cage_mode and Time.get_ticks_msec()<deadline:await drain()
	if not check(not owner.cage_mode,"Successful chain selection did not close picker") or not await chain_ready():return
	check(owner.cage_occupants.rows.size()==1 and owner.cage_occupants.rows[0].id==int(expected.unit_id),"Chain selection did not refresh parent")
	await panel_capture("chain-selected","chain-assignment-selected")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.occupant_check(0).get_center())
	if not await chain_ready():return
	check(owner.cage_occupants.rows.is_empty(),"Chain parent toggle did not remove assignment")
	await panel_capture("chain-removed","chain-assignment-removed")
	if not await rename_to(expected.custom_name+"x"):return
	await panel_capture("chain-renamed","remaining-building-27-renamed")
	if not await rename_to(expected.custom_name):return
	await pointer(Vector2(832,82));if not await chest_ready():return
	check(owner.state.snapshot.removing and owner.cage_occupants.building_id==-1,"Removal retained chain assignment authority")
	await panel_capture("chain-removing","remaining-building-27-removing")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await chain_ready():return
	await panel_capture("chain-cancelled","remaining-building-27-cancelled")
	key(KEY_ESCAPE);await drain()
	check(scene._ui.host.active==null and owner.cage_occupants.building_id==-1 and not owner.cage_mode,"Chain close retained authority")
	scene._ui.open_building_holder(27,int(expected.id))
	if not await chain_ready():return
	check(owner.state.building_id==int(expected.id),"Chain holder opened wrong target")
	key(KEY_ESCAPE);await drain()
	exercised=true
