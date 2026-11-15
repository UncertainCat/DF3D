extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "furniture-expected.json"
func result_filename() -> String:return "workshop-wire-result.json"
func rename_to(value: String) -> bool:
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(384,30))
	if not check(owner.panel.name_entry.editing,"Furniture rename did not start"):return false
	for index in 100:key(KEY_BACKSPACE)
	for character in value:key(0,character.unicode_at(0))
	key(KEY_ENTER)
	if not await chest_ready():return false
	return check(owner.state.snapshot.custom_name==value,"Furniture name differs")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		owner.open_target(int(entry.id))
		if not await chest_ready():return
		var prefix: String="workshop-furniture-"+str(int(entry.type))+"-"
		check(owner.state.snapshot.type==int(entry.type) and owner.state.snapshot.has("appearance"),"Furniture header lacks native type/artwork")
		await panel_capture(str(int(entry.id))+"-initial",prefix+"initial")
		if not await rename_to("Furniture reference"):return
		await panel_capture(str(int(entry.id))+"-renamed",prefix+"renamed")
		if not await rename_to(String(entry.actions[0].name)):return
		var contents=owner.panel.contents
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,2).get_center())
		if not await chest_ready():return
		check(owner.state.snapshot.forbidden and owner.contents.snapshot.rows[0].forbid,"Furniture Forbid did not refresh header and item")
		await panel_capture(str(int(entry.id))+"-forbidden",prefix+"forbidden")
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,2).get_center())
		if not await chest_ready():return
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(416,30))
		if not await chest_ready():return
		check(owner.state.snapshot.removing,"Furniture removal not confirmed")
		await panel_capture(str(int(entry.id))+"-removing",prefix+"removing")
		if OS.get_environment("DF3D_FURNITURE_REMOVAL_CONTROLS")=="1":
			for control in [[2,"forbid"],[3,"dump"],[4,"melt"],[5,"hidden"]]:
				var before: bool=owner.contents.snapshot.rows[0][control[1]]
				for attempt in [1,2]:
					await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,control[0]).get_center())
					if not await chest_ready():return
					check(owner.contents.snapshot.rows[0][control[1]]==(before if control[1]=="melt" or attempt==2 else not before),"Removal component flag differs: "+control[1])
					check(owner.state.snapshot.removing and owner.contents.snapshot.removing,"Component edit lost demolition state")
					var label: String="removing-"+control[1]+"-"+str(attempt)
					await panel_capture(str(int(entry.id))+"-"+label,prefix+label)
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
		if not await chest_ready():return
		check(not owner.state.snapshot.removing,"Furniture removal cancellation not confirmed")
		await panel_capture(str(int(entry.id))+"-restored",prefix+"restored")
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,1).get_center())
		if not await settle(owner.item_owner.state):return
		check(owner.item_owner.state.item_id==int(entry.actions[0].item_id) and scene._ui.host.active==owner.item_owner and not owner.panel.visible,"Furniture View did not transfer ownership to its component")
		await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*owner.item_owner.panel.holder_rect().get_center())
		if not await chest_ready():return
		check(owner.state.building_id==int(entry.id),"Item holder returned to a different building")
		await panel_capture(str(int(entry.id))+"-holder-return",prefix+"restored")
		if int(entry.type)==1 and OS.get_environment("DF3D_FURNITURE_RESIZE")=="1":
			for size_case in [["small",Vector2i(960,600)],["medium",Vector2i(1200,720)],["wide",Vector2i(1600,900)],["default",Vector2i(1200,800)]]:
				root.size=size_case[1];await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
				var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
				var native:=Image.load_from_file(directory+"/workshop-furniture-1-resize-"+size_case[0]+".png");native.convert(Image.FORMAT_RGB8)
				var crop:=image.get_region(region);crop.save_png(directory+"/furniture-resize-"+size_case[0]+".png")
				check(crop.get_data()==native.get_region(region).get_data(),"Furniture resize differs: "+size_case[0])
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null and not owner.panel.visible,"Furniture Escape retained input")
	exercised=true
