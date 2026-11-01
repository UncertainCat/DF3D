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
	if FileAccess.file_exists(directory+"/unit-health-pages-native.json"):
		var native_health: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-health-pages-native.json"))
		var health_pages: Array=detail.get("health_pages",[])
		check(health_pages.size()==5 and health_pages.is_read_only(),"Health page transport missing or mutable")
		for i in mini(5,health_pages.size()):
			check(health_pages[i].kind==i and health_pages[i].rows==native_health.pages[i].tagged_rows,"Native Health rows changed in transport: "+str(i))
			check(health_pages[i].is_read_only() and health_pages[i].rows.is_read_only(),"Health nested publication is mutable")
		var health_file:=FileAccess.open(directory+"/unit-health-wire-result.json",FileAccess.WRITE)
		health_file.store_string(JSON.stringify({"success":not failed,"pages":health_pages}));health_file.close()
	if FileAccess.file_exists(directory+"/unit-skills-native.json"):
		var native_skills: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-skills-native.json"))
		var skill_pages: Array=detail.get("skills_pages",[])
		check(skill_pages.size()==5 and skill_pages.is_read_only(),"Skills transport missing or mutable")
		for i in mini(5,skill_pages.size()):
			var page: Dictionary=skill_pages[i]
			var native: Dictionary=native_skills.pages[i]
			check(page.kind==native.tab and page.is_read_only() and page.rows.is_read_only(),"Skills page identity or ownership changed")
			var ids: Array=native.knowledge_ids if i==4 else native.skills
			check(page.rows.size()==ids.size(),"Skills row count changed")
			for j in mini(page.rows.size(),ids.size()):
				var row: Dictionary=page.rows[j]
				check(row.is_read_only() and row.id==ids[j] and row.caption==native.probe.captions[j],"Native Skills row or caption changed")
				if i==4:check(row.knowledge_type==native.knowledge_types[j] and row.knowledge_bits==native.knowledge_bits[j] and row.subtitle==native.probe.subtitles[j],"Knowledge semantics changed")
				else:
					check(row.rating==native.values[j] and row.rust_value==native.rust_values[j],"Native skill ratings changed")
					var color: Array=native.probe.colors[j]
					check(row.caption_color==(int(color[0])|(int(color[1])<<3)|(int(color[2])<<6)),"Native skill color changed")
				if i==4:check(row.caption_color==-1,"Knowledge acquired skill color")
		var skill_file:=FileAccess.open(directory+"/unit-skills-wire-result.json",FileAccess.WRITE)
		skill_file.store_string(JSON.stringify({"success":not failed,"pages":skill_pages}));skill_file.close()
	check(inspector.creature_sheet.tab=="Overview" and not source.panel.visible,"Unit destination did not start Overview")
	var view_deadline:=Time.get_ticks_msec()+5000
	while inspector.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<view_deadline:await create_timer(0.02).timeout
	check(not inspector.creature_display.get("detail",{}).is_empty(),"Creature view did not consume loaded detail")
	if FileAccess.file_exists(directory+"/unit-items-wire-expected.json"):
		var native_items: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-items-wire-expected.json"))
		var expected_rows: Array=[]
		for row in native_items.rows:
			expected_rows.append({"id":row.id,"kind":0,"caption":row.caption,"role":row.role,"parent":-1,"indicator":row.indicator})
			for child in row.contents:expected_rows.append({"id":child.id,"kind":child.kind,"caption":child.caption,"role":"","parent":row.id})
		for row in native_items.spatters:expected_rows.append({"id":-1,"kind":3,"caption":row.caption,"role":row.body_part_caption,"parent":-1})
		var actual_rows: Array=inspector.creature_sheet.records_for("inventory")
		check(actual_rows.size()==expected_rows.size(),"Native Items wire row count differs")
		for index in mini(actual_rows.size(),expected_rows.size()):
			var actual: Dictionary=actual_rows[index]
			var wanted: Dictionary=expected_rows[index]
			check(actual.get("name","")==wanted.caption and int(actual.get("related_id",-1))==int(wanted.id),"Native Items wire caption/target differs at "+str(index))
			check(int(inspector.creature_sheet.fact_value(actual,"row_kind",-1))==int(wanted.kind),"Native Items wire kind differs")
			check(int(inspector.creature_sheet.fact_value(actual,"assignment_indicator",-1))==int(wanted.get("indicator",-1)),"Native Items wire assignment differs")
			check(int(inspector.creature_sheet.fact_value(actual,"parent_item_id",-1))==int(wanted.parent),"Native Items wire parent differs")
			check(inspector.creature_sheet.record_text(actual,"inventory")==wanted.role,"Native Items wire role differs at "+str(index))
		var items_wire: Dictionary={"success":not failed,"expected":expected_rows,"actual":actual_rows}
		var items_file:=FileAccess.open(directory+"/unit-items-wire-result.json",FileAccess.WRITE)
		items_file.store_string(JSON.stringify(items_wire,"  "));items_file.close()
	if FileAccess.file_exists(directory+"/unit-customize-captions.json"):
		var captions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-customize-captions.json"))
		var records: Array=inspector.creature_sheet.records_for("identity").filter(func(row):return inspector.creature_sheet.fact_value(row,"record_type")=="customize_captions")
		check(records.size()==1,"Missing native Customize captions")
		if records.size()==1:
			for key in ["name","profession"]:check(inspector.creature_sheet.fact_value(records[0],key)==captions[key],"Customize wire caption differs: "+key)
	var hauling: Dictionary={}
	for row in inspector.creature_sheet.records_for("identity"):
		if inspector.creature_sheet.fact_value(row,"record_type")=="overview_hauling":hauling=row
	check(int(hauling.get("id",-1))==int(expected.snapshot.id),"Native hauling selector returned a different item")
	check(inspector.creature_sheet.fact_value(hauling,"native_text","")=="Haul: sweet pod seeds","Native hauling caption differs")
	var overview_status: Dictionary={}
	for row in inspector.creature_sheet.records_for("identity"):
		if inspector.creature_sheet.fact_value(row,"record_type")=="overview_status":overview_status=row
	var overview_case: String=expected.get("overview_case","child")
	var cannot_learn: bool=expected.get("header_case","")=="cannot-learn"
	var ghost: bool=expected.get("health_case","")=="ghost"
	check(inspector.creature_sheet.fact_value(overview_status,"needs_summary_eligible","")==("no" if overview_case=="child" or cannot_learn or ghost else "yes"),"Native needs gate differs")
	if overview_case=="squad-alias":check(inspector.creature_sheet.fact_value(overview_status,"squad_text","")=="Native squad alias","Native squad alias differs")
	elif overview_case!="squad":check(inspector.creature_sheet.fact_value(overview_status,"squad_text","")==("" if cannot_learn or ghost else "None"),"Native unassigned squad summary differs")
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
	var header_status_rect:=Rect2i(528,100,264,12)
	var activity_rect:=Rect2i(528,112,264,12)
	var combat_rect:=Rect2i(664,376,232,72)
	check(rendered.get_region(combat_rect).get_data()==native.get_region(combat_rect).get_data(),"Native combat skill rows differ")
	check(rendered.get_region(activity_rect).get_data()==native.get_region(activity_rect).get_data(),"Native activity pixels differ")
	var header_name_rect:=Rect2i(528,64,264,24)
	check(rendered.get_region(header_name_rect).get_data()==native.get_region(header_name_rect).get_data(),"Native header name pixels differ")
	var translated_name_rect:=Rect2i(528,88,264,12)
	check(rendered.get_region(translated_name_rect).get_data()==native.get_region(translated_name_rect).get_data(),"Native translated name pixels differ")
	check(rendered.get_region(header_status_rect).get_data()==native.get_region(header_status_rect).get_data(),"Native header status pixels differ")
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
	if OS.get_environment("DF3D_UNIT_HEALTH_VIEW")=="1":
		await exercise_health_view(inspector)
		if failed:return
	if OS.get_environment("DF3D_UNIT_ITEMS_VIEW")=="1":
		await exercise_items_view(inspector,target)
		if failed:return
	if FileAccess.file_exists(directory+"/unit-customize-captions.json"):
		await exercise_customize(inspector,int(expected.snapshot.id))
	if ghost:check(not is_instance_valid(inspector.expel_button) or not inspector.expel_button.is_visible_in_tree(),"Ghost exposed Expel absent from native")
	elif overview_case=="neutral":await exercise_expel_preview(inspector,target)
	key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null and not inspector.panel.visible,"Unit sheet Escape did not release input")
	for label in health_labels:
		if is_instance_valid(label):check(not label.is_processing(),"Hidden health animation kept processing")
	if not health_labels.is_empty():
		source.open_target(int(expected.snapshot.id))
		if not await settle(source.state):return
		await pointer(source.panel.get_global_transform_with_canvas()*source.panel.holder_rect().get_center())
		var reopen_deadline:=Time.get_ticks_msec()+5000
		while (not inspector.panel.visible or inspector.creature_display.get("detail",{}).is_empty()) and Time.get_ticks_msec()<reopen_deadline:await create_timer(0.02).timeout
		await process_frame;await process_frame
		check(scene._ui.host.active==inspector and inspector.selected.get("id",-1)==target,"Unit reopen lost input owner or identity")
		var resumed: Array=[]
		for label in inspector.panel.find_children("*","Label",true,false):
			if label.get_script()==preload("res://scripts/creature_health_flash.gd"):
				check(label.is_visible_in_tree() and label.is_processing(),"Reopened health animation did not resume")
				resumed.append(label)
		check(resumed.size()==health_labels.size(),"Reopening duplicated or lost animated health rows")
		check(scene.camera_rig.position==camera_before,"Reopening Unit sheet moved camera")
		key(KEY_ESCAPE);await process_frame
		check(scene._ui.host.active==null and not inspector.panel.visible,"Reopened Unit sheet retained input")
		for label in resumed:
			if is_instance_valid(label):check(not label.is_processing(),"Reopened health animation did not retire")
	if FileAccess.file_exists(directory+"/unit-camera-native.json"):
		await exercise_follow(inspector,source,int(expected.snapshot.id),target)
	await exercise_history(inspector,source,int(expected.snapshot.id),target)
	if OS.get_environment("DF3D_UNIT_HEALTH_LIFECYCLE")=="1":await exercise_items_lifecycle(inspector,target,true)
	elif OS.get_environment("DF3D_UNIT_ITEMS_LIFECYCLE")=="1":await exercise_items_lifecycle(inspector,target)
	exercised=true

func health_tab(inspector,title: String) -> bool:
	for child in inspector.body.get_children():
		if child is Button and child.text==title:
			await pointer(child.get_global_transform_with_canvas()*(child.size*0.5))
			await process_frame;await process_frame
			return true
	return check(false,"Missing creature tab: "+title)

func exercise_health_view(inspector) -> void:
	if not await health_tab(inspector,"Health"):return
	var samples: Array=[]
	for name in ["Status","Wounds","Treatment","History","Description"]:
		if not await health_tab(inspector,name):return
		var view=inspector.creature_sheet.health_view
		if not check(is_instance_valid(view) and view.is_visible_in_tree(),"Health view missing: "+name):return
		await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		actual.save_png(directory+"/unit-health-"+name.to_lower()+"-scene.png")
		var expected:=Image.load_from_file(directory+"/unit-health-page-"+name.to_lower()+".png");expected.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(432,244,424,492)
		check(actual.get_region(rect).get_data()==expected.get_region(rect).get_data(),"Composed native Health text pixels differ: "+name)
		var before: Array=view.lines.duplicate(true)
		inspector.redraw();await process_frame;await process_frame
		check(inspector.creature_sheet.health_view==view and view.lines==before,"Health refresh replaced control or changed native text: "+name)
		samples.append({"name":name,"lines":view.lines.size(),"pixels_match":actual.get_region(rect).get_data()==expected.get_region(rect).get_data()})
	if OS.get_environment("DF3D_UNIT_HEALTH_OVERFLOW")=="1":
		await exercise_health_overflow(inspector)
		if failed:return
	if OS.get_environment("DF3D_UNIT_HEALTH_IDENTITY")=="1":
		await exercise_health_identity(inspector)
		if failed:return
	var previous=inspector.creature_sheet.health_view
	if not await health_tab(inspector,"Overview"):return
	check(not is_instance_valid(previous) or not previous.is_visible_in_tree(),"Health tab departure retained visible content")
	if not await health_tab(inspector,"Health"):return
	check(inspector.creature_sheet.subtabs.Health=="Status" and is_instance_valid(inspector.creature_sheet.health_view),"Health tab return did not reset to native Status")
	if not await health_tab(inspector,"Overview"):return
	var evidence:=FileAccess.open(directory+"/unit-health-view-result.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"success":not failed,"pages":samples,"retained_refresh":true,"tab_return":true}));evidence.close()

func exercise_health_overflow(inspector) -> void:
	if not await health_tab(inspector,"History"):return
	var view=inspector.creature_sheet.health_view
	if not check(view.lines.size()==75 and view.scrollbar.visible,"Health History overflow missing"):return
	var wheel_point: Vector2=view.get_global_transform_with_canvas()*Vector2(120,100)
	for _i in 7:await pointer(wheel_point,MOUSE_BUTTON_WHEEL_DOWN)
	check(view.first==7,"Composed Health wheel differs")
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(880,400);root.push_input(motion,true)
	var press:=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
	check(view.scrollbar.dragging,"Composed Health drag did not start")
	inspector.redraw();await process_frame
	check(inspector.creature_sheet.health_view==view and view.scrollbar.dragging,"Health redraw retired active drag")
	motion=InputEventMouseMotion.new();motion.position=Vector2(880,500);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	press=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;root.push_input(press,true)
	check(view.first==17 and not view.scrollbar.dragging,"Composed Health drag differs from native")
	var away:=InputEventMouseMotion.new();away.position=Vector2(400,400);root.push_input(away,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8);image.save_png(directory+"/unit-health-drag-scene.png")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_health_pages_reference.layout_reference
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(Rect2i(432,244,424,492)).get_data())
	check(hash.finish().hex_encode()==reference.drag_text_rgb_sha256,"Composed scrolled Health text differs from native")
	scene._fortress_hud.toggle_settings();await process_frame
	await pointer(wheel_point,MOUSE_BUTTON_WHEEL_DOWN)
	check(view.first==17,"Settings allowed Health input underneath")
	scene._fortress_hud.toggle_settings();await process_frame
	root.size=Vector2i(960,600);await process_frame;await process_frame
	check(inspector.creature_sheet.health_view==view and view.capacity()==25 and view.first==17,"Health resize lost position or control")
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	check(view.capacity()==41 and view.first==17,"Health resize return differs")
	if not await health_tab(inspector,"Status"):return
	check(inspector.creature_sheet.health_view==view and view.first==17,"Health subtab lost shared scroll")
	if not await health_tab(inspector,"History"):return
	check(view.first==17,"Health History return lost shared scroll")
	var grip: Vector2i=view.scrollbar.thumb()
	motion=InputEventMouseMotion.new();motion.position=view.scrollbar.get_global_transform_with_canvas()*Vector2(8,(grip.x+grip.y*0.5)*12);root.push_input(motion,true)
	press=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
	check(view.scrollbar.dragging,"Health close test drag missing")
	var target:=int(inspector.selected.id)
	var entity: Dictionary=world.inspect_entity(1,target)
	key(KEY_ESCAPE);await process_frame
	check(not inspector.is_open() and scene._ui.host.active==null and inspector.selected.is_empty(),"Health Escape retained panel owner")
	check(not is_instance_valid(view) or (not view.scrollbar.dragging and not view.allowed()),"Health close retained drag or input")
	press=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;root.push_input(press,true)
	inspector.open_target(entity.tile,1,target)
	var deadline:=Time.get_ticks_msec()+5000
	while inspector.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	check(inspector.is_open() and inspector.creature_sheet.tab=="Overview","Same creature reopen did not reset to native Overview")
	if not await health_tab(inspector,"Health"):return
	check(inspector.creature_sheet.subtabs.Health=="Status" and inspector.creature_sheet.health_view.first==0,"Health reopen did not reset to native Status/top")
	var evidence:=FileAccess.open(directory+"/unit-health-overflow-result.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"success":not failed,"native_drag_text":true,"refresh_during_drag":true,"overlay_blocks_input":true,"resize_retains_scroll":true,"shared_subtab_scroll":true,"close_retires_drag":true,"reopen_resets_overview":true,"health_reopens_status_top":true}));evidence.close()

func exercise_health_identity(inspector) -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-health-layout-native.json"))
	var targets: Array=[]
	for sample in reference.observations:
		if sample.name in ["identity-other-health","identity-return-health"]:targets.append(sample)
	if not check(targets.size()==2,"Native Health identity reference missing"):return
	if not await health_tab(inspector,"History"):return
	var old_view=inspector.creature_sheet.health_view
	if not check(old_view.scrollbar.visible,"Health identity test requires overflow"):return
	var grip: Vector2i=old_view.scrollbar.thumb()
	var point: Vector2=old_view.scrollbar.get_global_transform_with_canvas()*Vector2(8,(grip.x+grip.y*0.5)*12)
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	var button:=InputEventMouseButton.new();button.position=point;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true;root.push_input(button,true)
	check(old_view.scrollbar.dragging,"Health identity drag did not start")
	var results: Array=[]
	for sample in targets:
		var id:=int(sample.unit_id);var entity: Dictionary=world.inspect_entity(1,id)
		if not check(not entity.is_empty(),"Health identity target missing from world model"):return
		inspector.open_target(entity.tile,1,id)
		await process_frame
		check(not is_instance_valid(old_view) or (not old_view.is_visible_in_tree() and not old_view.scrollbar.dragging),"Different creature retained old Health view or gesture")
		button=InputEventMouseButton.new();button.position=point;button.button_index=MOUSE_BUTTON_LEFT;root.push_input(button,true)
		check(inspector.selected.id==id and inspector.creature_sheet.tab=="Overview","Creature identity change did not reset to native Overview")
		var deadline:=Time.get_ticks_msec()+5000
		while int(inspector.creature_display.get("detail",{}).get("unit_id",-1))!=id and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
		if not check(int(inspector.creature_display.get("detail",{}).get("unit_id",-1))==id,"Creature detail publication retained previous identity"):return
		if not await health_tab(inspector,"Health"):return
		var view=inspector.creature_sheet.health_view
		check(inspector.creature_sheet.subtabs.Health=="Status" and view.first==0,"Different creature retained old Health page or scroll")
		await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		actual.save_png(directory+"/unit-health-"+sample.name+"-scene.png")
		var native:=Image.load_from_file(directory+"/unit-health-layout-"+sample.name+".png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(432,244,424,492)
		var matched:=actual.get_region(rect).get_data()==native.get_region(rect).get_data()
		check(matched,"Different creature Health text differs from native")
		results.append({"unit_id":id,"native_pixels_match":matched,"lines":view.lines.size()})
		old_view=view
	var file:=FileAccess.open(directory+"/unit-health-identity-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"old_drag_retired":true,"targets":results}));file.close()

func items_lifecycle_transition(operation: String) -> void:
	var file:=FileAccess.open(directory+"/unit-items-lifecycle-request.tmp",FileAccess.WRITE)
	file.store_string(JSON.stringify({"op":operation}));file.close()
	DirAccess.rename_absolute(directory+"/unit-items-lifecycle-request.tmp",directory+"/unit-items-lifecycle-request.json")
	var deadline:=Time.get_ticks_msec()+5000
	while not FileAccess.file_exists(directory+"/unit-items-lifecycle-ack.json") and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	if not check(FileAccess.file_exists(directory+"/unit-items-lifecycle-ack.json"),"Items lifecycle acknowledgement timed out"):return
	var ack: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-items-lifecycle-ack.json"))
	DirAccess.remove_absolute(directory+"/unit-items-lifecycle-ack.json")
	check(ack.op==operation,"Items lifecycle acknowledgement differs")

func exercise_items_lifecycle(inspector,target: int,health:=false) -> void:
	var prefix:="unit-health-lifecycle" if health else "unit-items-lifecycle"
	var entity: Dictionary=world.inspect_entity(1,target)
	inspector.open_target(entity.tile,1,target)
	var deadline:=Time.get_ticks_msec()+5000
	while inspector.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	if health:
		if not await health_tab(inspector,"Health"):return
		if not await health_tab(inspector,"History"):return
	else:await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(124,132))
	root.size=Vector2i(960,600);await process_frame;await process_frame
	var view=inspector.creature_sheet.health_view if health else inspector.creature_sheet.items_view
	if not check(is_instance_valid(view) and view.scrollbar.visible,"Lifecycle creature overflow missing"):return
	var grip: Vector2i=view.scrollbar.thumb()
	var point: Vector2=view.scrollbar.get_global_transform_with_canvas()*Vector2(8,(grip.x+grip.y*0.5)*12)
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	var button:=InputEventMouseButton.new();button.position=point;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true;root.push_input(button,true)
	await process_frame
	check(view.scrollbar.dragging,"Lifecycle drag did not start")
	await items_lifecycle_transition("disable")
	deadline=Time.get_ticks_msec()+5000
	while scene._ui.host.active!=null and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	check(not inspector.panel.visible and scene._ui.host.active==null and inspector.selected.is_empty(),"Bridge loss retained creature owner")
	check(not is_instance_valid(view) or (not view.scrollbar.dragging and not view.allowed()),"Bridge loss retained creature gesture or input")
	button=InputEventMouseButton.new();button.position=point;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=false;root.push_input(button,true)
	await items_lifecycle_transition("enable")
	deadline=Time.get_ticks_msec()+10000
	while (actions._transport_lost or not world.poll_management().get("transport_alive",false)) and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	check(not actions._transport_lost and world.poll_management().get("transport_alive",false),"Replacement producer did not recover")
	check(not inspector.panel.visible and scene._ui.host.active==null,"Replacement producer reopened retired creature panel")
	deadline=Time.get_ticks_msec()+30000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if not check(scene._loader.entered and scene._ui.host.play_enabled,"Replacement fortress did not finish loading"):return
	deadline=Time.get_ticks_msec()+10000
	entity=world.inspect_entity(1,target)
	while entity.is_empty() and Time.get_ticks_msec()<deadline:
		await create_timer(0.02).timeout
		entity=world.inspect_entity(1,target)
	if not check(not entity.is_empty(),"Replacement creature identity did not arrive"):return
	inspector.open_target(entity.tile,1,target)
	deadline=Time.get_ticks_msec()+5000
	while inspector.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	if health:
		if not await health_tab(inspector,"Health"):return
		if not await health_tab(inspector,"History"):return
	else:await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(124,132))
	var reopened=inspector.creature_sheet.health_view if health else inspector.creature_sheet.items_view
	check(inspector.creature_sheet.tab==("Health" if health else "Items") and is_instance_valid(reopened) and not reopened.rows.is_empty() and scene._ui.host.active==inspector,"Explicit creature tab reopen failed after replacement")
	if health:check(reopened.lines.size()==75 and reopened.first==0,"Reconnected Health history lost native rows or reset")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/"+prefix+"-reopened.png")
	var file:=FileAccess.open(directory+"/"+prefix+"-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"drag_retired":true,"owner_retired":true,"no_automatic_reopen":true,"explicit_reopen":true}));file.close()
	inspector.close_panel();root.size=Vector2i(1200,800)

func exercise_items_view(inspector,target: int) -> void:
	if OS.get_environment("DF3D_UNIT_ITEMS_CONTAINED_SCENE")=="1":
		await exercise_contained_items(inspector,target);return
	await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(124,132))
	await process_frame;await process_frame
	if not check(inspector.creature_sheet.tab=="Items","Items tab click did not select Items"):return
	var view=inspector.creature_sheet.items_view
	if not check(is_instance_valid(view) and view.is_visible_in_tree(),"Items view is not visible"):return
	if not check(not view.rows.is_empty(),"Items view has no rows"):return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-scene.png")
	check(int(view.fact(view.rows[0],"assignment_indicator",-1))==1,"Baseline clothing assignment missing")
	var hover_motion:=InputEventMouseMotion.new()
	hover_motion.position=view.get_global_transform_with_canvas()*view.indicator_rect(0).get_center();root.push_input(hover_motion,true)
	await create_timer(0.65).timeout;await process_frame;await RenderingServer.frame_post_draw
	check(inspector.hover_help.visible and inspector.hover_help.displayed=="unit_inventory_clothing","Clothing help missing")
	root.get_texture().get_image().save_png(directory+"/unit-items-clothing-help-scene.png")
	await pointer(hover_motion.position)
	check(scene._ui.host.active==inspector and inspector.creature_sheet.tab=="Items","Clothing indicator click navigated")
	hover_motion=InputEventMouseMotion.new();hover_motion.position=view.get_global_transform_with_canvas()*view.inspect_rect(0).get_center();root.push_input(hover_motion,true)
	await create_timer(0.65).timeout;await process_frame;await RenderingServer.frame_post_draw
	check(inspector.hover_help.visible and inspector.hover_help.displayed=="unit_inventory_view","Inventory View help missing")
	root.size=Vector2i(960,600);await process_frame;await process_frame
	view=inspector.creature_sheet.items_view
	check(view.capacity()==9 and view.scrollbar.visible,"Small Items viewport did not show native overflow")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-resized-scene.png")
	var wheel_point: Vector2=view.get_global_transform_with_canvas()*Vector2(120,100)
	await pointer(wheel_point,MOUSE_BUTTON_WHEEL_DOWN);await pointer(wheel_point,MOUSE_BUTTON_WHEEL_DOWN)
	check(view.first==2,"Items wheel did not advance one row")
	await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(40,132))
	await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(124,132))
	view=inspector.creature_sheet.items_view
	check(inspector.creature_sheet.tab=="Items" and view.first==2,"Items tab return lost scroll position")
	check(int(view.fact(view.rows[view.first],"assignment_indicator",-1))==1,"Items tab return lost clothing assignment facts")
	var scroll_rows:=FileAccess.open(directory+"/unit-items-scroll-rows.json",FileAccess.WRITE)
	scroll_rows.store_string(JSON.stringify(view.rows,"  "));scroll_rows.close()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-tab-return-scene.png")
	var grip: Vector2i=view.scrollbar.thumb()
	var drag_point: Vector2=view.scrollbar.get_global_transform_with_canvas()*Vector2(8,(grip.x+grip.y*0.5)*12)
	var drag_motion:=InputEventMouseMotion.new();drag_motion.position=drag_point;root.push_input(drag_motion,true)
	var drag_button:=InputEventMouseButton.new();drag_button.position=drag_point;drag_button.button_index=MOUSE_BUTTON_LEFT;drag_button.pressed=true;root.push_input(drag_button,true)
	await process_frame
	check(view.scrollbar.dragging,"Items scrollbar drag did not start")
	if OS.get_environment("DF3D_UNIT_ITEMS_REFRESH")=="1":await exercise_items_refresh(inspector,target,view)
	inspector.redraw();await process_frame
	check(inspector.creature_sheet.items_view==view and view.scrollbar.dragging,"Header redraw replaced the active Items drag")
	drag_motion=InputEventMouseMotion.new();drag_motion.position=view.scrollbar.get_global_transform_with_canvas()*Vector2(8,240);root.push_input(drag_motion,true)
	drag_button=InputEventMouseButton.new();drag_button.position=drag_motion.position;drag_button.button_index=MOUSE_BUTTON_LEFT;drag_button.pressed=false;root.push_input(drag_button,true)
	check(view.first==2 and not view.scrollbar.dragging,"Items drag did not continue and release after redraw")
	if OS.get_environment("DF3D_UNIT_ITEMS_ASSIGNMENT_REFRESH")=="1":await exercise_assignment_refresh(inspector,target,view)
	scene._fortress_hud.toggle_settings();await process_frame
	await pointer(wheel_point,MOUSE_BUTTON_WHEEL_DOWN)
	check(view.first==2,"Settings allowed Items scrolling underneath")
	scene._fortress_hud.toggle_settings();await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-scroll-small-scene.png")
	var small_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_items_reference.layout_reference
	for name in ["unit-items-resized-scene","unit-items-tab-return-scene","unit-items-scroll-small-scene"]:
		var sample:=Image.load_from_file(directory+"/"+name+".png");sample.convert(Image.FORMAT_RGB8)
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(sample.get_region(Rect2i(568,204,24,36)).get_data())
		check(digest.finish().hex_encode()==small_reference.small_clothing_rgb_sha256,"Items clothing pixels changed after resize/tab/overlay: "+name)
	await pointer(wheel_point,MOUSE_BUTTON_WHEEL_UP);await pointer(wheel_point,MOUSE_BUTTON_WHEEL_UP)
	check(view.first==0,"Items scroll did not return to the first row")
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	view=inspector.creature_sheet.items_view
	check(view.capacity()==14 and view.first==0 and not view.scrollbar.visible,"Items resize did not restore baseline layout")
	var item_id:=int(view.rows[0].get("related_id",-1))
	var item_owner=scene._ui.controller("farm").item_owner
	var transitions: Array=[]
	var observe: Callable=func():transitions.append({"phase":item_owner.state.phase,"id":item_owner.state.item_id,"snapshot":item_owner.state.snapshot.duplicate(true),"stack":get_stack()})
	item_owner.state.changed.connect(observe)
	await pointer(view.get_global_transform_with_canvas()*view.inspect_rect(0).get_center())
	var ready:=await settle(item_owner.state)
	item_owner.state.changed.disconnect(observe)
	var trace:=FileAccess.open(directory+"/unit-items-navigation-trace.json",FileAccess.WRITE)
	trace.store_string(JSON.stringify({"transitions":transitions,"phase":item_owner.state.phase,"id":item_owner.state.item_id},"  "));trace.close()
	if not ready:return
	check(scene._ui.host.active==item_owner and item_owner.state.item_id==item_id,"Items View did not open the selected item")
	check(item_owner.state.snapshot.has("appearance") and item_owner.panel.icon!=null,"Clothing sheet lost semantic artwork")
	check(item_owner.state.snapshot.get("owner",{}).get("id",-1)==target,"Clothing wire lost native owner identity")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-inspected-scene.png")
	var snapshot:=FileAccess.open(directory+"/unit-items-inspected-scene.json",FileAccess.WRITE)
	snapshot.store_string(JSON.stringify(item_owner.state.snapshot,"  "));snapshot.close()
	if OS.get_environment("DF3D_ITEM_OWNER_REFRESH")=="1":await exercise_owner_refresh(item_owner,item_id,target)
	await pointer(item_owner.panel.get_global_transform_with_canvas()*item_owner.panel.holder_rect().get_center())
	await process_frame;await process_frame
	check(scene._ui.host.active==inspector and inspector.selected.get("id",-1)==target,"Item carrier did not return to the creature")
	check(inspector.creature_sheet.tab=="Overview","Item carrier did not reset to native Overview")
	var result:=FileAccess.open(directory+"/unit-items-view-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"success":not failed,"inspected_item":item_id,"creature":target}));result.close()

func exercise_items_refresh(inspector,target: int,view) -> void:
	var baseline: int=view.rows.size()
	var observations: Array=[]
	var serial:=0
	for operation in ["add","restore"]:
		serial+=1
		var file:=FileAccess.open(directory+"/unit-items-refresh-request.tmp",FileAccess.WRITE)
		file.store_string(JSON.stringify({"unit_id":target,"op":operation,"serial":serial}));file.close()
		DirAccess.rename_absolute(directory+"/unit-items-refresh-request.tmp",directory+"/unit-items-refresh-request.json")
		var deadline:=Time.get_ticks_msec()+10000
		while not FileAccess.file_exists(directory+"/unit-items-refresh-ack.json") and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
		if not check(FileAccess.file_exists(directory+"/unit-items-refresh-ack.json"),"Contents refresh acknowledgement timed out"):return
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-items-refresh-ack.json"))
		DirAccess.remove_absolute(directory+"/unit-items-refresh-ack.json")
		check(int(expected.serial)==serial and expected.op==operation,"Contents acknowledgement mismatched")
		var count:=baseline+(1 if operation=="add" else 0)
		deadline=Time.get_ticks_msec()+10000
		while view.rows.size()!=count and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
		check(view.rows.size()==count,"Automatic creature refresh missed changed contents: "+operation)
		check(inspector.creature_sheet.items_view==view and view.scrollbar.dragging and view.first==2,"Contents refresh replaced held gesture or offset")
		if operation=="add" and view.rows.size()==count:
			var native: Dictionary=expected.native.rows[0].contents[0]
			check(int(view.rows[1].related_id)==int(native.id) and view.rows[1].name==native.caption,"Refreshed contained row differs from native")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/unit-items-refresh-"+operation+".png")
		observations.append({"op":operation,"rows":view.rows.size(),"first":view.first,"dragging":view.scrollbar.dragging})
	var file:=FileAccess.open(directory+"/unit-items-refresh-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"observations":observations}));file.close()

func exercise_assignment_refresh(inspector,target: int,view) -> void:
	view.scrollbar.move_to(0)
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_items_reference.indicator_reference
	var observations: Array=[]
	var serial:=2
	for sample in [["squad",0,"squad","unit_inventory_squad"],["tool",2,"work-before-clothing","unit_inventory_tool"],["restore",1,"clothing","unit_inventory_clothing"]]:
		serial+=1
		var file:=FileAccess.open(directory+"/unit-items-refresh-request.tmp",FileAccess.WRITE)
		file.store_string(JSON.stringify({"unit_id":target,"op":sample[0],"serial":serial}));file.close()
		DirAccess.rename_absolute(directory+"/unit-items-refresh-request.tmp",directory+"/unit-items-refresh-request.json")
		var deadline:=Time.get_ticks_msec()+10000
		while not FileAccess.file_exists(directory+"/unit-items-refresh-ack.json") and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
		if not check(FileAccess.file_exists(directory+"/unit-items-refresh-ack.json"),"Assignment acknowledgement timed out"):return
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-items-refresh-ack.json"))
		DirAccess.remove_absolute(directory+"/unit-items-refresh-ack.json")
		check(int(expected.serial)==serial and expected.op==sample[0] and int(expected.native.rows[0].indicator)==sample[1],"Assignment native reference differs")
		deadline=Time.get_ticks_msec()+10000
		while int(view.fact(view.rows[0],"assignment_indicator",-1))!=sample[1] and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
		check(int(view.fact(view.rows[0],"assignment_indicator",-1))==sample[1] and inspector.creature_sheet.items_view==view,"Automatic assignment refresh missed native change")
		var motion:=InputEventMouseMotion.new();motion.position=view.get_global_transform_with_canvas()*view.indicator_rect(0).get_center();root.push_input(motion,true)
		await create_timer(0.65).timeout;await RenderingServer.frame_post_draw
		check(inspector.hover_help.visible and inspector.hover_help.displayed==sample[3],"Assignment refresh retained stale tooltip")
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var rect: Rect2=view.indicator_rect(0);rect.position=view.get_global_transform_with_canvas()*rect.position
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(Rect2i(rect)).get_data())
		var digest:=hash.finish().hex_encode()
		var native: Dictionary=reference.cases.filter(func(row):return row.name==sample[2])[0]
		check(digest==native.indicator_rgb_sha256,"Refreshed assignment icon differs from native")
		image.save_png(directory+"/unit-items-assignment-"+sample[0]+".png")
		observations.append({"op":sample[0],"indicator":sample[1],"help":inspector.hover_help.displayed,"rgb_sha256":digest})
	view.scrollbar.move_to(2)
	var file:=FileAccess.open(directory+"/unit-items-assignment-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"observations":observations}));file.close()

func exercise_contained_items(inspector,target: int) -> void:
	await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(124,132))
	var view=inspector.creature_sheet.items_view
	if not check(is_instance_valid(view) and view.rows.size()==15,"Contained Items rows did not reach the view"):return
	var child:=int(view.rows[1].get("related_id",-1))
	check(int(view.fact(view.rows[1],"row_kind",-1))==1 and child>=0,"Contained item target absent")
	check(int(view.fact(view.rows[2],"row_kind",-1))==2 and int(view.rows[2].related_id)==target,"Contained creature target absent")
	check(int(view.rows[3].related_id)==-1,"Unresolved contained row absent")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-contained-scene.png")
	await pointer(view.get_global_transform_with_canvas()*view.inspect_rect(3).get_center())
	check(scene._ui.host.active==inspector and inspector.creature_sheet.tab=="Items","Unresolved contained click navigated")
	for sample in [[1,"unit_inventory_view"],[2,"unit_inventory_creature"]]:
		var motion:=InputEventMouseMotion.new();motion.position=view.get_global_transform_with_canvas()*view.inspect_rect(sample[0]).get_center();root.push_input(motion,true)
		await create_timer(0.65).timeout;await process_frame
		check(inspector.hover_help.visible and inspector.hover_help.displayed==sample[1],"Contained hover missing: "+sample[1])
	await pointer(view.get_global_transform_with_canvas()*view.inspect_rect(1).get_center())
	var item_owner=scene._ui.controller("farm").item_owner
	if not await settle(item_owner.state):return
	check(scene._ui.host.active==item_owner and item_owner.state.item_id==child,"Contained item View selected wrong sheet")
	check(item_owner.state.snapshot.get("carrier",{}).get("id",-1)==target,"Controlled contained item lost its actual carrier")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-items-contained-item-scene.png")
	await pointer(item_owner.panel.get_global_transform_with_canvas()*item_owner.panel.holder_rect().get_center())
	await process_frame;await process_frame
	check(scene._ui.host.active==inspector and inspector.creature_sheet.tab=="Overview","Contained item carrier did not open Overview")
	await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(124,132))
	view=inspector.creature_sheet.items_view
	await pointer(view.get_global_transform_with_canvas()*view.inspect_rect(2).get_center())
	await process_frame;await process_frame
	check(scene._ui.host.active==inspector and int(inspector.selected.get("id",-1))==target and inspector.creature_sheet.tab=="Overview","Contained creature View did not open native Overview")
	var file:=FileAccess.open(directory+"/unit-items-contained-scene-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"unit_id":target,"child_id":child,"unresolved_inert":true,"carrier_return":true,"creature_overview":true}));file.close()

func exercise_owner_refresh(item_owner,item_id: int,carrier_id: int) -> void:
	var observations: Array=[]
	var serial:=0
	for operation in ["other","none","unresolved","restore"]:
		serial+=1
		var file:=FileAccess.open(directory+"/item-owner-request.tmp",FileAccess.WRITE)
		file.store_string(JSON.stringify({"item_id":item_id,"op":operation,"serial":serial}));file.close()
		DirAccess.rename_absolute(directory+"/item-owner-request.tmp",directory+"/item-owner-request.json")
		var deadline:=Time.get_ticks_msec()+5000
		while not FileAccess.file_exists(directory+"/item-owner-ack.json") and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		if not check(FileAccess.file_exists(directory+"/item-owner-ack.json"),"Owner refresh acknowledgement timed out"):return
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/item-owner-ack.json"))
		DirAccess.remove_absolute(directory+"/item-owner-ack.json")
		check(int(expected.serial)==serial and expected.op==operation,"Owner refresh acknowledgement mismatched")
		deadline=Time.get_ticks_msec()+5000
		while item_owner.state.snapshot.get("revision",0)!=int(expected.revision) and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		check(item_owner.state.phase==item_owner.state.Phase.Ready and item_owner.state.snapshot.get("revision",0)==int(expected.revision),"Automatic item refresh missed owner change: "+operation)
		var value: Dictionary=item_owner.state.snapshot
		check(value.get("owner",{}).get("id",-1)==int(expected.owner.id),"Owner refresh identity differs")
		check(value.get("owner",{}).get("name","")==expected.owner.name,"Owner refresh native caption differs")
		check(value.get("carrier",{}).get("id",-1)==carrier_id,"Owner refresh changed carrier")
		check(scene._ui.host.active==item_owner and item_owner.panel.visible,"Owner refresh retired the item panel")
		check(item_owner.panel.snapshot.get("owner",{})==value.get("owner",{}),"Rendered header retained stale ownership")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/item-owner-refresh-"+operation+".png")
		observations.append({"op":operation,"owner":value.get("owner",{}),"revision":str(value.get("revision",0)),"carrier":value.get("carrier",{})})
	var file:=FileAccess.open(directory+"/item-owner-refresh-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"observations":observations},"  "));file.close()

func follow_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if scene._ui.creature_follow.last_position!=null:return true
		await create_timer(0.01).timeout
	return check(false,"Creature follow did not confirm position")

func follow_pixels(inspector,label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/unit-camera-"+label+".png");native.convert(Image.FORMAT_RGB8)
	check(actual.get_region(Rect2i(856,64,32,36)).get_data()==native.get_region(Rect2i(856,64,32,36)).get_data(),"Creature camera artwork differs: "+label)
	actual.save_png(directory+"/unit-follow-scene-"+label+".png")

var follow_serial:=0
func native_follow_change(target: int,operation: String) -> Dictionary:
	follow_serial+=1
	var file:=FileAccess.open(directory+"/unit-follow-request.tmp",FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit_id":target,"op":operation,"serial":follow_serial}));file.close()
	DirAccess.rename_absolute(directory+"/unit-follow-request.tmp",directory+"/unit-follow-request.json")
	var deadline:=Time.get_ticks_msec()+5000
	while not FileAccess.file_exists(directory+"/unit-follow-ack.json") and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	if not check(FileAccess.file_exists(directory+"/unit-follow-ack.json"),"Native follow change timed out"):return {}
	var result: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-follow-ack.json"))
	DirAccess.remove_absolute(directory+"/unit-follow-ack.json")
	check(int(result.serial)==follow_serial and result.op==operation,"Native follow acknowledgement mismatched")
	return result.position

func await_follow_position(tile: Vector3i) -> void:
	var deadline:=Time.get_ticks_msec()+5000
	while scene._ui.creature_follow.last_position!=tile and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	check(scene._ui.creature_follow.last_position==tile,"Composed camera missed native movement")
	await process_frame;await process_frame
	var rig=scene.camera_rig
	var point:=Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5)
	var anchor: Vector2=rig.native_follow_anchor(Vector2(root.size),Vector2.ONE,rig._df_pixels_per_tile)
	check(rig.get_node("Camera3D").unproject_position(point).distance_to(anchor)<0.1,"Moving unit camera anchor differs")

func exercise_follow(inspector,source,source_id: int,target: int) -> void:
	source.open_target(source_id)
	if not await settle(source.state):return
	await pointer(source.panel.get_global_transform_with_canvas()*source.panel.holder_rect().get_center())
	await drain();await process_frame
	check(inspector.panel.visible and is_instance_valid(inspector.follow_button),"Unit camera button absent")
	await follow_pixels(inspector,"before")
	var hover_motion:=InputEventMouseMotion.new();hover_motion.position=Vector2(872,82);root.push_input(hover_motion,true)
	await create_timer(0.65).timeout;await process_frame;await RenderingServer.frame_post_draw
	check(inspector.hover_help.visible and inspector.hover_help.displayed=="unit_camera","Unit camera help absent")
	var help: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-camera-help.json"))
	check(help.lines==preload("res://scripts/native_hover_view.gd").UNIT_HELP.camera,"Unit camera help wording differs")
	var hover_image:=root.get_texture().get_image();hover_image.convert(Image.FORMAT_RGB8)
	var font:=Image.load_from_file(world.ui_font_path())
	for cell in help.cells:
		var ch:=int(cell.ch)
		for y in 12:
			for x in 8:
				var ink:=font.get_pixel(ch%16*8+x,ch/16*12+y)
				if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
				check(hover_image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y).is_equal_approx(preload("res://scripts/native_creature_text.gd").colors[int(cell.color)]),"Unit camera help glyph differs")
	hover_image.save_png(directory+"/unit-camera-help-viewer.png")
	await pointer(inspector.follow_button.get_global_transform_with_canvas()*Vector2(16,18))
	if not await follow_ready():return
	var follow=scene._ui.creature_follow;var rig=scene.camera_rig
	check(follow.unit_id==target,"Camera button followed wrong unit")
	await follow_pixels(inspector,"enabled")
	var tile: Vector3i=follow.last_position
	var point:=Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5)
	for extent in [Vector2i(960,600),Vector2i(1200,800)]:
		root.size=extent;await process_frame;await process_frame;await process_frame
		var scale: Vector2=preload("res://scripts/presentation_settings.gd").effective_scale_vector(Vector2(extent))
		var anchor: Vector2=rig.native_follow_anchor(Vector2(extent),scale,rig._df_pixels_per_tile)
		check(rig.get_node("Camera3D").unproject_position(point).distance_to(anchor)<0.1,"Creature follow resize framing differs")
	await pointer(inspector.follow_button.get_global_transform_with_canvas()*Vector2(16,18))
	check(follow.unit_id==-1,"Second camera click retained follow")
	await pointer(inspector.follow_button.get_global_transform_with_canvas()*Vector2(16,18))
	if not await follow_ready():return
	key(KEY_ESCAPE);await process_frame
	check(not inspector.panel.visible and follow.unit_id==target,"Closing unit sheet lost follow")
	var moved:=await native_follow_change(target,"move")
	check(moved.get("valid",false),"Moved native unit unavailable")
	await await_follow_position(tile+Vector3i(1,-1,0))
	await native_follow_change(target,"restore");await await_follow_position(tile)
	var hidden:=await native_follow_change(target,"hidden")
	check(hidden.get("valid",false),"Native controlled unit hidden-terrain rule changed")
	await create_timer(0.15).timeout;await drain()
	check(follow.unit_id==target,"Hidden terrain incorrectly stopped controlled unit follow")
	await native_follow_change(target,"visible")
	source.open_target(source_id)
	if not await settle(source.state):return
	await pointer(source.panel.get_global_transform_with_canvas()*source.panel.camera_rect().get_center())
	await drain()
	check(follow.unit_id==-1 and scene._ui.item_follow.item_id==source_id,"Item follow did not replace unit follow")
	await pointer(source.panel.get_global_transform_with_canvas()*source.panel.holder_rect().get_center())
	await drain();await process_frame
	await pointer(inspector.follow_button.get_global_transform_with_canvas()*Vector2(16,18))
	if not await follow_ready():return
	check(scene._ui.item_follow.item_id==-1,"Unit follow did not replace item follow")
	key(KEY_ESCAPE);await process_frame
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(200,400);motion.relative=Vector2(16,0);motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion,true);await process_frame
	check(follow.unit_id==-1 and follow.last_position==null,"Manual map pan retained unit follow")
	follow.toggle(target)
	if not await follow_ready():return
	var inactive:=await native_follow_change(target,"inactive")
	check(not inactive.get("valid",true),"Inactive native unit still followable")
	var deadline:=Time.get_ticks_msec()+5000
	while follow.unit_id>=0 and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	check(follow.unit_id==-1 and follow.last_position==null,"Native refusal did not stop composed follow")
	await native_follow_change(target,"active")
	await create_timer(0.15).timeout;await drain()
	check(follow.unit_id==-1,"Restoring unit automatically resumed follow")
	var file:=FileAccess.open(directory+"/unit-follow-scene-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"unit_id":target,"resize":true,"close_preserves":true,"exclusive":true,"pan_stops":true,"native_motion":true,"native_refusal_stops":true,"no_auto_resume":true}));file.close()

func open_customize(inspector) -> bool:
	await pointer(inspector.body.get_global_transform_with_canvas()*Vector2(416,18))
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and not inspector.customize.opened:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(inspector.customize.opened,"Customize did not open from native button")

func exercise_customize(inspector,source_item: int) -> void:
	var hover_motion:=InputEventMouseMotion.new();hover_motion.position=Vector2(840,82);root.push_input(hover_motion,true)
	await create_timer(0.65).timeout
	await process_frame;await RenderingServer.frame_post_draw
	check(inspector.hover_help.visible and inspector.hover_help.displayed=="unit_customize","Customize native hover did not appear")
	var hover_image:=root.get_texture().get_image();hover_image.convert(Image.FORMAT_RGB8)
	var native_help: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-customize-help.json"))
	check(native_help.lines==preload("res://scripts/native_hover_view.gd").UNIT_HELP.customize,"Customize help wording differs")
	var font:=Image.load_from_file(world.ui_font_path())
	var ink_count:=0
	for cell in native_help.cells:
		var ch:=int(cell.ch)
		for y in 12:
			for x in 8:
				var ink:=font.get_pixel(ch%16*8+x,ch/16*12+y)
				if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
				ink_count+=1
				check(hover_image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y).is_equal_approx(preload("res://scripts/native_creature_text.gd").colors[int(cell.color)]),"Customize help glyph differs")
	check(ink_count>0,"Customize native help contains no glyph evidence")
	hover_image.save_png(directory+"/unit-customize-help-viewer.png")
	if not await open_customize(inspector):return
	await process_frame
	check(not inspector.hover_help.visible,"Opening Customize retained obsolete help")
	var editor=inspector.customize
	var original: Dictionary=editor.state.snapshot.duplicate(true)
	if not check(original.nickname.is_empty() and original.profession.is_empty(),"Customize fixture expects empty original custom fields"):return
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(directory+"/unit-customize-scene.png")
	var native:=Image.load_from_file(directory+"/unit-header-actions-open.png");native.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(528,64,288,72)
	check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Composed Customize pixels differ")
	await pointer(Vector2(600,82));check(editor.field==0,"Nickname click lost focus");key(KEY_Q,81)
	check(editor.values[0]=="Q","Nickname key lost input")
	root.size=Vector2i(960,600);await process_frame;await process_frame
	check(editor.opened and editor.field==0 and editor.values[0]=="Q","Resize lost active draft")
	check(inspector.customize_view.size==Vector2(288,72),"Resize changed native editor geometry")
	scene._fortress_hud.toggle_settings()
	key(KEY_Z,90)
	await pointer(inspector.customize_view.get_global_transform_with_canvas()*Vector2(72,54))
	check(editor.opened and editor.field==0 and editor.values[0]=="Q","Overlay allowed hidden editor input")
	key(KEY_ESCAPE);await process_frame
	check(not scene._fortress_hud.settings.visible and editor.opened,"Overlay Escape retired underlying editor")
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	await pointer(Vector2(600,118));check(editor.field==1,"Profession click lost focus");key(KEY_R,82)
	check(editor.values==["Q","R"],"Profession key lost input")
	await drain()
	check(editor.values==["Q","R"] and editor.state.snapshot.nickname=="Q" and editor.state.snapshot.profession=="R","Last clicked field did not receive confirmed edits: "+str(editor.values)+" phase="+str(editor.state.phase)+" results="+str(actions._results))
	key(KEY_ENTER);await process_frame
	check(editor.opened and editor.field==-1,"Enter unexpectedly closed Customize")
	key(KEY_ESCAPE);await process_frame
	check(inspector.panel.visible and not editor.opened and scene._ui.host.active==inspector,"Customize Escape closed unit sheet")
	if not await open_customize(inspector):return
	check(editor.state.snapshot.nickname=="Q" and editor.state.snapshot.profession=="R","Reopened editor lost native names")
	await pointer(Vector2(600,82));key(KEY_X,88)
	var source=scene._ui.controller("farm").item_owner
	source.open_target(source_item)
	check(not editor.opened,"Changing active panel retained unit draft")
	if not await settle(source.state):return
	await pointer(source.panel.get_global_transform_with_canvas()*source.panel.holder_rect().get_center())
	if not await open_customize(inspector):return
	check(editor.state.snapshot.nickname=="QX" and editor.state.snapshot.profession=="R","Panel switch lost queued typing or selected wrong unit")
	await pointer(Vector2(600,82));key(KEY_BACKSPACE);key(KEY_BACKSPACE)
	await pointer(Vector2(600,118));key(KEY_BACKSPACE)
	await drain()
	var restored: bool=editor.state.snapshot==original
	check(restored,"Editor did not restore original semantic snapshot")
	key(KEY_ENTER);key(KEY_ESCAPE);await process_frame
	var file:=FileAccess.open(directory+"/unit-customize-scene-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"last_clicked_field":true,"enter_keeps_customize":true,"escape_keeps_sheet":true,"restored":restored,"native_help_glyph_pixels":ink_count,"resize_retains_draft":true,"overlay_blocks_input":true,"panel_switch_drains_typing":true}));file.close()

func exercise_history(inspector,source,source_id:int,target:int) -> void:
	source.open_target(source_id)
	if not await settle(source.state):return
	await pointer(source.panel.get_global_transform_with_canvas()*source.panel.holder_rect().get_center())
	var deadline:=Time.get_ticks_msec()+5000
	while (not is_instance_valid(inspector.history_button) or not inspector.panel.visible) and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	if not check(is_instance_valid(inspector.history_button),"Unit Reports button missing"):return
	await process_frame;await RenderingServer.frame_post_draw
	var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_reports_navigation_reference
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(Rect2i(792,64,32,36)).get_data())
	check(hash.finish().hex_encode()==reference.button_rgb_sha256,"Unit Reports artwork differs from native")
	var motion:=InputEventMouseMotion.new();motion.position=inspector.history_button.get_global_transform_with_canvas()*Vector2(16,18);root.push_input(motion,true)
	await create_timer(0.6).timeout;await RenderingServer.frame_post_draw
	image=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	check(inspector.hover_help.visible,"Reports hover did not appear")
	var font:=Image.load_from_file(world.ui_font_path())
	var ink_count:=0
	for cell in reference.hover.cells:
		var ch:=int(cell.ch)
		for y in 12:
			for x in 8:
				var ink:=font.get_pixel(ch%16*8+x,ch/16*12+y)
				if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
				ink_count+=1
				check(image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y).is_equal_approx(preload("res://scripts/native_creature_text.gd").colors[int(cell.color)]),"Reports help glyph differs")
	check(ink_count>0,"Reports hover missing native glyph evidence")
	if OS.get_environment("DF3D_UNIT_REPORTS_FROM_EXPEL")=="1":
		await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18));await drain()
		check(inspector.expel.phase==inspector.expel.Phase.Confirming,"Reports fixture did not open Expel")
		check(not inspector.history_button.disabled,"Expel disabled native Reports navigation")
	await pointer(inspector.history_button.get_global_transform_with_canvas()*Vector2(16,18))
	var reports=scene._ui.controller("reports")
	var model=reports.controller.state
	await drain()
	check(scene._ui.host.active==reports and reports.panel.visible and not inspector.panel.visible,"Reports click did not replace unit sheet")
	check(inspector.expel.phase==inspector.expel.Phase.Closed and inspector.expel.snapshot().is_empty(),"Reports retained Expel confirmation authority")
	check(model.direct_unit_entry and model.unit_id==target and model.unit_category==0 and not model.log_initial_needed,"Reports click did not load direct Combat history")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/unit-reports-scene.png")
	for sample in [[Vector2i(960,600),Vector2(680,432),10],[Vector2i(1600,900),Vector2(1320,732),18],[Vector2i(1200,800),Vector2(920,624),15]]:
		root.size=sample[0];await process_frame;await process_frame
		check(model.opened and scene._ui.host.active==reports and reports.panel.size==sample[1] and model.unit_page_rows==sample[2],"Composed Combat resize lost identity or native geometry")
	var populated:=FileAccess.file_exists(directory+"/unit-reports-scene-expected.json")
	if populated:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-reports-scene-expected.json"))
		check(model.rows.size()==22 and model.log_requested==7,"Populated direct history did not load newest native rows")
		for index in model.rows.size():
			check(int(model.rows[index].id)==int(expected.report_ids[index]) and int(model.rows[index].speaker_id)==target,"Combat history row identity/speaker differs")
		var scroll_checks:Array=[]
		for sample in [[Vector2(2,6),6],[Vector2(8,6),6],[Vector2(8,52),0]]:
			model.scroll_to(7);await process_frame
			await pointer(reports.panel.position+reports.panel.scrollbar.position+sample[0])
			check(model.log_requested==sample[1],"Combat arrow/track stepping differs")
			scroll_checks.append(model.log_requested)
		model.scroll_to(7);await process_frame
		var origin:Vector2=reports.panel.position+reports.panel.scrollbar.position
		var drag_motion:=InputEventMouseMotion.new();drag_motion.position=origin+Vector2(8,452);root.push_input(drag_motion,true)
		var drag_press:=InputEventMouseButton.new();drag_press.position=drag_motion.position;drag_press.button_index=MOUSE_BUTTON_LEFT;drag_press.pressed=true;root.push_input(drag_press,true)
		drag_motion=InputEventMouseMotion.new();drag_motion.position=origin+Vector2(8,152);drag_motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(drag_motion,true)
		var drag_release:=InputEventMouseButton.new();drag_release.position=drag_motion.position;drag_release.button_index=MOUSE_BUTTON_LEFT;root.push_input(drag_release,true)
		await process_frame
		check(model.log_requested==1 and not reports.panel.scrollbar.dragging,"Combat drag differs or retained capture")
		scroll_checks.append(model.log_requested)
		var scroll_file=FileAccess.open(directory+"/unit-reports-scroll-scene.json",FileAccess.WRITE)
		scroll_file.store_string(JSON.stringify({"first_rows":scroll_checks,"approved_right_half_correction":true}));scroll_file.close()
		model.scroll_to(7);await process_frame
		await pointer(reports.panel.position+reports.panel.scrollbar.position+Vector2(8,6))
		check(model.log_requested==6,"Combat scrollbar up did not navigate retained rows")
		await pointer(reports.panel.position+Vector2(400,250),MOUSE_BUTTON_WHEEL_UP)
		check(model.log_requested==6,"Combat text wheel moved native-inert log")
		if expected.get("append_enabled",false):await exercise_history_append(reports,target)
	var paused:bool=model.pause_on_new
	await pointer(reports.panel.position+reports.panel.pause_target().get_center())
	check(model.pause_on_new!=paused,"Combat pause toggle did not receive input")
	scene._fortress_hud.toggle_settings()
	await pointer(reports.panel.position+reports.panel.pause_target().get_center())
	check(model.pause_on_new!=paused,"Overlay allowed Combat input")
	key(KEY_ESCAPE);await process_frame
	check(model.opened,"Overlay Escape closed Combat history")
	key(KEY_ESCAPE);await process_frame
	check(not model.opened and scene._ui.host.active==null and not inspector.panel.visible,"Combat Back reopened unit sheet or retained input")
	if populated:
		reports.open_creature_history(target);await drain();await process_frame;await RenderingServer.frame_post_draw
		check(reports.panel.speaker_targets.size()==15,"Combat speaker targets missing")
		await pointer(reports.panel.position+reports.panel.speaker_targets[0].rect.get_center())
		check(not model.opened and scene._ui.host.active==inspector and inspector.selected.get("id",-1)==target,"Combat speaker did not open current creature")
		var ready:=Time.get_ticks_msec()+5000
		while not is_instance_valid(inspector.history_button) and Time.get_ticks_msec()<ready:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		if not check(is_instance_valid(inspector.history_button),"Speaker sheet history button absent"):return
		await pointer(inspector.history_button.get_global_transform_with_canvas()*Vector2(16,18));await drain();await process_frame;await RenderingServer.frame_post_draw
		var tile:Vector3i=model.rows[model.log_first].position
		await pointer(reports.panel.position+reports.panel.report_targets[0].rect.get_center())
		check(not model.opened and scene._ui.host.active==null,"Combat recenter retained a panel")
		check(is_equal_approx(scene.camera_rig.position.x,tile.x+0.5) and is_equal_approx(scene.camera_rig.position.z,tile.y+0.5) and world.get_top_z()==tile.z,"Combat recenter missed stored report position")
	var file:=FileAccess.open(directory+"/unit-reports-scene-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"unit_id":target,"direct_combat":true,"back_to_map":true,"overlay_blocks_input":true,"resize":true,"native_help_glyph_pixels":ink_count,"native_button_pixels":1152,"populated_navigation":populated}));file.close()

func exercise_history_append(reports,target:int) -> void:
	var model=reports.controller.state
	model.scroll_to(7)
	root.size=Vector2i(1600,900);await process_frame;await process_frame
	check(model.log_requested==7 and model.visible_log_rows()==15,"Append fixture did not retain resized first row")
	var deadline:=Time.get_ticks_msec()+5000
	while model.unit_log_length<0 and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	check(model.unit_log_length>=0,"Report source length baseline missing")
	var pauses:Array=[]
	var observe_pause:=func():pauses.append(true)
	model.pause_requested.connect(observe_pause)
	var evidence:Array=[]
	for serial in [1,2,3,4]:
		var pause:bool=serial%2==0
		if model.pause_on_new!=pause:await pointer(reports.panel.position+reports.panel.pause_target().get_center())
		var before:=pauses.size()
		var file:=FileAccess.open(directory+"/unit-report-append-request.tmp",FileAccess.WRITE)
		file.store_string(JSON.stringify({"unit_id":target,"serial":serial}));file.close()
		DirAccess.rename_absolute(directory+"/unit-report-append-request.tmp",directory+"/unit-report-append-request.json")
		deadline=Time.get_ticks_msec()+5000
		while not FileAccess.file_exists(directory+"/unit-report-append-ack.json") and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		if not check(FileAccess.file_exists(directory+"/unit-report-append-ack.json"),"Native append acknowledgement missing; no replay"):break
		var ack:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/unit-report-append-ack.json"));DirAccess.remove_absolute(directory+"/unit-report-append-ack.json")
		deadline=Time.get_ticks_msec()+5000
		while int(model.rows.back().id)!=int(ack.id) and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		check(model.rows.size()==22+serial and int(model.rows.back().id)==int(ack.id),"Live Combat append missing or duplicated")
		check(model.log_requested==maxi(7,4+serial) and model.visible_log_rows()==mini(18,15+serial),"Live append moved above retained native first row")
		check(pauses.size()-before==int(pause),"Pause-on-new emitted wrong number of intents")
		evidence.append({"id":int(ack.id),"rows":model.rows.size(),"first":model.log_requested,"visible":model.visible_log_rows(),"pause_option":pause,"pause_intents":pauses.size()-before})
	model.pause_requested.disconnect(observe_pause)
	root.size=Vector2i(1200,800);await process_frame;await process_frame
	var file:=FileAccess.open(directory+"/unit-reports-append-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"observations":evidence}));file.close()

func exercise_expel_preview(inspector,target:int) -> void:
	var model=inspector.expel
	var live_preview:Dictionary={}
	var deadline:=Time.get_ticks_msec()+5000
	while not is_instance_valid(inspector.expel_button) and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	if not check(is_instance_valid(inspector.expel_button),"Native eligible creature lacks Expel button"):return
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/farm-item-carrier-unit-view.png");native.convert(Image.FORMAT_RGB8)
	check(actual.get_region(Rect2i(856,100,32,36)).get_data()==native.get_region(Rect2i(856,100,32,36)).get_data(),"Expel header artwork differs")
	var motion:=InputEventMouseMotion.new();motion.position=inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18);root.push_input(motion,true)
	await create_timer(0.6).timeout;await RenderingServer.frame_post_draw
	actual=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	check(inspector.hover_help.visible,"Expel hover did not appear")
	var hover:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_expel_view_reference.hover
	var font:=Image.load_from_file(world.ui_font_path());var ink_count:=0
	for cell in hover.cells:
		var ch:=int(cell.ch)
		for y in 12:
			for x in 8:
				var ink:=font.get_pixel(ch%16*8+x,ch/16*12+y)
				if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
				ink_count+=1
				check(actual.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y).is_equal_approx(preload("res://scripts/native_creature_text.gd").colors[int(cell.color)]),"Expel help glyph differs")
	check(ink_count>0,"Expel hover missing native glyph evidence")
	for cancel_button in [true,false]:
		await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18))
		deadline=Time.get_ticks_msec()+5000
		while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		if not check(model.phase==model.Phase.Confirming and model.unit_id==target,"Expel click did not show native affected group"):return
		check(is_instance_valid(inspector.expel_view) and model.snapshot().units[0].id==target,"Expel rendered view missing current group")
		live_preview=model.snapshot()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/unit-expel-scene.png")
		if cancel_button:
			var generation:int=model.generation
			await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18));await drain()
			check(model.generation>generation and model.phase==model.Phase.Confirming,"Repeated Expel did not refresh preview")
			await pointer(inspector.customize_button.get_global_transform_with_canvas()*Vector2(16,18));await drain();await process_frame
			check(inspector.customize.opened and model.phase==model.Phase.Confirming and inspector.expel_view.is_visible_in_tree(),"Expel blocked Customize or lost visible preview")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/unit-expel-customize-scene.png")
			key(KEY_ESCAPE);await process_frame
			check(not inspector.customize.opened and model.phase==model.Phase.Confirming,"Escape did not close Customize before Expel")
		scene._fortress_hud.toggle_settings();await process_frame
		await pointer(inspector.expel_view.get_global_transform_with_canvas()*Vector2(52,inspector.expel_view.size.y-18))
		check(model.phase==model.Phase.Confirming and model.ticket==0,"Settings allowed hidden Expel confirmation")
		key(KEY_ESCAPE);await process_frame
		check(model.phase==model.Phase.Confirming,"Settings Escape closed Expel")
		if cancel_button:await pointer(inspector.expel_view.get_global_transform_with_canvas()*Vector2(inspector.expel_view.size.x-40,inspector.expel_view.size.y-18))
		else:key(KEY_ESCAPE);await process_frame
		check(model.phase==model.Phase.Closed and inspector.is_open() and scene._ui.host.active==inspector,"Expel cancellation did not return to same Overview: button=%s phase=%s open=%s owner=%s" % [cancel_button,model.phase,inspector.is_open(),scene._ui.host.active==inspector])
	if OS.get_environment("DF3D_UNIT_EXPEL_LIFECYCLE")=="1":await exercise_expel_lifecycle(inspector,target,live_preview)
	var file:=FileAccess.open(directory+"/unit-expel-scene-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"unit_id":target,"native_button_pixels":1152,"native_group":true,"native_help_glyph_pixels":ink_count,"overlay_blocks_confirmation":true,"cancel_and_escape_return_overview":true}));file.close()

func exercise_expel_lifecycle(inspector,target:int,preview:Dictionary) -> void:
	# Keep the real scene, inspector, host, assets and native read-only facts.
	# Only Expel receipts are injected; no departure can reach the live bridge.
	var source=preload("res://tests/farm_state_test.gd").World.new()
	var service=preload("res://scripts/semantic_action_service.gd").new();service.configure(source);service.poll()
	var model=inspector.expel;model.configure(service)
	var receipt:=func(outcome):
		var payload:Dictionary={"outcome":outcome}
		if outcome==C.CreatureExpelOutcome.Ready:payload.preview=preview.duplicate(true)
		source.state={"world_epoch":5,"revision":source.calls.size()+1,"request_seq":source.calls.size(),"action":source.calls[-1].request.action,"status":C.ManagementStatus.Ok if outcome in [C.CreatureExpelOutcome.Ready,C.CreatureExpelOutcome.Applied] else C.ManagementStatus.Rejected,"creature_expel":payload}
		service.poll()
	await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18));service.poll()
	check(model.phase==model.Phase.Reading,"Injected pending read did not reach real inspector")
	inspector.close_panel();receipt.call(C.CreatureExpelOutcome.Ready);await process_frame
	check(not inspector.panel.visible and scene._ui.host.active==null and model.phase==model.Phase.Closed,"Late read reopened closed main-scene panel")
	inspector.open_target(Vector3i.ZERO,1,target);await process_frame
	for replacement in [false,true]:
		await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18));service.poll();receipt.call(C.CreatureExpelOutcome.Ready);await process_frame
		check(model.phase==model.Phase.Confirming,"Injected native preview did not render")
		await pointer(Vector2(476,730));service.poll();await process_frame
		check(model.phase==model.Phase.Applying,"Real final button did not queue injected action")
		if replacement:scene._ui.controller("reports").open_creature_history(target);await drain()
		else:key(KEY_ESCAPE);await process_frame
		receipt.call(C.CreatureExpelOutcome.Applied);await process_frame
		check(model.phase==model.Phase.Closed and model.snapshot().is_empty(),"Late departure revived cancelled or replaced inspector")
		if replacement:
			check(scene._ui.host.active==scene._ui.controller("reports") and not inspector.panel.visible,"Late departure stole Reports ownership")
			inspector.open_target(Vector3i.ZERO,1,target);await process_frame
		else:check(scene._ui.host.active==inspector and inspector.panel.visible,"Pending Escape did not preserve Overview")
	await pointer(inspector.expel_button.get_global_transform_with_canvas()*Vector2(16,18));service.poll();receipt.call(C.CreatureExpelOutcome.Ready);await process_frame
	# Rendering-only overflow list, as in the native layout oracle. No confirm.
	var repeated:Array=[]
	for i in 24:repeated.append(preview.units[0].duplicate(true))
	model._preview.units=repeated;model.changed.emit();await process_frame
	inspector.expel_view.first=7;inspector.expel_view.refresh();await process_frame
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(880,400);root.push_input(motion,true)
	var press:=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true);await process_frame
	check(inspector.expel_view.scrollbar.dragging,"Main-scene scrollbar did not capture drag")
	var dragging_view=inspector.expel_view;inspector.redraw();await process_frame
	check(inspector.expel_view==dragging_view and inspector.expel_view.scrollbar.dragging,"Header redraw replaced active Expel drag")
	scene._fortress_hud.toggle_settings();await process_frame
	check(not inspector.expel_view.scrollbar.dragging,"Opening Settings retained Expel drag capture")
	key(KEY_ESCAPE);await process_frame
	motion=InputEventMouseMotion.new();motion.position=Vector2(880,300);root.push_input(motion,true);await process_frame
	check(inspector.expel_view.first==7,"Closing Settings resumed retired drag")
	press.pressed=false;press.position=motion.position;root.push_input(press,true)
	source.state={"world_epoch":5,"revision":0,"status":0,"transport_alive":false};service.poll();await process_frame
	check(model.phase==model.Phase.Unavailable and model.snapshot().is_empty() and inspector.expel_view.get_node_or_null("ConfirmExpel")==null,"Lost Expel connection retained main-scene authority")
	scene._ui.host.reset_local_views();await process_frame
	check(scene._ui.host.active==null and not inspector.panel.visible,"Session reset retained inspector ownership")
	model.configure(actions);service.free();inspector.open_target(Vector3i.ZERO,1,target);await process_frame
	var file:=FileAccess.open(directory+"/unit-expel-lifecycle-scene.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"injected_expel_transport":true,"late_read":true,"pending_cancel":true,"reports_replacement":true,"overlay_retires_drag":true,"disconnect_retires_authority":true,"session_reset_releases_owner":true}));file.close()
