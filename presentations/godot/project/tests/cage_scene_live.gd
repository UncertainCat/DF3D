extends "res://tests/furniture_map_scene_live.gd"
func expected_filename() -> String:return "cage-scene-expected.json"
func result_filename() -> String:return "cage-scene-result.json"
func cage_ready() -> bool:
	if not await chest_ready():return false
	if not await settle(owner.cage_occupants):return false
	# Applied occupant edits start a fresh contents read.
	return await chest_ready()
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	if not await open_furniture(expected) or not await cage_ready():return
	check(owner.cage_occupants.rows.size()==1 and owner.cage_occupants.rows[0].contained,"Cage map entry lost occupant facts")
	var facts:=FileAccess.open(directory+"/cage-scene-contents.json",FileAccess.WRITE);facts.store_string(JSON.stringify(owner.contents.snapshot));facts.close()
	await panel_capture("cage-initial","remaining-building-28")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cage_rect().get_center())
	if not check(owner.cage_mode,"Cage picker did not open") or not await settle(owner.cage):return
	await process_frame;await process_frame
	var index: int=owner.cage.rows.find_custom(func(row):return row.entity==1 and row.id==6960)
	if not check(index>=0,"Cage picker lacks native drake"):return
	await pointer(owner.cage_view.choices[index].get_global_rect().get_center())
	if not await settle(owner.cage) or not await cage_ready():return
	check(owner.cage_occupants.rows.size()==2 and owner.cage_occupants.rows[1].id==6960,"Picker did not refresh parent")
	key(KEY_ESCAPE);await drain()
	check(not owner.cage_mode and owner.panel.visible and owner.cage_occupants.building_id==int(expected.id),"Escape did not return to cage parent")
	await panel_capture("cage-assigned","cage-body-assigned-unit")
	var before: int=owner.cage_occupants.revision
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.occupant_check(0).get_center())
	await drain()
	check(owner.cage_occupants.revision==before,"Native blank item row gained an action")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.occupant_check(1).get_center())
	if not await cage_ready():return
	check(owner.cage_occupants.rows.size()==1,"Parent checkbox did not remove assigned unit")
	await panel_capture("cage-removed","cage-body-parent-removed")
	key(KEY_ESCAPE);await drain()
	check(scene._ui.host.active==null and owner.cage_occupants.building_id==-1 and not owner.cage_mode,"Closing cage retained input or occupant authority")
	scene._ui.open_building_holder(28,int(expected.id))
	if not await cage_ready():return
	check(owner.cage_occupants.rows.size()==1,"Holder return used stale parent rows")
	key(KEY_ESCAPE);await drain()
	exercised=true
