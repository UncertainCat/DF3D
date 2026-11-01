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
	check(inspector.creature_sheet.fact_value(overview_status,"needs_summary_eligible","")==("no" if overview_case=="child" or cannot_learn else "yes"),"Native needs gate differs")
	if overview_case=="squad-alias":check(inspector.creature_sheet.fact_value(overview_status,"squad_text","")=="Native squad alias","Native squad alias differs")
	elif overview_case!="squad":check(inspector.creature_sheet.fact_value(overview_status,"squad_text","")==("" if cannot_learn else "None"),"Native unassigned squad summary differs")
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
	if FileAccess.file_exists(directory+"/unit-customize-captions.json"):
		await exercise_customize(inspector,int(expected.snapshot.id))
	if overview_case=="neutral":await exercise_expel_preview(inspector,target)
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
	exercised=true

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
