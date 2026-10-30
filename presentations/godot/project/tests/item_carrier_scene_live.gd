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
	var overview_status: Dictionary={}
	for row in inspector.creature_sheet.records_for("identity"):
		if inspector.creature_sheet.fact_value(row,"record_type")=="overview_status":overview_status=row
	var overview_case: String=expected.get("overview_case","child")
	check(inspector.creature_sheet.fact_value(overview_status,"needs_summary_eligible","")==("no" if overview_case=="child" else "yes"),"Native needs gate differs")
	if overview_case=="squad-alias":check(inspector.creature_sheet.fact_value(overview_status,"squad_text","")=="Native squad alias","Native squad alias differs")
	elif overview_case!="squad":check(inspector.creature_sheet.fact_value(overview_status,"squad_text","")=="None","Native unassigned squad summary differs")
	var focus_text: String={"focused":"Focused!","focused-mild":"Focused","distracted":"Distracted!","distracted-mild":"Distracted","fresh-focused":"Focused!","fresh-distracted":"Distracted!"}.get(overview_case,"")
	check(inspector.creature_sheet.fact_value(overview_status,"focus_text","")==focus_text,"Native focus header differs")
	var offices: Array=inspector.creature_sheet.records_for("identity").filter(func(row):return inspector.creature_sheet.fact_value(row,"record_type")=="overview_office")
	var fallback: Array=inspector.creature_sheet.records_for("identity").filter(func(row):return inspector.creature_sheet.fact_value(row,"record_type")=="overview_office_fallback")
	var status_case: bool=overview_case in ["child","office-citizen","office-resident","office-excluded"]
	if status_case:
		check(fallback.size()==(0 if overview_case=="office-excluded" else 1),"Native office status eligibility differs")
		if not fallback.is_empty():
			check(inspector.creature_sheet.fact_value(fallback[0],"status","")==("Resident" if overview_case=="office-resident" else "Citizen"),"Native membership status differs")
			check(inspector.creature_sheet.fact_value(fallback[0],"position","")=="No official position","Native no-office line differs")
	else:check(fallback.is_empty(),"Office status leaked beneath titles")
	var required: Array=inspector.creature_sheet.records_for("identity").filter(func(row):return inspector.creature_sheet.fact_value(row,"record_type")=="overview_room_requirements")
	check(required.size()==1,"Missing native room requirements")
	if required.size()==1:
		var native_required: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-room-requirements.json"))
		var native_values: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-room-values.json"))
		var keys: Array=["office","bedroom","dining","tomb"]
		for i in 4:check(int(inspector.creature_sheet.fact_value(required[0],keys[i],"-1"))==int(native_required[i]),"Native room requirement differs: "+keys[i])
		for i in 4:check(int(inspector.creature_sheet.fact_value(required[0],"actual_"+keys[i],"-1"))==int(native_values[i]),"Native room value differs: "+keys[i])
	if overview_case!="child":
		var titles: Array=offices.map(func(row):return row.name)
		var expected_titles: Array={"offices":["Bookkeeper","Second office","Third office"],"office-requirements":["Bookkeeper","Second office","Third office"],"office-spouse":["Bookkeeper","Native consort"]}.get(overview_case,["Bookkeeper"])
		if status_case:expected_titles=[]
		check(titles==expected_titles,"Native office title/order differs")
		if overview_case=="office-spouse" and offices.size()==2:check(inspector.creature_sheet.fact_value(offices[1],"spouse","")=="yes","Spouse title lost its semantic source")
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-overview-scene.png")
	var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/farm-item-carrier-unit-view.png");native.convert(Image.FORMAT_RGB8)
	if status_case:
		var status_rect:=Rect2i(664,292,232,24)
		check(rendered.get_region(status_rect).get_data()==native.get_region(status_rect).get_data(),"Native office status pixels differ")
	elif overview_case!="child":
		var office_rect:=Rect2i(664,292,232,48 if overview_case=="office-requirements" else 36 if overview_case=="offices" else 24 if overview_case=="office-spouse" else 12)
		check(rendered.get_region(office_rect).get_data()==native.get_region(office_rect).get_data(),"Native office title pixels differ")
	var health_rect:=Rect2i(424,292,232,72)
	var phase_path:=directory+"/unit-health-phases.json"
	var health_labels: Array=[]
	if FileAccess.file_exists(phase_path):
		var phase_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(phase_path))
		for label in inspector.panel.find_children("*","Label",true,false):
			if label.get_script()==preload("res://scripts/creature_health_flash.gd"):
				check(label.is_processing(),"Native health animation did not start")
				label.set_process(false);health_labels.append(label)
		check(health_labels.size()==int(phase_data.get("animated_count",3)),"Missing animated native health labels")
		for phase in phase_data.phases:
			for label in health_labels: label.apply_time(int(phase.tick))
			await create_timer(1.1).timeout;await RenderingServer.frame_post_draw
			var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
			for row_index in 6:
				var rect:=Rect2i(424,292+row_index*12,232,12)
				var expected_region:=native.get_region(rect)
				var original: Dictionary=phase_data.original_rows[row_index]
				if not str(original.text).is_empty():
					# The native screenshot and later tile read can land in different
					# phases. Preserve its glyph mask, applying the controlled native color.
					var background:=expected_region.get_pixel(231,11)
					var new_color: Color=inspector.creature_sheet.NativeText.colors[int(phase.colors[row_index])]
					for py in expected_region.get_height():
						for px in expected_region.get_width():
							if not expected_region.get_pixel(px,py).is_equal_approx(background):expected_region.set_pixel(px,py,new_color)
				check(actual.get_region(rect).get_data()==expected_region.get_data(),"Native health phase pixels differ: %d row%d" % [phase.tick,row_index])
		for label in health_labels:label.set_process(true)
	else:
		check(rendered.get_region(health_rect).get_data()==native.get_region(health_rect).get_data(),"Native Overview health pixels differ")
	for region in [Rect2i(416,52,488,4),Rect2i(416,52,4,708),Rect2i(900,52,4,708),Rect2i(416,756,488,4),Rect2i(424,64,96,96),Rect2i(424,160,472,48),Rect2i(424,376,232,12),Rect2i(664,376,232,12),Rect2i(664,460,232,72)]:
		check(rendered.get_region(region).get_data()==native.get_region(region).get_data(),"Unit frame/portrait pixels differ: "+str(region))
	var evidence:=FileAccess.open(directory+"/unit-overview-scene.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"detail":detail,"panel_position":[inspector.panel.position.x,inspector.panel.position.y],"panel_size":[inspector.panel.size.x,inspector.panel.size.y]}));evidence.close()
	check(scene.camera_rig.position==camera_before,"Unit carrier unexpectedly moved camera")
	key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null and not inspector.panel.visible,"Unit sheet Escape did not release input")
	for label in health_labels:
		if is_instance_valid(label):check(not label.is_processing(),"Hidden health animation kept processing")
	exercised=true
