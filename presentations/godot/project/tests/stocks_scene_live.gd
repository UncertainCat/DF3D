extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "stocks-wire-reference.json"
func result_filename() -> String:return "job-settings-wire-result.json"

func stocks_ready() -> bool:
	if not await settle(owner.state):return false
	for frame in 3:await process_frame
	await drain()
	return check(owner.state.phase==owner.state.Phase.Ready and not owner.state.items.is_empty(),"Stocks visible item facts missing")

func exercise(expected: Dictionary) -> void:
	Engine.max_fps=30
	owner=scene._ui.controller("stocks")
	var target_id:=int(expected.selection.groups[0].ids[0])
	var tile:=Vector3i(int(expected.position[0]),int(expected.position[1]),int(expected.position[2]))
	var rig=scene.camera_rig
	for inspect in [false,true]:
		owner.open_panel()
		if not await stocks_ready():return
		var group: Dictionary=owner.state.groups[0]
		if not owner.state.expanded(group):
			await pointer(owner.panel.item_canvas.get_global_transform_with_canvas()*Vector2(60,18))
			if not await stocks_ready():return
		var button: Rect2=owner.panel.control_rect(1,-1 if inspect else -2)
		await pointer(owner.panel.item_canvas.get_global_transform_with_canvas()*button.get_center())
		await drain()
		check(owner.state.phase==owner.state.Phase.Closed and not owner.panel.visible,"Stocks did not close after navigation")
		check(world.get_top_z()==tile.z and is_equal_approx(rig.position.x,tile.x+0.5) and is_equal_approx(rig.position.z,tile.y+0.5),"Stocks camera focused wrong tile")
		check(scene._ui.item_follow.item_id==-1 and scene._ui.creature_follow.unit_id==-1,"Stocks navigation unexpectedly enabled follow")
		if inspect:
			if not await settle(owner.item_owner.state):return
			check(scene._ui.host.active==owner.item_owner and owner.item_owner.state.item_id==target_id,"View opened wrong item owner")
			var panel=owner.item_owner.panel
			await pointer(panel.get_global_transform_with_canvas()*panel.camera_rect().get_center());await drain()
			check(scene._ui.item_follow.item_id==target_id and scene._ui.item_follow.last_position==tile,"Item camera button did not follow native position")
			await pointer(panel.get_global_transform_with_canvas()*panel.camera_rect().get_center());await drain()
			check(scene._ui.item_follow.item_id==-1,"Item camera toggle did not stop follow")
			await pointer(panel.get_global_transform_with_canvas()*Vector2(100,200),MOUSE_BUTTON_RIGHT)
			check(not panel.visible and scene._ui.host.active==null and not owner.panel.visible,"Back did not close item sheet without returning to Stocks")
		else:check(scene._ui.host.active==null and not owner.item_owner.panel.visible,"Recenter retained a panel")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/stocks-main-scene.png")
	exercised=true
