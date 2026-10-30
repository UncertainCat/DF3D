extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "chest-melt-expected.json"
func result_filename() -> String:return "chest-melt-scene-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("chest");owner.open_target(int(expected.building_id))
	if not await chest_ready():return
	var index: int=owner.contents.snapshot.rows.find_custom(func(row):return row.id==int(expected.item_id))
	if not check(index>=0 and owner.contents.snapshot.rows[index].can_melt,"Eligible Melt fixture missing"):return
	for desired in [true,false]:
		await pointer(owner.panel.contents.get_global_transform_with_canvas()*owner.panel.contents.control_rect(index,4).get_center())
		if not await chest_ready():return
		check(owner.contents.snapshot.rows[index].melt==desired,"Melt viewport effect differs")
		check(owner.state.snapshot.removing and owner.contents.snapshot.removing,"Melt changed removal state")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,200),MOUSE_BUTTON_RIGHT)
	check(scene._ui.host.active==null,"Melt workflow retained input owner")
	exercised=true
