extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "carrier-expected.json"
func result_filename() -> String:return "carrier-scene-result.json"
func exercise(expected: Dictionary) -> void:
	if int(expected.snapshot.carrier.kind)==2:
		await unit_carrier(expected);return
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

func unit_carrier(expected: Dictionary) -> void:
	var source=scene._ui.controller("farm").item_owner
	source.open_target(int(expected.snapshot.id))
	if not await settle(source.state):return
	var target: int=int(expected.snapshot.carrier.id)
	var camera_before: Vector3=scene.camera_rig.position
	await pointer(source.panel.get_global_transform_with_canvas()*source.panel.holder_rect().get_center())
	var inspector=scene._ui.controller("inspector")
	if not check(scene._ui.host.active==inspector and inspector.selected.get("id",-1)==target and inspector.selected.get("kind",0)==1,"Unit carrier did not open creature sheet"):return
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var info: Dictionary=world.creature_info_state(target)
		if not info.get("detail",{}).is_empty() and not info.get("loading",true):break
		await create_timer(0.02).timeout
	var detail: Dictionary=world.creature_info_state(target).get("detail",{})
	check(not detail.is_empty() and detail.get("sections",[]).size()>0,"Unit destination remained a loading shell")
	check(inspector.creature_sheet.tab=="Overview" and not source.panel.visible,"Unit destination did not start Overview")
	var view_deadline:=Time.get_ticks_msec()+5000
	while inspector.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<view_deadline:await create_timer(0.02).timeout
	check(not inspector.creature_display.get("detail",{}).is_empty(),"Creature view did not consume loaded detail")
	var hauling: Dictionary={}
	for row in inspector.creature_sheet.records_for("identity"):
		if inspector.creature_sheet.fact_value(row,"record_type")=="overview_hauling":hauling=row
	check(int(hauling.get("id",-1))==int(expected.snapshot.id),"Native hauling selector returned a different item")
	check(inspector.creature_sheet.fact_value(hauling,"native_text","")=="Haul: sweet pod seeds","Native hauling caption differs")
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-overview-scene.png")
	var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/farm-item-carrier-unit-view.png");native.convert(Image.FORMAT_RGB8)
	for region in [Rect2i(416,52,488,4),Rect2i(416,52,4,708),Rect2i(900,52,4,708),Rect2i(416,756,488,4),Rect2i(424,64,96,96),Rect2i(424,160,472,48),Rect2i(424,376,232,12)]:
		check(rendered.get_region(region).get_data()==native.get_region(region).get_data(),"Unit frame/portrait pixels differ: "+str(region))
	var evidence:=FileAccess.open(directory+"/unit-overview-scene.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"detail":detail,"panel_position":[inspector.panel.position.x,inspector.panel.position.y],"panel_size":[inspector.panel.size.x,inspector.panel.size.y]}));evidence.close()
	check(scene.camera_rig.position==camera_before,"Unit carrier unexpectedly moved camera")
	key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null and not inspector.panel.visible,"Unit sheet Escape did not release input")
	exercised=true
