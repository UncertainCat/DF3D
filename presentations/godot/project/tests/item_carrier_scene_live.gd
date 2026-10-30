extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "carrier-expected.json"
func result_filename() -> String:return "carrier-scene-result.json"
func exercise(expected: Dictionary) -> void:
	var farm=scene._ui.controller("farm")
	var inspector=farm.item_owner
	var target: int=int(expected.snapshot.carrier.id)
	inspector.open_target(int(expected.snapshot.id))
	if not await settle(inspector.state):return
	check(inspector.state.snapshot.carrier.id==target,"Container link changed before navigation")
	await pointer(inspector.panel.get_global_transform_with_canvas()*inspector.panel.holder_rect().get_center())
	if not await settle(inspector.state):return
	check(scene._ui.host.active==inspector and inspector.state.item_id==target and inspector.state.snapshot.item_type==30,"Carrier View did not open Box item")
	var holder: Dictionary=inspector.state.snapshot.get("holder",{})
	if not check(holder.get("type",-1)==10,"Carrier fixture Box has no chest holder"):return
	await pointer(inspector.panel.get_global_transform_with_canvas()*inspector.panel.holder_rect().get_center())
	owner=scene._ui.controller("chest")
	if not await chest_ready():return
	check(owner.state.building_id==holder.id and not inspector.panel.visible,"Box holder did not transfer input to chest")
	var index: int=owner.contents.snapshot.rows.find_custom(func(row):return row.id==target)
	if not check(index>=0,"Chest contents lost installed Box"):return
	await pointer(owner.panel.contents.get_global_transform_with_canvas()*owner.panel.contents.control_rect(index,1).get_center())
	if not await settle(owner.item_owner.state):return
	check(scene._ui.host.active==owner.item_owner and owner.item_owner.state.item_id==target,"Chest contents did not return to Box item")
	await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*Vector2(100,200),MOUSE_BUTTON_RIGHT)
	check(scene._ui.host.active==null and not owner.item_owner.panel.visible,"Carrier navigation left input owner active")
	exercised=true
