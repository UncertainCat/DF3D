extends "res://tests/areas_controller_scene_live.gd"
# Actual fortress scene, viewport-routed location controls and native game readback.
# Raw zone creation/deletion below is fixture setup/cleanup, not workflow acceptance.
var candidate_portrait_audited := false
var details_parent_checked: Dictionary={}
var details_staff_count:=0
var quantity_cases:=0
func pointer_areas() -> void:
	if FileAccess.file_exists(directory+"/naming-restart.txt"):
		await naming_restart();return
	if FileAccess.file_exists(directory+"/naming-disconnect.txt"):
		await seed_catalog()
		for sent in [false,true]:
			await naming_disconnect(sent)
			if stopped:return
		write_json("naming-disconnect-evidence.json",{"queued":"not_sent","sent":"unknown","reconnected_without_replay":true})
		return
	if FileAccess.file_exists(directory+"/quantity-lifecycle.json"):
		await quantity_lifecycle(str(JSON.parse_string(FileAccess.get_file_as_string(directory+"/quantity-lifecycle.json")).mode))
		return
	step = "scene location reference setup"
	await seed_catalog()
	if stopped: return
	await native("paint_counts_location_list")
	if stopped: return
	var list_reference: Array = JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-location-list.json"))
	var existing := await inspect(23,1)
	if stopped: return
	var zones: Button = scene._fortress_hud.navigation.Zones
	zones.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size())
	await click_control(zones,true)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"Zones before existing locations"): return
	editor.use_area(existing)
	await click_control(editor.zone_menu.controls.location)
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"existing location chooser"): return
	# A completed transport reply precedes the container's queued layout pass.
	await capture("existing_locations")
	if stopped: return
	if not check(editor.locations_state.rows.size()==list_reference.size(),"Native location count differs"): return
	for index in list_reference.size():
		var row: Dictionary=editor.locations_state.rows[index]
		var reference: Dictionary=list_reference[index]
		var control: Button=editor.locations_view.choices[index]
		if not check(int(row.id)==int(reference.id) and str(row.name)==str(reference.name),"Native location identity/order/name differs"): return
		if int(row.location_kind)==4:
			if not check(int(row.guild_profession)==int(reference.profession) and int(row.location_tier)==int(reference.tier),"Guild metadata differs"): return
		if not check(control.get_node("Name").text==reference.title and control.get_node("Subtitle").text==reference.subtitle,
			"Location row copy differs from native: %d actual=%s/%s native=%s/%s" % [index,control.get_node("Name").text,control.get_node("Subtitle").text,reference.title,reference.subtitle]): return
	var observed_locations: Array=editor.locations_state.rows.duplicate(true)
	if FileAccess.file_exists(directory+"/religious-staff-scene.txt"):
		await religious_staff_route(observed_locations);return
	if FileAccess.file_exists(directory+"/recognition-scene.txt"):
		await recognition_route(observed_locations);return
	if FileAccess.file_exists(directory+"/naming-scene.txt"):
		await naming_routes(observed_locations)
		return
	editor.close_panel()
	await details_transport(observed_locations)
	if stopped: return
	await details_entry()
	if stopped: return
	await details_access(observed_locations)
	if stopped: return
	await details_routes(observed_locations)
	if stopped:return
	await native("paint_counts_begin")
	if stopped: return
	await native("paint_counts_location_creation")
	if stopped: return
	world.set_top_z(164)
	scene.camera_rig.focus_on(Vector3(171.5,165,58.5),30)
	var references: Array = JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-location-creation.json"))
	for reference in references:
		if reference.get("no_mutation",false): continue
		step = "scene location "+str(reference.scenario)
		var page := await request({"action":10,"kind":1,"zone_type":92,"operation":5,"paint_mode":1,"paint_z":164,
			"spans":[{"y":57,"x":170,"length":3},{"y":58,"x":170,"length":3},{"y":59,"x":170,"length":3}]})
		if stopped: return
		var area: Dictionary = page.areas[0]
		await native("paint_counts_track",{"id":int(area.id),"tiles":9})
		if stopped: return
		var launcher: Button = scene._fortress_hud.navigation.Zones
		launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size())
		await click_control(launcher,true)
		if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"Zones launcher"): return
		editor.use_area(area)
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"location chooser"): return
		var kind := int(reference.kind)
		if kind in [2,4]:
			await native("guard_before")
			await click_control(editor.locations_view.create_buttons[kind-1])
			if not await wait_ui(func(): return settled() and not editor.locations_state.busy() and editor.locations_state.catalog_kind == kind,"catalog before Back"): return
			await pointer_click(Vector2(640,82))
			if not await wait_ui(func(): return settled() and editor.locations_state.catalog_kind == 0,"catalog Back"): return
			await native("guard_after")
			if stopped: return
		await click_control(editor.locations_view.create_buttons[kind-1])
		if kind in [2,4]:
			if not await wait_ui(func(): return settled() and not editor.locations_state.busy() and editor.locations_state.catalog_kind == kind,"creation catalog"): return
			var chosen := -1
			for index in editor.locations_state.catalog_rows.size():
				var row: Dictionary = editor.locations_state.catalog_rows[index]
				if (kind == 4 and int(row.profession) == int(reference.profession)) or (kind == 2 and int(row.kind) == int(reference.practice_kind)+2 and int(row.id) == int(reference.practice_id)):
					chosen = index; break
			if not check(chosen >= 0,"native choice identity absent"): return
			var first := mini(chosen,maxi(0,editor.locations_state.catalog_rows.size()-10))
			for index in first: await pointer_click(Vector2(450,280),MOUSE_BUTTON_WHEEL_DOWN)
			if not check(editor.locations_view.catalog_view.native_scroll.first == first,"scene wheel routed to wrong row"): return
			await capture(str(reference.scenario)+"_choices")
			if stopped: return
			var catalog_view = editor.locations_view.catalog_view
			if not check(catalog_view.scroll.scroll_vertical == first*36 and is_equal_approx(catalog_view.choices[chosen].get_global_rect().position.y,100+36*(chosen-first)),
				"scene row layout disagrees with scroll position: first=%d scroll=%d row=%s" % [first,catalog_view.scroll.scroll_vertical,str(catalog_view.choices[chosen].get_global_rect())]): return
			await pointer_click(Vector2(450,118+36*(chosen-first)))
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) >= 0,"location created"): return
		await assigned_details(editor.selected)
		if stopped: return
		await native("paint_counts_location_compare",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		await capture(str(reference.scenario)+"_created")
		if stopped: return
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"chooser before removal"): return
		var location_id := int(editor.selected.location_id)
		await existing_scroll(true,str(reference.scenario)+"_assigned_scroll")
		if stopped: return
		# Newly created location is the final native list entry. Selecting it
		# again closes the chooser without changing any native state.
		var assigned_view = editor.locations_view
		if not check(int(editor.locations_state.rows[-1].id)==location_id,"created location is not last in native list"): return
		await native("guard_before")
		if stopped: return
		await pointer_click(assigned_view.scroll.global_position+Vector2(72,18+4*36))
		if not await wait_ui(func(): return settled() and editor.stockpile_page=="types" and not editor.locations_view.visible,"current location selection closes chooser"): return
		await native("guard_after")
		if stopped: return
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"chooser after current selection"): return
		await click_control(editor.locations_view.remove)
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) == -1,"location removed"): return
		await native("paint_counts_location_removed",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"chooser before reassignment"): return
		await existing_scroll(false,str(reference.scenario)+"_unassigned_scroll")
		if stopped: return
		var chosen := -1
		for index in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[index].id)==location_id: chosen=index; break
		if not check(chosen>=0,"created location absent from chooser"): return
		var view = editor.locations_view
		var first := mini(chosen,maxi(0,view.choices.size()-6))
		while view.native_scroll.first>first:
			await pointer_click(view.scroll.global_position+Vector2(72,18),MOUSE_BUTTON_WHEEL_UP)
		if not check(chosen>=view.native_scroll.first and chosen<view.native_scroll.first+6,"created location outside visible rows"): return
		await pointer_click(view.scroll.global_position+Vector2(72,18+36*(chosen-first)))
		if not await wait_ui(func(): return settled() and editor.stockpile_page=="types" and int(editor.selected.get("location_id",-1))==location_id,"scrolled row reassigned"): return
		await assigned_details(editor.selected)
		if stopped: return
		await native("paint_counts_location_reassigned",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"chooser before final removal"): return
		await click_control(editor.locations_view.remove)
		if not await wait_ui(func(): return settled() and editor.stockpile_page=="types" and int(editor.selected.get("location_id",-1))==-1,"reassigned location removed"): return
		await native("paint_counts_location_removed",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		editor.close_panel()
		if not await wait_ui(func(): return actions._active == 0 and actions._queue.is_empty(),"scene close drains reads"): return
		area = await inspect(int(area.id),1)
		if stopped: return
		await request({"action":12,"kind":1,"id":int(area.id),"expected_revision":area.revision})
		if stopped: return
		await native("paint_counts_absent",{"id":int(area.id)})
		if stopped: return
	await native("paint_counts_cleanup")
	if not stopped: print("AREAS_LOCATION_SCENE_PASS")

func existing_scroll(assigned: bool, label: String) -> void:
	await capture(label+"_before")
	if stopped: return
	var view = editor.locations_view
	var bar = view.native_scroll
	var page := 5 if assigned else 6
	if not check(bar.visible and bar.page==page and view.scroll.size.y==page*36,"existing location scroll geometry differs"): return
	await native("guard_before")
	if stopped: return
	# Native153010: arrow/wheel move one row; thumb drag clamps to endpoints.
	var point: Vector2=view.scroll.global_position+Vector2(72,18)
	while bar.first>0: await pointer_click(point,MOUSE_BUTTON_WHEEL_UP)
	await pointer_click(point,MOUSE_BUTTON_WHEEL_DOWN)
	if not check(bar.first==1 and view.scroll.scroll_vertical==36,"existing location wheel differs"): return
	await pointer_click(bar.global_position+Vector2(8,6))
	if not check(bar.first==0 and view.scroll.scroll_vertical==0,"existing location up arrow differs"): return
	await pointer_drag(bar.global_position+Vector2(8,18),bar.global_position+Vector2(8,bar.size.y+10))
	var last: int=view.choices.size()-page
	if not check(bar.first==last and not bar.dragging and view.scroll.scroll_vertical==last*36,"existing location drag endpoint differs"): return
	await capture(label)
	if stopped: return
	if not check(is_equal_approx(view.choices[last].global_position.y,view.scroll.global_position.y),"existing location visible row disagrees with thumb"): return
	await native("guard_after")

func details_transport(observed_locations: Array) -> void:
	var identities: Dictionary={}
	for row in observed_locations: identities[int(row.id)]=row
	var originals: Dictionary={}
	for phase in ["baseline","change","restore"]:
		step="location Details transport "+phase
		await native("paint_counts_location_details",{"phase":phase})
		if stopped: return
		var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/location-details-"+phase+".json"))
		for expected in reference.rows:
			if not check(identities.has(int(expected.id)),"Native location absent from observed chooser"): return
			var observed: Dictionary=identities[int(expected.id)]
			if not check(int(observed.site_id)==int(reference.site_id),"Chooser site differs from native owner"): return
			var intent: Dictionary={"action":9,"operation":Contract.AreaOperation.LocationDetails,"kind":1,
				"location_site_id":int(observed.site_id),"location_id":int(observed.id)}
			var result:=await request(intent)
			if stopped: return
			var detail: Dictionary=result.get("location_details",{})
			if not check(int(detail.get("revision",0))>0,"Details receipt absent"): return
			var comparable:=detail.duplicate(true);comparable.erase("revision")
			if not check(JSON.parse_string(JSON.stringify(comparable))==expected,"Details transport differs from native fields"): return
			var repeated:=await request(intent)
			if stopped: return
			if not check(repeated.get("location_details",{})==detail,"Unchanged Details receipt differs"): return
			if phase=="baseline": originals[int(expected.id)]=detail
			elif phase=="restore":
				if not check(detail==originals[int(expected.id)],"Restored Details differs from original snapshot"): return
			elif int(expected.kind)==5 or int(detail.appraisal)!=int(originals[int(expected.id)].appraisal):
				if not check(detail.revision!=originals[int(expected.id)].revision,"Paused native change did not change Details receipt"): return
			else:
				if not check(detail==originals[int(expected.id)],"Unrelated Details snapshot changed"): return
	step="location Details invalid site"
	var seq: int=world.area_request({"action":9,"operation":Contract.AreaOperation.LocationDetails,"kind":1,
		"location_site_id":2147483647,"location_id":0})
	if not check(seq>0,"Details refusal request not sent"): return
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		var result: Dictionary=world.poll_management()
		if int(result.get("request_seq",0))==seq and int(result.get("status",S.Idle)) not in [S.Idle,S.Pending]:
			check(int(result.status)==S.Rejected and not result.get("area",{}).has("location_details") and str(result.get("message",""))=="","Details refusal leaked data or authored copy")
			return
		await create_timer(0.01).timeout
	incomplete("Details refusal wait cap hit; no replay",true)

func staff_candidates_transport(details: Dictionary) -> void:
	var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_selector.json"))
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_metadata.json"))
	var observed_units: Dictionary={}
	for unit in metadata.units:observed_units[int(unit.unit_id)]=unit
	var candidate_state=preload("res://scripts/location_staff_candidates_state.gd").new()
	candidate_state.configure(editor.details_state.service)
	for expected in evidence.selectors:
		if int(expected.location_id)!=int(details.id):continue
		var occupation_id:=-1
		for row in details.staff.rows:
			if int(row.source)==0 and int(row.role)==int(expected.role) and int(row.unit_id)==-1 and int(row.histfig_id)==-1:
				occupation_id=int(row.occupation_id);break
		if not check(occupation_id>=0,"native candidate role lacks empty occupation"):return
		step="staff candidate transport location=%d role=%d"%[int(details.id),int(expected.role)]
		var intent: Dictionary={"action":9,"kind":1,"operation":Contract.AreaOperation.LocationStaffCandidates,
			"location_site_id":int(details.site_id),"location_id":int(details.id),"occupation_id":occupation_id}
		var reply:=await request(intent)
		if stopped:return
		var page: Dictionary=reply.get("location_staff_candidates",{})
		if not check(not page.is_empty(),"candidate page absent"):return
		if not check(int(page.site_id)==int(details.site_id) and int(page.location_id)==int(details.id) and int(page.occupation_id)==occupation_id
			and int(page.role)==int(expected.role) and int(page.cursor)==0 and int(page.next_cursor)==0 and int(page.total)==expected.displayed_ids.size(),"candidate page metadata differs"):return
		var actual_ids: Array=[]
		var actual_scores: Array=[]
		for row in page.rows:
			actual_ids.append(int(row.unit_id));actual_scores.append({"unit_id":int(row.unit_id),"score":int(row.score)})
			if not check(observed_units.has(int(row.unit_id)),"candidate metadata reference absent"):return
			var observed: Dictionary=observed_units[int(row.unit_id)]
			for field in ["name","base_name","profession_name","profession_color","legendary"]:
				if not check(row.get(field)==observed[field],"candidate semantic metadata differs: "+field+" unit="+str(row.unit_id)):return
		if not check(actual_ids.size()==expected.displayed_ids.size(),"candidate native count differs"):return
		for index in actual_ids.size():
			if not check(actual_ids[index]==int(expected.displayed_ids[index]),"candidate native order differs"):return
		if not check(JSON.parse_string(JSON.stringify(actual_scores))==expected.compiled_scores,"candidate native scores differ"):return
		var repeated:=await request(intent)
		if stopped:return
		if not check(repeated.get("location_staff_candidates",{})==page,"unchanged candidates receipt differs"):return
		for variant in 3:
			var invalid:=intent.duplicate()
			if variant==0:invalid.location_site_id=2147483647
			elif variant==1:invalid.occupation_id=2147483647
			else:invalid.expected_list_revision=int(page.revision)
			# Invalid observations clear the retained list. A previously issued receipt
			# must stay stale even when the original target and identical rows return.
			var seq: int=world.area_request(invalid)
			if not check(seq>0,"candidate refusal request not sent"):return
			var deadline:=Time.get_ticks_msec()+30000
			var received:=false
			while Time.get_ticks_msec()<deadline:
				world.poll();var state: Dictionary=world.poll_management()
				if int(state.get("request_seq",0))==seq and int(state.get("status",S.Idle)) not in [S.Idle,S.Pending]:
					if not check(int(state.status)==S.Rejected and not state.get("area",{}).has("location_staff_candidates") and str(state.get("message",""))=="","candidate refusal leaked data or authored copy"):return
					received=true;break
				await create_timer(0.01).timeout
			if not received:incomplete("candidate refusal wait cap; no replay",true);return
		candidate_state.open({"site_id":int(details.site_id),"location_id":int(details.id),"occupation_id":occupation_id,"role":int(expected.role)})
		if not await wait_ui(func():return candidate_state.ticket==0,"staff selector controller read"):return
		if not check(candidate_state.phase==candidate_state.Phase.Ready and candidate_state.rows==page.rows and candidate_state.revision>int(page.revision),"controller did not publish the fresh native list"):return
		var fresh_revision: int=candidate_state.revision
		candidate_state.refresh()
		if not await wait_ui(func():return candidate_state.ticket==0,"staff selector controller refresh"):return
		if not check(candidate_state.phase==candidate_state.Phase.Ready and candidate_state.rows==page.rows and candidate_state.revision==fresh_revision,"controller refresh changed stable native facts"):return
		await staff_candidate_portraits(page)
		if stopped:return
		candidate_state.close()
		if not check(candidate_state.phase==candidate_state.Phase.Closed and candidate_state.rows.is_empty(),"closed selector retained selectable rows"):return
		print("STAFF_CANDIDATE_TRANSPORT_PASS location=",details.id," role=",expected.role," rows=",actual_ids.size()," controller=true metadata=true")

func image_digest(source: Image, clear_transparent := true) -> String:
	var image := source.duplicate() as Image
	image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
	var pixels := image.get_data()
	if clear_transparent:
		for pixel in range(0,pixels.size(),4):
			if pixels[pixel+3]==0:pixels[pixel]=0;pixels[pixel+1]=0;pixels[pixel+2]=0
	var hasher:=HashingContext.new();hasher.start(HashingContext.HASH_SHA256);hasher.update(pixels)
	return hasher.finish().hex_encode()

func staff_candidate_portraits(page: Dictionary) -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_portraits.json"))
	if not candidate_portrait_audited:
		var mismatches: Array=[]
		var pending: Array=reference.unit_images.keys()
		var deadline:=Time.get_ticks_msec()+90000
		while not pending.is_empty() and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll();editor._process(0.02)
			for key in pending.duplicate():
				var id:=int(key)
				var texture: Texture2D=world.selection_icon(1,id,true)
				if texture==null:continue
				var icon: Image=texture.get_image()
				if not check(icon.save_png(directory+"/candidate_unit_%d.png"%id)==OK,"candidate audit capture failed"):return
				if icon.get_size()!=Vector2i(32,32) or image_digest(icon)!=reference.unit_images[key].visible_rgba_sha256:mismatches.append(id)
				pending.erase(key)
			if not pending.is_empty():await create_timer(0.02).timeout
		write_json("candidate-portrait-audit.json",{"total":reference.unit_images.size(),"mismatches":mismatches,"unavailable":pending})
		if not mismatches.is_empty() or not pending.is_empty():
			var diagnostic_ids:=PackedInt64Array()
			var diagnostic_rows: Array=[]
			for key in reference.unit_images:
				var id:=int(key)
				if not mismatches.has(id) and not pending.has(key):continue
				diagnostic_ids.append(id)
				diagnostic_rows.append({"id":id,"species":world.unit_species(id),"tile":str(world.unit_tile(id))})
			write_json("candidate-portrait-model.json",diagnostic_rows)
			world.dump_unit_composites(directory+"/candidate-composites",diagnostic_ids,diagnostic_ids.size())
		print("STAFF_CANDIDATE_PORTRAIT_AUDIT total=",reference.unit_images.size()," mismatches=",mismatches," unavailable=",pending)
		if not check(mismatches.is_empty() and pending.is_empty(),"candidate native sprite audit failed; see candidate-portrait-audit.json"):return
		candidate_portrait_audited=true
	var expected: Dictionary={}
	for sample in reference.cases:
		if int(sample.location_id)==int(page.location_id) and int(sample.role)==int(page.role):expected=sample;break
	if not check(not expected.is_empty(),"candidate portrait case missing"):return
	var picture=preload("res://scripts/native_unit_picture_frame.gd").new();picture.configure(world)
	var backgrounds: Dictionary={}
	for item in reference.art:
		var texture: Texture2D=picture.texture(item.token=="BUTTON_PICTURE_BOX_SELECTED")
		if not check(texture!=null,"candidate picture frame unavailable"):return
		var region:=texture.get_image().get_region(Rect2i(int(item.x)*8,int(item.y)*12,8,12))
		if not check(image_digest(region,false)==item.rgba_sha256,"candidate picture frame differs from native pixels: "+str(item.token)+" cell="+str(Vector2i(int(item.x),int(item.y)))):return
		backgrounds[item.token]=texture.get_image()
	var layer:=CanvasLayer.new();layer.layer=129;root.add_child(layer)
	var view=preload("res://scripts/location_staff_candidates_view.gd").new();layer.add_child(view)
	view.configure(world);view.layout(Vector2(1200,800));view.display_rows(page.rows)
	var ready:=await wait_ui(func():
		view.update_icons()
		return view.unit_icons.size()==16,"candidate portraits")
	if not ready:layer.queue_free();return
	for frame in 2:await process_frame;await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	for index in 16:
		var id:=int(page.rows[index].unit_id)
		if not check(id==int(expected.unit_ids[index]),"candidate portrait native order differs"):layer.queue_free();return
		var icon: Image=view.unit_icons[id].get_image()
		if not check(icon.save_png(directory+"/candidate_unit_%d.png"%id)==OK,"candidate icon capture failed"):layer.queue_free();return
		if not check(icon.get_size()==Vector2i(32,32) and image_digest(icon)==reference.unit_images[str(id)].visible_rgba_sha256,"candidate native sprite differs unit="+str(id)):layer.queue_free();return
		var background: Image=backgrounds["BUTTON_PICTURE_BOX_SELECTED" if index==0 else "BUTTON_PICTURE_BOX_DARK"]
		for y in 36:
			for x in 40:
				var source_x:=x if x<8 else 16+x%8 if x>=32 else 8+x%8
				var native_pixel:=background.get_pixel(source_x,y)
				if x>=2 and x<34 and y>=2 and y<34:
					var sprite_pixel:=icon.get_pixel(x-2,y-2)
					native_pixel=native_pixel.blend(sprite_pixel)
				if native_pixel.a<0.99:continue
				var actual:=rendered.get_pixel(376+x,88+index*36+y)
				if not check(absf(actual.r-native_pixel.r)+absf(actual.g-native_pixel.g)+absf(actual.b-native_pixel.b)<0.035,"candidate composed portrait position/pixels differ unit="+str(id)+" pixel="+str(Vector2i(x,y))):layer.queue_free();return
	if not check(rendered.save_png(directory+"/candidate_rows_%d_%d.png"%[int(page.location_id),int(page.role)])==OK,"candidate row capture failed"):layer.queue_free();return
	if int(page.location_id)==0 and int(page.role)==1:
		if not check(await preload("res://tests/location_staff_candidates_input_helpers.gd").replay(self,view,page.rows),"native selector discrete input differs"):layer.queue_free();return
		print("STAFF_CANDIDATE_INPUT_PASS")
	if not check(await preload("res://tests/location_staff_candidates_input_helpers.gd").replay_headers(self,view,page.rows,int(page.location_id),int(page.role)),"native candidate header sorting differs"):layer.queue_free();return
	print("STAFF_CANDIDATE_HEADERS_PASS location=",page.location_id," role=",page.role)
	if int(page.location_id)==1 and int(page.role)==0:
		if not check(await preload("res://tests/location_staff_candidates_input_helpers.gd").replay_filter_keys(self,view,page.rows),"native candidate filtering differs"):layer.queue_free();return
		print("STAFF_CANDIDATE_FILTER_KEYS_PASS")
		if not check(await preload("res://tests/location_staff_candidates_input_helpers.gd").replay_filter_input(self,view,page.rows),"native candidate filter input differs"):layer.queue_free();return
		print("STAFF_CANDIDATE_FILTER_INPUT_PASS")
		if not check(await preload("res://tests/location_staff_candidates_input_helpers.gd").replay_filter_navigation(self,view,page.rows),"native candidate filter focus/navigation differs"):layer.queue_free();return
		print("STAFF_CANDIDATE_FILTER_NAVIGATION_PASS")
	view.display_rows([])
	if not check(view.unit_icons.is_empty(),"closed candidate selector retained portraits"):layer.queue_free();return
	layer.queue_free();await process_frame
	print("STAFF_CANDIDATE_PORTRAITS_PASS location=",page.location_id," role=",page.role," rows=16")

func assigned_details(area: Dictionary, edit_staff: bool = false) -> void:
	if not check(int(area.get("location_site_id",-1))>=0,"Assigned zone missing observed location site"): return
	var result:=await request({"action":9,"operation":Contract.AreaOperation.LocationDetails,"kind":1,
		"location_site_id":int(area.location_site_id),"location_id":int(area.location_id)})
	if stopped: return
	var details: Dictionary=result.get("location_details",{})
	check(int(details.get("site_id",-1))==int(area.location_site_id) and int(details.get("id",-1))==int(area.location_id)
		and int(area.id) in details.get("zone_ids",[]),"Assigned Details identity or membership differs")
	if stopped:return
	await click_control(editor.zone_menu.controls.location_details)
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and editor.details_layer.visible,"assigned zone Details route"):return
	if not check(editor.details_origin=="zone" and int(editor.details_state.snapshot.id)==int(area.location_id)
		and int(editor.details_state.snapshot.site_id)==int(area.location_site_id) and not editor.locations_view.visible,"assigned route identity or parent differs"):return
	await details_parent_input()
	if stopped:return
	if edit_staff:
		await staff_route_edits()
		if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.details_layer.visible,"assigned Details Back"):return
	check(editor.panel.visible and editor.stockpile_page=="types" and int(editor.selected.location_id)==int(area.location_id),"assigned Back lost zone parent")

func naming_routes(locations: Array) -> void:
	var cases:=0
	for index in locations.size():
		var id:=int(locations[index].id)
		step="scene naming location %d"%id
		await click_control(editor.locations_view.choices[index].get_node("Details"))
		if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready,"naming Details entry"):return
		var details=editor.details_view
		await click_control(details.rename_button)
		var names=details.name_workflow.names
		if not await wait_ui(func():return names.phase==names.Phase.Ready,"complete native naming choices"):return
		if not check(details.name_view.visible and not details.heading.visible and names.snapshot.id==id,"naming target/visibility"):return
		if id==1:
			await naming_long_header(details,id)
			if stopped:return
			await naming_resize(details,id)
			if stopped:return
		await native("name_choices",{"location_id":id,"component":0,"query":"","choices":names.rows})
		await capture("naming_%d"%id)
		for mode in [1,0,2,3]:
			await native("name_guard",{"location_id":id})
			if stopped:return
			var chosen: Dictionary=names.rows[0].duplicate(true)
			await pointer_click({1:Vector2(744,178),0:Vector2(668,142),2:Vector2(608,358),3:Vector2(832,82)}[mode])
			if not await wait_ui(func():return names.phase==names.Phase.Ready and names.ticket==0,"naming mutation receipt and choices"):return
			var value: Dictionary=names.snapshot.value.duplicate(true)
			value.first_name_bytes=Array(value.first_name_bytes);value.nickname_bytes=Array(value.nickname_bytes)
			if mode in [0,1]:
				await native("name_edit_check",{"location_id":id,"mode":mode,"target":0,"word":chosen.word,"part":chosen.part,"value":value})
			else:
				await native("name_random_check",{"location_id":id,"mode":mode,"target":6,"displayed":0,"value":value})
			await native("name_headers",{"location_id":id,"native_header":names.snapshot.native_header,"english_header":names.snapshot.english_header})
			if stopped:return
		await pointer_click(Vector2(912,82))
		if not await wait_ui(func():return not details.name_workflow.active and editor.details_state.phase==editor.details_state.Phase.Ready,"Details refreshed after naming"):return
		await native("name_details",{"location_id":id,"name":editor.details_state.snapshot.name})
		var final_name: String=editor.details_state.snapshot.name
		await click_control(details.rename_button)
		if not await wait_ui(func():return names.phase==names.Phase.Ready,"reopened naming"):return
		await pointer_key(KEY_ESCAPE)
		if not check(not details.name_workflow.active and editor.details_origin=="chooser","Escape must return to Details"):return
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not await wait_ui(func():return editor.details_origin.is_empty() and editor.locations_view.visible and not editor.locations_state.busy(),"naming Details Back"):return
		if not check(editor.locations_state.rows[index].name==final_name,"chooser retained old location name"):return
		cases+=1
	for sent in [false,true]:
		await naming_close_pending(sent)
		if stopped:return
	await naming_assigned_routes(locations)
	if stopped:return
	write_json("naming-scene-evidence.json",{"locations":cases,"mutations":cases*5+4,"resize_cases":3,"pending_close_cases":2,"assigned_routes":cases,"scope":"chooser and assigned quill entry, resized selection/focus and compact parent visibility, full choices, four edit modes and native readback, Done refresh, reopen/Escape/Back, queued cancellation and sent late receipt after dismissal"})
	print("LOCATION_NAMING_SCENE_PASS locations=",cases)
	editor.close_panel()

func naming_long_header(details, id: int) -> void:
	step="main naming long header"
	await pointer_click(Vector2(912,82))
	if not await wait_ui(func():return not details.name_workflow.active and editor.details_state.phase==editor.details_state.Phase.Ready,"before long-name fixture"):return
	await native("name_long_fixture",{"location_id":id})
	await click_control(details.rename_button)
	var names=details.name_workflow.names
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"long-name observation"):return
	await native("name_headers",{"location_id":id,"native_header":names.snapshot.native_header,"english_header":names.snapshot.english_header})
	await capture("naming_long_header")
	var header_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_name_editor.json")).long_header_reference
	var image:=root.get_texture().get_image()
	var mask:=PackedByteArray();mask.resize(1200*24)
	for y in 24:
		for x in 1200:
			var color:=image.get_pixel(x,y+88)
			mask[y*1200+x]=1 if color==Color8(255,225,17) else 2 if color==Color8(18,254,207) else 0
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(mask)
	var glyphs_match: bool=hash.finish().hex_encode()==header_reference.main_glyph_mask_sha256
	var icon:=image.get_region(Rect2i(40,100,32,36));icon.convert(Image.FORMAT_RGB8)
	hash.start(HashingContext.HASH_SHA256);hash.update(icon.get_data())
	var icon_matches: bool=hash.finish().hex_encode()==header_reference.selected_zone_icon_rgb_sha256
	write_json("naming-long-header-evidence.json",{"native_header":names.snapshot.native_header,"english_header":names.snapshot.english_header})
	await native("name_long_restore",{"location_id":id})
	if not check(glyphs_match,"native long header including zone icon and right HUD overdraw"):return
	if not check(icon_matches,"native selected-zone icon size and composition"):return
	await pointer_click(Vector2(912,82))
	if not await wait_ui(func():return not details.name_workflow.active and editor.details_state.phase==editor.details_state.Phase.Ready,"after long-name restoration"):return
	await click_control(details.rename_button)
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"restored naming observation"):return

func naming_resize(details, id: int) -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_name_editor.json")).resize_reference
	var names=details.name_workflow.names
	var observations: Array=[]
	for sample in reference.cases:
		step="main naming resize "+sample.name
		root.size=Vector2i(sample.viewport[0],sample.viewport[1]);scene._fortress_hud.apply_ui_scale()
		for frame in 8:editor._process(0);await process_frame
		var rect:=screen_rect(details.name_view)
		var expected:=Rect2(sample.rect[0],sample.rect[1],sample.rect[2],sample.rect[3])
		if not check(rect==expected and details.name_view.page==int(sample.page),"main naming native resize geometry: "+str(rect)):return
		if not check(editor.panel.modulate.a==(0.0 if sample.name=="small" else 1.0),"native compact parent visibility"):return
		await capture("naming_resize_"+sample.name)
		var target:=int(sample.page)-1
		var choice: Dictionary=names.rows[target].duplicate(true)
		await native("name_guard",{"location_id":id})
		await pointer_click(rect.position+Vector2(380,120+target*36))
		if not await wait_ui(func():return names.phase==names.Phase.Ready and names.ticket==0,"resized last-row selection"):return
		var value: Dictionary=names.snapshot.value.duplicate(true)
		value.first_name_bytes=Array(value.first_name_bytes);value.nickname_bytes=Array(value.nickname_bytes)
		await native("name_edit_check",{"location_id":id,"mode":1,"target":0,"word":choice.word,"part":choice.part,"value":value})
		if stopped:return
		await pointer_click(rect.position+Vector2(rect.size.x-48,90))
		if not check(details.name_view.entering_filter,"resized filter hitbox"):return
		await pointer_key(KEY_ENTER)
		if not check(not details.name_view.entering_filter,"resized filter Enter"):return
		if sample.name=="small":
			await pointer_click(rect.position+Vector2(rect.size.x-64,30))
			if not await wait_ui(func():return not details.name_workflow.active and editor.details_state.phase==editor.details_state.Phase.Ready,"compact naming Done"):return
			editor._process(0);await process_frame
			if not check(editor.panel.modulate.a==1.0,"parent must return after compact naming Done"):return
			root.size=Vector2i(1200,800);scene._fortress_hud.apply_ui_scale()
			for frame in 8:editor._process(0);await process_frame
			await click_control(details.rename_button)
			if not await wait_ui(func():return names.phase==names.Phase.Ready,"naming after compact Done"):return
		observations.append({"viewport":sample.viewport,"rect":sample.rect,"page":sample.page,"selected_word":choice.word,"selected_part":choice.part})
	write_json("naming-resize-evidence.json",{"cases":observations,"native_selection_effects":3,"scope":"actual fortress composition, native frame geometry, resized last-row selection and filter focus; Details and HUD overlap parity remain separate"})

func naming_restart() -> void:
	step="naming producer restart"
	await seed_catalog();await quantity_lifecycle_open()
	if stopped:return
	var details=editor.details_view
	await click_control(details.rename_button)
	var names=details.name_workflow.names
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"restart naming choices"):return
	var original: Dictionary=names.snapshot.value.duplicate(true)
	var id: int=names.snapshot.id
	await pointer_click(Vector2(744,178))
	var ticket: int=names.ticket
	await pointer_click(Vector2(832,82))
	if not check(ticket>0 and names.queue.size()==1,"restart requires naming edit plus dependent Random"):return
	var applied:=await quantity_unobserved(ticket)
	if stopped:return
	if not check(applied.area.location_name.value!=original,"restart naming Select must change native name"):return
	await quantity_restart(ticket,"naming")
	if stopped:return
	if not check(not details.name_workflow.active and names.identity.is_empty() and names.snapshot.is_empty() and names.queue.is_empty() and names.ticket==0,"restart retained naming authority"):return
	var native_value:=original.duplicate(true)
	native_value.first_name_bytes=Array(native_value.first_name_bytes);native_value.nickname_bytes=Array(native_value.nickname_bytes)
	await native("name_read",{"location_id":id,"value":native_value})
	await quantity_lifecycle_open()
	if stopped:return
	await click_control(details.rename_button)
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"fresh naming after producer replacement"):return
	if not check(names.snapshot.value==original and names.queue.is_empty(),"replacement naming reused unsaved edit"):return
	editor.close_panel()
	print("LOCATION_NAMING_RESTART_PASS")

func naming_disconnect(sent: bool) -> void:
	step="naming disconnect sent="+str(sent)
	await quantity_lifecycle_open()
	if stopped:return
	var details=editor.details_view
	await click_control(details.rename_button)
	var names=details.name_workflow.names
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"disconnect naming choices"):return
	var id: int=names.snapshot.id
	await native("name_guard",{"location_id":id})
	var expected: Dictionary=names.snapshot.value.duplicate(true)
	await pointer_click(Vector2(744,178))
	var ticket: int=names.ticket
	if not check(ticket>0 and names.phase==names.Phase.Editing,"disconnect naming edit missing"):return
	await pointer_click(Vector2(832,82))
	if not check(names.queue.size()==1,"disconnect naming dependent Random missing"):return
	if sent:
		var reply:=await quantity_unobserved(ticket)
		if stopped:return
		expected=reply.area.location_name.value.duplicate(true)
	world.detach_live();actions.poll()
	var outcome: Dictionary=actions.result(ticket)
	write_json("naming-disconnect-%s.json"%str(sent),outcome)
	if not check(outcome.get("outcome")==("unknown" if sent else "not_sent"),"naming disconnect outcome differs"):return
	if not check(not details.name_workflow.active and names.identity.is_empty() and names.snapshot.is_empty() and names.queue.is_empty() and names.ticket==0 and not editor.details_layer.visible,"disconnect retained naming authority"):return
	if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active==0,"disconnected naming remains dispatchable"):return
	if not sent:await native("name_unchanged",{"location_id":id})
	if not check(world.attach(),"naming reconnect failed"):return
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll();editor._process(0.02)
		if world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)):break
		await create_timer(0.02).timeout
	if not check(bool(world.poll_management().get("transport_alive",false)),"naming reconnect timeout"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();editor._process(0.02);await process_frame
	if not check(actions._next_ticket==next_ticket and names.identity.is_empty() and not details.name_workflow.active and not editor.details_layer.visible,"reconnect replayed or reopened naming"):return
	var native_value: Dictionary=expected.duplicate(true)
	native_value.first_name_bytes=Array(native_value.first_name_bytes);native_value.nickname_bytes=Array(native_value.nickname_bytes)
	await native("name_read",{"location_id":id,"value":native_value})
	await native("name_rng_unchanged",{"location_id":id})
	await quantity_lifecycle_open()
	if stopped:return
	await click_control(details.rename_button)
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"fresh naming after reconnect"):return
	if not check(names.snapshot.value==expected and names.queue.is_empty(),"reopened naming reused stale state"):return
	editor.close_panel()
	print("LOCATION_NAMING_DISCONNECT_PASS sent=",sent)

func naming_close_pending(sent: bool) -> void:
	step="naming pending close sent="+str(sent)
	await click_control(editor.locations_view.choices[0].get_node("Details"))
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready,"pending naming Details"):return
	var details=editor.details_view
	await click_control(details.rename_button)
	var names=details.name_workflow.names
	if not await wait_ui(func():return names.phase==names.Phase.Ready,"pending naming choices"):return
	var id: int=names.snapshot.id
	var chosen: Dictionary=names.rows[0].duplicate(true)
	await native("name_guard",{"location_id":id})
	await pointer_click(Vector2(744,178))
	var ticket: int=names.ticket
	if not check(ticket>0 and names.phase==names.Phase.Editing,"pending naming mutation missing"):return
	var observed: Dictionary={}
	if sent:
		var reply:=await quantity_unobserved(ticket)
		if stopped:return
		observed=reply.area.location_name.value.duplicate(true)
		observed.first_name_bytes=Array(observed.first_name_bytes);observed.nickname_bytes=Array(observed.nickname_bytes)
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not check(not details.name_workflow.active and not details.name_view.is_visible_in_tree(),"pending naming Back retained editor"):return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy() and settled(),"pending naming parent retired"):return
	if not check(not details.name_workflow.active and names.snapshot.is_empty() and names.ticket==0 and editor.details_state.snapshot.is_empty(),"late naming reply revived retired state"):return
	if sent:
		await native("name_edit_check",{"location_id":id,"mode":1,"target":0,"word":chosen.word,"part":chosen.part,"value":observed})
		await native("name_details",{"location_id":id,"name":editor.locations_state.rows[0].name})
	else:
		if not check(actions.result(ticket).get("outcome")=="not_sent","queued naming edit was sent on cancellation"):return
		await native("name_unchanged",{"location_id":id})
	if stopped:return
	await click_control(editor.locations_view.choices[1].get_node("Details"))
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready,"new Details target after pending naming"):return
	if not check(editor.details_state.snapshot.id!=id and not details.name_workflow.active,"new target inherited naming state"):return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)

func naming_assigned_routes(locations: Array) -> void:
	var original_id:=int(editor.selected.location_id)
	for index in locations.size():
		var id:=int(locations[index].id)
		step="assigned naming location %d"%id
		await quantity_scroll_location(index)
		await click_control(editor.locations_view.choices[index])
		if not await wait_ui(func():return settled() and not editor.locations_view.visible and int(editor.selected.get("location_id",-1))==id,"assigned naming zone"):return
		await click_control(editor.zone_menu.controls.location_details)
		if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready,"assigned naming Details"):return
		if not check(editor.details_origin=="zone" and editor.details_state.snapshot.id==id,"assigned naming target"):return
		var details=editor.details_view
		await click_control(details.rename_button)
		var names=details.name_workflow.names
		if not await wait_ui(func():return names.phase==names.Phase.Ready,"assigned naming choices"):return
		await native("name_guard",{"location_id":id})
		var chosen: Dictionary=names.rows[0].duplicate(true)
		await pointer_click(Vector2(744,178))
		if not await wait_ui(func():return names.phase==names.Phase.Ready and names.ticket==0,"assigned naming edit"):return
		var value: Dictionary=names.snapshot.value.duplicate(true)
		value.first_name_bytes=Array(value.first_name_bytes);value.nickname_bytes=Array(value.nickname_bytes)
		await native("name_edit_check",{"location_id":id,"mode":1,"target":0,"word":chosen.word,"part":chosen.part,"value":value})
		await pointer_click(Vector2(912,82))
		if not await wait_ui(func():return not details.name_workflow.active and editor.details_state.phase==editor.details_state.Phase.Ready,"assigned naming refresh"):return
		await native("name_details",{"location_id":id,"name":editor.details_state.snapshot.name})
		if stopped:return
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not check(editor.details_origin.is_empty() and editor.stockpile_page=="types","assigned naming Back"):return
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func():return settled() and not editor.locations_state.busy() and editor.locations_view.visible,"chooser after assigned naming"):return
	if original_id<0:await click_control(editor.locations_view.remove)
	else:
		var index:=-1
		for i in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[i].id)==original_id:index=i;break
		if not check(index>=0,"original naming assignment missing"):return
		await quantity_scroll_location(index)
		await click_control(editor.locations_view.choices[index])
	if not await wait_ui(func():return settled() and int(editor.selected.get("location_id",-1))==original_id,"restore naming assignment"):return
	var restored:=await inspect(int(editor.selected.id),1)
	check(int(restored.location_id)==original_id,"native naming assignment not restored")

func details_routes(locations: Array) -> void:
	step="fortress Details entry routes"
	editor.close_panel()
	var zones: Button=scene._fortress_hud.navigation.Zones
	zones.show();scene._fortress_hud.layout(scene._fortress_hud.logical_view_size())
	await click_control(zones,true)
	if not await wait_ui(func():return editor.panel.visible and editor.available and settled(),"Zones for Details routes"):return
	var area:=await inspect(23,1)
	if stopped:return
	editor.use_area(area)
	await click_control(editor.zone_menu.controls.location)
	if not await wait_ui(func():return settled() and not editor.locations_state.busy(),"Details route chooser"):return
	for index in locations.size():
		var row: Dictionary=editor.locations_state.rows[index]
		var scroll_before: int=editor.locations_view.native_scroll.first
		await click_control(editor.locations_view.choices[index].get_node("Details"))
		if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and editor.details_layer.visible,"chooser Details route"):return
		if not check(editor.details_origin=="chooser" and int(editor.details_state.snapshot.id)==int(row.id)
			and int(editor.details_state.snapshot.site_id)==int(row.site_id) and not editor.locations_view.visible,"chooser route identity or parent differs"):return
		await details_parent_input()
		if stopped:return
		await staff_route_edits()
		if stopped:return
		await quantity_route_edits()
		if stopped:return
		await capture("details_route_%d"%int(row.id))
		var closing_quantity:=await quantity_prepare_close()
		# Native window Escape from tavern numeric entry returns to the chooser
		# and retains the typed value, just like right-click Details dismissal.
		if int(row.id)==1:await pointer_key(KEY_ESCAPE)
		else:await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not closing_quantity.is_empty():
			if not check(editor.details_closing and not editor.details_layer.visible,"pending quantity dismissal must hide without cancelling"):return
			if not await wait_ui(func():return not editor.details_closing,"quantity drain after dismissal"):return
			await native("quantity_check",{"location_id":int(row.id),"quantity_id":closing_quantity.quantity,"value":closing_quantity.expected})
			await native("quantity_seed",{"location_id":int(row.id),"quantity_id":closing_quantity.quantity,"value":closing_quantity.original})
			if stopped:return
		if not await wait_ui(func():return editor.details_origin.is_empty() and editor.locations_view.visible,"chooser Details Back"):return
		if not check(editor.locations_view.native_scroll.first==scroll_before and editor.details_state.snapshot.is_empty(),"Back reset chooser scroll or retained Details"):return
		if int(row.id)==1:print("LOCATION_QUANTITY_ESCAPE_PASS pending_value_retained=true chooser_visible=true")
		var after:=await inspect(23,1)
		if not check(int(after.location_id)==int(area.location_id) and int(after.location_site_id)==int(area.location_site_id),"Details navigation assigned the zone"):return
	if not check(details_staff_count==10,"full route ordinary staff matrix incomplete"):return
	if not check(quantity_cases==13,"full route quantity matrix incomplete"):return
	print("LOCATION_QUANTITY_SCENE_PASS cases=",quantity_cases)
	# Exercise the same native ordinary-role matrix through an actually assigned
	# zone. Assign through the chooser, inspect the resulting membership, then
	# enter using the assigned zone's Details control, not a direct Details call.
	for row in locations:
		var index: int=-1
		for i in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[i].id)==int(row.id):index=i;break
		if not check(index>=0,"assigned staff route location absent from chooser"):return
		await quantity_scroll_location(index)
		if stopped:return
		await click_control(editor.locations_view.choices[index])
		if not await wait_ui(func():return settled() and not editor.locations_view.visible and int(editor.selected.get("location_id",-1))==int(row.id),"assign staff route location"):return
		var assigned:=await inspect(int(area.id),1)
		if stopped:return
		if not check(int(assigned.location_id)==int(row.id),"staff route assignment not present in native zone"):return
		await assigned_details(assigned,true)
		if stopped:return
		await click_control(editor.zone_menu.controls.location)
		if not await wait_ui(func():return settled() and not editor.locations_state.busy() and editor.locations_view.visible,"chooser after assigned staff route"):return
	# Restore the original zone membership through the same user-facing controls.
	if int(area.location_id)<0:
		await click_control(editor.locations_view.remove)
	else:
		var original_index: int=-1
		for i in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[i].id)==int(area.location_id):original_index=i;break
		if not check(original_index>=0,"original location missing before restoration"):return
		await quantity_scroll_location(original_index)
		if stopped:return
		await click_control(editor.locations_view.choices[original_index])
	if not await wait_ui(func():return settled() and not editor.locations_view.visible and int(editor.selected.get("location_id",-1))==int(area.location_id),"restore staff route membership"):return
	var restored:=await inspect(int(area.id),1)
	if stopped:return
	if not check(int(restored.location_id)==int(area.location_id) and int(restored.location_site_id)==int(area.location_site_id),"assigned staff route changed original membership"):return
	editor.close_panel()
	if not check(details_staff_count==20,"assigned route ordinary staff matrix incomplete"):return
	if not stopped:print("LOCATION_DETAILS_ROUTES_PASS chooser=",locations.size()," assigned=",locations.size()," staff=",details_staff_count)

func details_parent_input() -> void:
	var route: String=editor.details_origin
	if details_parent_checked.has(route):return
	var original: Dictionary=editor.selected.duplicate(true)
	var details: Dictionary=editor.details_state.snapshot.duplicate(true)
	var page: String=editor.stockpile_page
	await native("guard_before")
	if stopped:return
	var count:=receipts.size()
	var clicked: Array=[]
	for key in ["location","location_details","owner","rename","repaint","suspend"]:
		var control: Control=editor.zone_menu.controls[key]
		if not control.is_visible_in_tree():continue
		await click_control(control);clicked.append(key)
		if not check(editor.details_origin==route and editor.details_state.snapshot==details and editor.request_ticket==0
			and editor.selected==original and editor.stockpile_page==page,"Details leaked parent click: "+key):return
	await click_control(editor.zone_menu.buttons.DiningHall);clicked.append("new_zone_type")
	await pointer_click(Vector2(1050,430));clicked.append("world_map")
	for i in 5:world.poll();actions.poll();editor._process(0.02);await process_frame
	if not check(editor.details_origin==route and editor.details_state.snapshot==details and editor.selected==original
		and editor.request_ticket==0 and editor.stockpile_page==page and editor.mode=="inspect"
		and receipts.size()==count and not editor.zone_menu.name_entry.visible,"Details parent shield allowed a hidden edit or request"):return
	await native("guard_after")
	if stopped:return
	details_parent_checked[route]=clicked
	write_json("details-parent-input.json",details_parent_checked)
	print("LOCATION_DETAILS_PARENT_INPUT_PASS route=",route," controls=",clicked)

func staff_route_point(view, occupation: int, remove: bool) -> Vector2:
	var staff=view.staff_view
	var index: int=-1
	for i in staff.rows.size():
		if int(staff.rows[i].get("occupation_id",-1))==occupation:index=i;break
	if not check(index>=0,"staff route occupation absent"):return Vector2.ZERO
	# Initial viewport offset is fixture setup, not a new physical-scroll claim.
	staff.display(editor.details_state.snapshot,mini(index,int(staff.geometry.max_scroll)))
	var x: float=(66 if int(staff.geometry.max_scroll)>0 else 68)*8+16 if remove else 208
	return staff.global_position+Vector2(x,(int(staff.geometry.first_y)-6+(index-staff.first)*3)*12+18)

func staff_route_edits() -> void:
	var model=editor.details_state
	var view=editor.details_view
	var flow=view.staff_workflow
	var selector=view.staff_candidates_view
	var seen: Dictionary={}
	for row in model.snapshot.staff.rows.duplicate(true):
		if int(row.source)!=0 or int(row.unit_id)!=-1 or int(row.histfig_id)!=-1 or seen.has(int(row.role)):continue
		seen[int(row.role)]=true
		step="full route staff %s %d role %d"%[editor.details_origin,int(model.snapshot.id),int(row.role)]
		var original: Dictionary=model.snapshot.duplicate(true)
		var origin: String=editor.details_origin
		# Cancel before the driver polls the manually driven action service.
		var receipts_before:=receipts.size()
		await pointer_click(staff_route_point(view,int(row.occupation_id),false))
		if not check(flow.mode==flow.Mode.Choosing and flow.candidates.ticket>0,"staff route did not queue selector read"):return
		var cancelled_ticket: int=flow.candidates.ticket
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		for i in 3:world.poll();actions.poll();await process_frame
		if not check(flow.mode==flow.Mode.Closed and flow.candidates.ticket==0 and model.snapshot==original
			and receipts.size()==receipts_before+1 and actions.result(cancelled_ticket).get("outcome")=="not_sent"
			and editor.details_origin==origin,"queued selector cancellation leaked work or closed Details"):return
		await pointer_click(staff_route_point(view,int(row.occupation_id),false))
		if not await wait_ui(func():return selector.is_visible_in_tree() and selector.actions_enabled,"full route candidate list"):return
		var ids: Array=[]
		for candidate in selector.rows.slice(0,16):ids.append(int(candidate.unit_id))
		var control:=await native("staff_edit_prepare",{"occupation_id":int(row.occupation_id),"location_id":int(model.snapshot.id),"candidates":ids})
		if stopped:return
		# Verify local ownership under the existing host overlay gate. This is not
		# acceptance of native Options content, transitions or Escape dispatch.
		host.set_overlay_blocked(true)
		await pointer_key(KEY_ENTER);await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not check(flow.mode==flow.Mode.Choosing and model.snapshot==original,"overlay admitted staff input"):return
		host.set_overlay_blocked(false)
		await native("staff_edit_unchanged")
		if stopped:return
		await pointer_click(selector.global_position+Vector2(44,678))
		await pointer_key(KEY_ENTER)
		if not check(not selector.filter_focused and flow.mode==flow.Mode.Choosing and model.snapshot==original,"focused Enter submitted instead of ending text entry"):return
		await native("staff_edit_unchanged")
		if stopped:return
		var selected: int=ids.find(int(control.unit_id))
		if not check(selected>=0,"staff control not in observed first page"):return
		if details_staff_count%2==0:
			for i in selected:await pointer_key(KEY_DOWN)
			await pointer_key(KEY_ENTER)
		else:await pointer_click(selector.global_position+Vector2(80,36+selected*36+18))
		if not await wait_ui(func():return model.phase!=model.Phase.Editing,"full route staff assignment"):return
		if not check(model.phase==model.Phase.Ready and flow.mode==flow.Mode.Closed and selector.all_rows.is_empty()
			and not selector.visible and view.staff_view.first==0 and editor.details_origin==origin,"assignment lost/reset wrong screen"):return
		await native("staff_edit_check",{"assigned":true,"evidence_suffix":"-fortress-"+origin})
		if stopped:return
		await staff_parent_matches_native()
		if stopped:return
		await pointer_click(staff_route_point(view,int(row.occupation_id),true))
		if not await wait_ui(func():return flow.mode==flow.Mode.Closed,"full route staff removal"):return
		if not check(model.phase==model.Phase.Ready and view.staff_view.first==0 and editor.details_origin==origin,"removal lost/reset wrong screen"):return
		await native("staff_edit_check",{"assigned":false,"evidence_suffix":"-fortress-"+origin})
		if stopped:return
		await staff_parent_matches_native()
		if stopped:return
		details_staff_count+=1
		print("LOCATION_STAFF_FORTRESS_PASS origin=",origin," location=",model.snapshot.id," role=",row.role)

func staff_parent_matches_native() -> void:
	if not await wait_ui(func():return editor.details_parent_ticket==0,"staff parent refresh"):return
	var actual:=await inspect(int(editor.selected.id),1)
	if stopped:return
	for key in ["owner_id","owner_name","owner_profession","owner_sex","location_id","location_site_id"]:
		if not check(editor.selected.get(key)==actual.get(key),"staff parent stale field: "+key):return
	var label: String=str(actual.get("owner_name",""))
	if not str(actual.get("owner_profession","")).is_empty():label+=", "+str(actual.owner_profession)
	if int(actual.get("owner_sex",-1)) in [0,1]:label+=", "+("♀" if int(actual.owner_sex)==0 else "♂")
	check(editor.zone_menu.owner_label.text==label,"staff parent owner caption is stale")

func details_entry() -> void:
	step="explicit Details entry"
	await native("paint_counts_location_details",{"phase":"entry_begin"})
	if stopped: return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/location-details-entry_begin.json"))
	var target: Dictionary={}
	for row in reference.rows:
		if int(row.kind)==5: target=row
	if not check(not target.is_empty(),"entry hospital absent"): return
	var read_intent={"action":Contract.ManagementAction.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationDetails,
		"location_site_id":int(target.site_id),"location_id":int(target.id)}
	var read:=await request(read_intent)
	if stopped: return
	var before: Dictionary=read.location_details
	if not check(before.staff.missing_roles==[7,8,9,10] and before.staff.rows.is_empty(),"read prepared slots unexpectedly"): return
	var intent=read_intent.duplicate();intent.action=Contract.ManagementAction.AreaUpdate;intent.operation=Contract.AreaOperation.LocationOpen
	intent.expected_revision=int(before.revision)^1
	await entry_failure(intent,Contract.LocationEntryOutcome.Stale)
	if stopped: return
	read=await request(read_intent)
	if not check(read.location_details==before,"stale entry mutated native facts"): return
	await native("paint_counts_location_details",{"phase":"entry_fail"})
	if stopped: return
	intent.expected_revision=before.revision
	await entry_failure(intent,Contract.LocationEntryOutcome.Unknown)
	if stopped: return
	await native("paint_counts_location_details",{"phase":"entry_recover"})
	if stopped: return
	read=await request(read_intent)
	if stopped: return
	intent.expected_revision=read.location_details.revision
	var opened:=await request(intent)
	if stopped: return
	if not check(int(opened.location_entry_outcome)==Contract.LocationEntryOutcome.Completed and opened.location_details.staff.missing_roles.is_empty(),"entry did not complete"): return
	await native("paint_counts_location_details",{"phase":"entry_after"})
	if stopped: return
	await native("paint_counts_location_details",{"phase":"entry_poll"})
	if stopped: return
	read=await request(read_intent)
	if not check(int(read.location_details.supplies[5].stored)==-123456,"poll refreshed cache unexpectedly"): return
	intent.expected_revision=read.location_details.revision
	var repeated:=await request(intent)
	if not check(repeated.location_details.staff==opened.location_details.staff,"reentry duplicated staffing slots"): return
	await native("paint_counts_location_details",{"phase":"entry_after"})
	if stopped: return
	await native("paint_counts_location_details",{"phase":"entry_restore"})
	if stopped: return
	step="Details state service integration"
	var model=editor.details_state
	var receipt_count:=receipts.size()
	model.open({"site_id":int(target.site_id),"id":int(target.id)})
	if not await wait_ui(func(): return model.ticket==0,"Details state entry"): return
	if not check(model.phase==model.Phase.Ready and int(model.snapshot.id)==int(target.id),"Details state entry did not become ready"): return
	if not check(receipts.size()==receipt_count+2 and int(receipts[-2].area.operation)==Contract.AreaOperation.LocationDetails
		and int(receipts[-1].area.operation)==Contract.AreaOperation.LocationOpen,"Details state must observe then enter exactly once"): return
	var observed: Dictionary=model.snapshot.duplicate(true)
	model.refresh();model.refresh()
	if not await wait_ui(func(): return model.ticket==0,"Details state refresh"): return
	if not check(receipts.size()==receipt_count+3 and int(receipts[-1].area.operation)==Contract.AreaOperation.LocationDetails
		and model.snapshot==observed,"Details state refresh must be observational and stable"): return
	editor.close_panel()
	check(model.phase==model.Phase.Closed and model.snapshot.is_empty(),"closing Areas must retire Details state")


func details_access(locations: Array) -> void:
	step="Details access through state and service"
	var model=editor.details_state
	# Mount the production bar in a test scaffold while the full Details route
	# remains unfinished. Clicks use the viewport, never direct pressed signals.
	var layer:=CanvasLayer.new();layer.layer=128;root.add_child(layer)
	var details_view=preload("res://scripts/location_details_view.gd").new();layer.add_child(details_view)
	details_view.configure(world,model,scene._fortress_hud.native_help);details_view.layout(Vector2(1200,800))
	var bar=details_view.access_view
	var native_text: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_affiliation_visual.json"))
	var font:=Image.load_from_file(world.ui_font_path())
	var staff_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_portraits.json"))
	var palette={7:Color8(192,192,192),15:Color.WHITE,14:Color8(255,225,17),11:Color8(18,254,207),13:Color8(232,17,255)}
	# Entry has its own cache/staff effects. Establish those before isolating edits.
	for row in locations:
		model.open({"site_id":int(row.site_id),"id":int(row.id)})
		if not await wait_ui(func(): return model.ticket==0,"access pre-entry"): return
		if not check(model.phase==model.Phase.Ready,"access pre-entry failed"): return
	await native("paint_counts_location_details",{"phase":"access_begin"})
	if stopped: return
	for row in locations:
		model.open({"site_id":int(row.site_id),"id":int(row.id)})
		if not await wait_ui(func(): return model.ticket==0,"access entry"): return
		if not check(model.phase==model.Phase.Ready,"access entry failed"): return
		await staff_candidates_transport(model.snapshot)
		if stopped:return
		for staff_row in model.snapshot.get("staff",{}).get("rows",[]):
			var names: Dictionary=staff_row.get("names",{})
			if int(names.get("holder_kind",0))!=1:continue
			var holder_id:=int(names.holder_id)
			if not await wait_ui(func():return world.selection_icon(1,holder_id,true)!=null,"staff unit sprite"):return
			var sprite: Image=world.selection_icon(1,holder_id,true).get_image()
			if not check(sprite.get_size()==Vector2i(32,32),"staff unit sprite dimensions differ"):return
			if not check(sprite.save_png(directory+"/staff_unit_%d.png"%holder_id)==OK,"staff sprite capture failed"):return
			if staff_reference.unit_images.has(str(holder_id)):
				sprite.convert(Image.FORMAT_RGBA8)
				# Native fixture records the base image, not generated mip levels.
				sprite.clear_mipmaps()
				var pixels:=sprite.get_data()
				if not check(pixels.size()==32*32*4,"staff sprite base byte count differs"):return
				for pixel in range(0,pixels.size(),4):
					if pixels[pixel+3]==0:pixels[pixel]=0;pixels[pixel+1]=0;pixels[pixel+2]=0
				var hasher:=HashingContext.new();hasher.start(HashingContext.HASH_SHA256);hasher.update(pixels)
				if not check(hasher.finish().hex_encode()==staff_reference.unit_images[str(holder_id)].visible_rgba_sha256,"staff native sprite pixels differ; appearance parity defect"):return
		await access_hover(bar)
		if stopped: return
		var modes=[0,1,2,3] if int(model.snapshot.kind) in [2,4] else [0,1,2]
		for mode in modes:
			var before: Dictionary=model.snapshot.duplicate(true)
			var count:=receipts.size()
			await click_control(bar.buttons[mode]);await click_control(bar.buttons[mode]);model.refresh()
			if not await wait_ui(func(): return model.ticket==0,"access mutation"): return
			if not check(model.phase==model.Phase.Ready and receipts.size()==count+1
				and int(receipts[-1].area.operation)==Contract.AreaOperation.LocationAccess
				and int(receipts[-1].area.location_edit_outcome)==Contract.LocationEditOutcome.Completed,"access mutation receipt differs"): return
			if not check(int(model.snapshot.access)==mode,"access mutation snapshot differs"): return
			if not check(int(bar.current.selected)==mode and not bar.buttons[mode].disabled,"permission bar did not reflect confirmed state"): return
			if not await wait_ui(func(): return scene._fortress_hud.native_help.displayed==str(mode),"access help after click"): return
			if not check(not scene._fortress_hud.minimap_panel.visible,"access help did not replace minimap"): return
			# A semantic receipt can precede the separate render thread's old frame.
			for frame in 3:
				await process_frame;await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image()
			for sample in native_text.cases:
				if sample.case!="baseline" or int(sample.details.id)!=int(row.id):continue
				for text_row in sample.expected:
					for index in text_row.cells.size():
						var cell: Dictionary=text_row.cells[index];var ch:=int(cell.ch)
						var color: Color=palette[int(cell.fg)+(8 if cell.bold else 0)]
						for y in 12:
							for x in 8:
								var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
								if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
								var actual:=image.get_pixel((int(text_row.x)+index)*8+x,int(text_row.y)*12+4+y)
								if not check(absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)<0.035,"live Details heading/affiliation glyph differs"):return
			for index in modes.size():
				var graphic: String="LOCATION_PERMISSION_"+("ON_" if index==mode else "OFF_")+["VISITORS","RESIDENTS","CITIZENS","MEMBERS"][index]
				var expected: Image=world.ui_texture(graphic).get_image()
				for y in 36:
					for x in 32:
						var color:=expected.get_pixel(x,y)
						if color.a<0.99: continue
						var actual:=image.get_pixel(384+index*32+x,112+y)
						if not check(absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)<0.03,"confirmed access graphic not rendered"): return
			if not check(image.save_png(directory+"/scene_access_%d_%d.png"%[int(row.id),mode])==OK,"access capture failed"): return
			var comparable: Dictionary=model.snapshot.duplicate(true)
			for key in ["revision","access","visitors","residents","members"]: comparable[key]=before[key]
			if not check(comparable==before,"access edit changed unrelated Details facts"): return
			await native("paint_counts_location_details",{"phase":"access_check_%d_%d" % [int(row.id),mode]})
			if stopped: return
		if int(model.snapshot.kind)==5:
			var staff=details_view.staff_view
			var scroll=staff.native_scroll
			var before_scroll: Dictionary=model.snapshot.duplicate(true)
			var scroll_receipts:=receipts.size()
			var point: Vector2=scroll.global_position+Vector2(8,scroll.size.y-6)
			await access_motion(point)
			for i in 3:
				for pressed in [true,false]:
					var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
					event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
					root.push_input(event,true);await process_frame
			if not check(staff.first==3 and scroll.first==3 and model.snapshot==before_scroll and receipts.size()==scroll_receipts,"staff scrolling changed simulation or failed to reach lower roles"):return
			model.refresh()
			if not await wait_ui(func():return model.ticket==0,"staff scroll refresh"):return
			if not check(staff.first==3,"Details refresh reset staff scroll"):return
			for frame in 3:await process_frame;await RenderingServer.frame_post_draw
			if not check(root.get_texture().get_image().save_png(directory+"/scene_staff_scrolled.png")==OK,"staff scroll capture failed"):return
		var count:=receipts.size()
		if 3 not in modes:
			model.set_access(3)
			if not check(model.ticket==0 and receipts.size()==count,"unavailable members sent"): return
		# Deliberately stale displayed receipt: bridge refusal must stop the owner.
		model.snapshot.revision=int(model.snapshot.revision)^1
		model.set_access(0)
		if not await wait_ui(func(): return model.ticket==0,"stale access mutation"): return
		if not check(model.phase==model.Phase.Stale and model.snapshot.is_empty(),"stale access did not invalidate owner"): return
		if not check(not scene._fortress_hud.native_help.visible and scene._fortress_hud.minimap_panel.visible,"invalidated access retained help"): return
		count=receipts.size();model.set_access(1);model.refresh()
		if not check(model.ticket==0 and receipts.size()==count,"stale access replayed"): return
		await native("paint_counts_location_details",{"phase":"access_check_%d_%d" % [int(row.id),int(modes[-1])]})
		if stopped: return
	model.close()
	await native("paint_counts_location_details",{"phase":"access_restore"})
	layer.queue_free();await process_frame

func access_hover(bar: Control) -> void:
	var help=scene._fortress_hud.native_help
	await access_motion(Vector2(700,400))
	await create_timer(1.1).timeout
	await access_motion(bar.buttons[0].get_global_rect().get_center())
	var started: int=help.state.started
	if not check(help.displayed.is_empty(),"cold access help skipped native delay"): return
	await create_timer(0.1).timeout
	await access_motion(bar.buttons[1].get_global_rect().get_center())
	if not check(help.state.started==started,"neighbor access button restarted native delay"): return
	if not await wait_ui(func(): return help.displayed=="1","delayed access help"): return
	await access_motion(bar.buttons[2].get_global_rect().get_center())
	if not check(help.displayed=="2" and not scene._fortress_hud.minimap_panel.visible,"warm access transition lost help"): return
	await access_motion(Vector2(700,400))
	if not check(not help.visible and scene._fortress_hud.minimap_panel.visible,"leaving access did not restore minimap"): return
	await access_motion(bar.buttons[0].get_global_rect().get_center())
	if not check(help.displayed=="0","short access return lost native warm state"): return
	print("ACCESS_HOVER_PASS cold delay, neighbor handoff, warm transition, leave and return")

func access_motion(position: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=position;event.global_position=position
	root.push_input(event,true)
	await process_frame;await process_frame

func entry_failure(intent: Dictionary, outcome: int) -> void:
	var seq: int=world.area_request(intent)
	if not check(seq>0,"entry refusal request not sent"): return
	var deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();var state: Dictionary=world.poll_management()
		if int(state.get("request_seq",0))==seq and int(state.get("status",S.Idle)) in [S.Ok,S.Rejected]:
			check(int(state.status)==S.Rejected and int(state.get("area",{}).get("location_entry_outcome",0))==outcome
				and not state.get("area",{}).has("location_details") and str(state.get("message",""))=="","entry refusal outcome differs")
			return
		await create_timer(0.01).timeout
	incomplete("entry refusal wait cap hit; no replay",true)

func quantity_digit(digit: int) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=48+digit;event.physical_keycode=48+digit;event.unicode=48+digit;event.pressed=pressed
		root.push_input(event,true)
	await process_frame

func quantity_route_edits() -> void:
	var model=editor.details_state;var view=editor.details_view.quantity_view
	for row in view.rows.duplicate(true):
		quantity_cases+=1;step="quantity viewport %d location %d"%[int(row.quantity),int(model.identity.id)]
		var quantity:=int(row.quantity)
		var original: int=model.snapshot.desired_copies if quantity==10 else model.snapshot.supplies[quantity].desired
		var scale: int={4:15000,5:10000,7:150,9:150}.get(quantity,1)
		await pointer_click(view.global_position+view.button_rect(row,0).get_center())
		if not check(view.workflow.editing==quantity and view.workflow.text=="","quantity icon did not start native draft"):return
		await quantity_digit(1);await quantity_digit(2)
		if not await wait_ui(func():return model.phase==model.Phase.Ready and not view.workflow.pending,"rapid quantity typing"):return
		await native("quantity_check",{"location_id":int(model.identity.id),"quantity_id":quantity,"value":12*scale})
		for action in [1,2]:
			await pointer_click(view.global_position+view.button_rect(row,action).get_center())
			if not await wait_ui(func():return model.phase==model.Phase.Ready and not view.workflow.pending,"quantity step"):return
			if not check(view.workflow.text=="12","step lost numeric draft"):return
			await native("quantity_check",{"location_id":int(model.identity.id),"quantity_id":quantity,"value":(13 if action==1 else 12)*scale})
		await pointer_key(KEY_ENTER)
		if not check(view.workflow.editing==-1,"quantity Enter did not finish"):return
		await native("quantity_seed",{"location_id":int(model.identity.id),"quantity_id":quantity,"value":original})
		model.refresh()
		if not await wait_ui(func():return model.phase==model.Phase.Ready,"restored quantity receipt"):return
		if stopped:return

func quantity_prepare_close() -> Dictionary:
	var model=editor.details_state;var view=editor.details_view.quantity_view
	if view.rows.is_empty():return {}
	var row: Dictionary=view.rows[0];var quantity:=int(row.quantity)
	var original: int=model.snapshot.desired_copies if quantity==10 else model.snapshot.supplies[quantity].desired
	var scale: int={4:15000,5:10000,7:150,9:150}.get(quantity,1)
	await pointer_click(view.global_position+view.button_rect(row,0).get_center())
	await quantity_digit(2);await quantity_digit(4)
	if not check(view.workflow.pending and model.ticket!=0,"dismissal test must hold a queued edit"):return {}
	return {"quantity":quantity,"original":original,"expected":24*scale}

func quantity_scroll_location(index: int) -> void:
	var view=editor.locations_view
	while index<view.native_scroll.first or index>=view.native_scroll.first+view.native_scroll.page:
		var old: int=view.native_scroll.first
		await pointer_click(view.scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_UP if index<old else MOUSE_BUTTON_WHEEL_DOWN)
		if not check(view.native_scroll.first!=old,"location chooser scroll did not advance"):return
	for frame in 2:editor._process(0);await process_frame
	check(view.scroll.get_global_rect().has_point(view.choices[index].get_global_rect().get_center()),"location chooser target outside clip")

func quantity_lifecycle_open() -> void:
	if not await wait_ui(func():return scene._loader.entered and scene._fortress_hud.enabled,"quantity lifecycle playable fortress"):return
	var area:=await inspect(23,1)
	if stopped:return
	var zones: Button=scene._fortress_hud.navigation.Zones
	zones.show();scene._fortress_hud.layout(scene._fortress_hud.logical_view_size())
	if not editor.panel.visible:await click_control(zones,true)
	if stopped:return
	if not await wait_ui(func():return editor.panel.visible and editor.available and settled(),"quantity lifecycle Zones"):return
	editor.use_area(area)
	await click_control(editor.zone_menu.controls.location)
	if not await wait_ui(func():return settled() and not editor.locations_state.busy() and editor.locations_view.visible,"quantity lifecycle chooser"):return
	await quantity_lifecycle_choose(1)

func quantity_lifecycle_choose(id: int) -> void:
	var index: int=-1
	for i in editor.locations_state.rows.size():
		if int(editor.locations_state.rows[i].id)==id:index=i;break
	if not check(index>=0,"quantity lifecycle location absent"):return
	await quantity_scroll_location(index)
	await click_control(editor.locations_view.choices[index].get_node("Details"))
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and editor.details_layer.visible,"quantity lifecycle Details"):return
	check(int(editor.details_state.snapshot.id)==id,"quantity lifecycle wrong location")

func quantity_unobserved(ticket: int, dispatch:=true) -> Dictionary:
	if dispatch:actions.poll()
	if not check(actions._requests.has(ticket) and int(actions._requests[ticket].sequence)>0,"quantity mutation not sent"):return {}
	var sequence: int=actions._requests[ticket].sequence
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();var reply: Dictionary=world.poll_management()
		if int(reply.get("request_seq",0))==sequence and int(reply.get("status",0))==S.Ok:
			if not check(actions.result(ticket).is_empty(),"quantity receipt already observed"):return {}
			write_json("quantity-unobserved-receipt.json",reply);return reply
		await create_timer(0.02).timeout
	check(false,"quantity native receipt timed out");return {}

func quantity_lifecycle(mode: String) -> void:
	step="quantity lifecycle "+mode
	await seed_catalog()
	await quantity_lifecycle_open()
	if stopped:return
	var model=editor.details_state;var view=editor.details_view.quantity_view;var flow=view.workflow
	var original: int=model.snapshot.supplies[0].desired
	var origin: Dictionary=model.identity.duplicate(true)
	await capture("quantity_lifecycle_ready")
	if mode=="stale":
		await native("quantity_seed",{"location_id":1,"quantity_id":0,"value":41})
		if stopped:return
	await pointer_click(view.global_position+view.button_rect(view.rows[0],0).get_center())
	await quantity_digit(2);await quantity_digit(4)
	var ticket: int=model.ticket
	if not check(ticket>0 and flow.pending and flow.queue.size()==1,"quantity lifecycle requires queued dependent input"):return
	if mode=="stale":
		if not await wait_ui(func():return model.phase==model.Phase.Stale,"stale quantity receipt"):return
		if not check(flow.queue.is_empty() and not flow.pending and flow.editing==-1 and model.snapshot.is_empty(),"stale quantity retained authority"):return
		var next_ticket: int=actions._next_ticket
		await quantity_digit(7)
		await capture("quantity_stale_retired")
		if not check(actions._next_ticket==next_ticket and not view.is_visible_in_tree(),"stale quantity accepted hidden input"):return
		await native("quantity_check",{"location_id":1,"quantity_id":0,"value":41})
		write_json("quantity-lifecycle-outcome.json",actions.result(ticket))
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		await quantity_lifecycle_choose(1)
		if stopped:return
		if not check(int(model.snapshot.supplies[0].desired)==41 and flow.text=="" and flow.editing==-1,"fresh Details reused stale draft"):return
	elif mode=="restart":
		await quantity_unobserved(ticket)
		if stopped:return
		await native("quantity_check",{"location_id":1,"quantity_id":0,"value":2})
		await quantity_restart(ticket)
		if stopped:return
		await native("quantity_check",{"location_id":1,"quantity_id":0,"value":original})
		await quantity_lifecycle_open()
		if stopped:return
		if not check(int(model.snapshot.supplies[0].desired)==original and flow.editing==-1 and flow.queue.is_empty(),"replacement quantity opening reused old work"):return
	elif mode=="late":
		await quantity_unobserved(ticket)
		if stopped:return
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not check(editor.details_closing and not editor.details_layer.visible,"late quantity close did not retire visible input"):return
		# Exercise the visible chooser before polling the old receipt. Opening
		# another target must remain blocked until the typed queue drains.
		if not check(editor.locations_view.is_visible_in_tree() and editor.locations_view.choices[0].get_node("Details").is_visible_in_tree(),"late target-switch control is not visible"):return
		await click_control(editor.locations_view.choices[0].get_node("Details"))
		if not check(editor.details_closing and model.identity==origin and not editor.details_layer.visible,"closing quantity owner was retargeted"):return
		if not await wait_ui(func():return not editor.details_closing,"late quantity drain"):return
		if not check(model.snapshot.is_empty() and model.phase==model.Phase.Closed and not editor.details_layer.visible,"late receipt revived closed Details"):return
		await native("quantity_check",{"location_id":1,"quantity_id":0,"value":24})
		await capture("quantity_late_retired")
		await quantity_lifecycle_choose(0)
		if stopped:return
		if not check(flow.text=="" and flow.editing==-1 and flow.queue.is_empty(),"new target inherited late draft"):return
	else:
		var expected:=original
		if mode=="sent":
			await quantity_unobserved(ticket)
			if stopped:return
			expected=2
		await native("quantity_check",{"location_id":1,"quantity_id":0,"value":expected})
		world.detach_live();actions.poll()
		var outcome: Dictionary=actions.result(ticket)
		write_json("quantity-lifecycle-outcome.json",outcome)
		if not check(outcome.get("outcome")==("unknown" if mode=="sent" else "not_sent"),"quantity disconnect outcome differs"):return
		if not check(model.identity.is_empty() and model.snapshot.is_empty() and flow.queue.is_empty() and not flow.pending and flow.editing==-1 and not editor.details_layer.visible and not editor.details_closing,"disconnect retained quantity authority"):return
		if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active==0,"disconnected quantity remains dispatchable"):return
		if not check(world.attach(),"quantity reconnect failed"):return
		var deadline:=Time.get_ticks_msec()+60000
		while Time.get_ticks_msec()<deadline:
			world.poll();actions.poll();editor._process(0.02)
			if world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)):break
			await create_timer(0.02).timeout
		if not check(bool(world.poll_management().get("transport_alive",false)),"quantity reconnect timeout"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:
			world.poll();actions.poll();editor._process(0.02);await process_frame
		if not check(actions._next_ticket==next_ticket and model.identity.is_empty() and not editor.details_layer.visible,"reconnect replayed or reopened quantity editor"):return
		await native("quantity_check",{"location_id":1,"quantity_id":0,"value":expected})
		await capture("quantity_disconnect_retired")
		await quantity_lifecycle_open()
		if stopped:return
		if not check(int(model.snapshot.supplies[0].desired)==expected and flow.editing==-1 and flow.queue.is_empty(),"reopened quantity failed fresh observation"):return
	await capture("quantity_lifecycle_reopened")
	editor.close_panel()
	await native("quantity_seed",{"location_id":1,"quantity_id":0,"value":original})
	if not stopped:print("LOCATION_QUANTITY_LIFECYCLE_PASS mode=",mode)

func quantity_restart(ticket: int, evidence_prefix:="quantity") -> void:
	var old_epoch: int=world.poll_session().get("fortress_epoch",0)
	var old_generation: int=world.session_generation()
	var new_requests: Dictionary={}
	var first_new_ticket: int=actions._next_ticket
	var observe:=func(received: int, _result: Dictionary):
		if received>=first_new_ticket and actions._requests.has(received):
			var item: Dictionary=actions._requests[received]
			new_requests[received]={"domain":item.domain,"request":item.request.duplicate(true)}
	actions.completed.connect(observe)
	handshake+=1
	write_json("request-%d.json"%handshake,{"op":"reload"})
	var file:=FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE)
	file.store_string(str(handshake));file.close()
	if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt")==OK,"quantity restart handshake failed"):return
	var deadline:=Time.get_ticks_msec()+690000
	var ack: Dictionary={}
	var lost:=false
	while ack.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll_session()
		var header: Dictionary=world.poll_management_header()
		# Keep the old success unobserved until actual transport/generation loss.
		# Otherwise normal polling would settle it before the lane stops DF.
		lost=lost or not bool(header.get("transport_alive",true)) or world.session_generation()!=old_generation or int(header.get("world_epoch",old_epoch)) not in [0,old_epoch]
		if lost:actions.poll(0.02);editor._process(0.02)
		for state in ["failed","incomplete","ack"]:
			var path:=directory+"/%s-%d"%[state,handshake]
			if not FileAccess.file_exists(path):continue
			var reply: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
			if state=="failed":check(false,"quantity restart: "+str(reply.reason));return
			if state=="incomplete":incomplete("quantity restart: "+str(reply.reason),true);return
			ack=reply
		await create_timer(0.02).timeout
	if not check(not ack.is_empty(),"quantity restart timed out; no replay"):return
	var epoch:=int(str(ack.epoch))
	if not check(epoch!=old_epoch and (epoch>>32)==int(ack.pid),"quantity replacement epoch invalid"):return
	deadline=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll_session();actions.poll(0.02);editor._process(0.02)
		if actions._epoch==epoch and actions._active==0 and actions._queue.is_empty():break
		await create_timer(0.02).timeout
	if not check(lost and actions._epoch==epoch and actions._active==0 and actions._queue.is_empty(),"quantity replacement service not ready"):return
	var outcome: Dictionary=actions.result(ticket)
	write_json(evidence_prefix+"-lifecycle-outcome.json",outcome)
	write_json(evidence_prefix+"-restart.json",{"old_epoch":str(old_epoch),"new_epoch":str(epoch),"old_generation":old_generation,"new_generation":world.session_generation(),"pid":ack.pid})
	var model=editor.details_state;var flow=editor.details_view.quantity_view.workflow
	if not check(outcome.get("outcome")=="unknown" and not actions._requests.has(ticket),"old quantity receipt survived producer replacement"):return
	if not check(model.identity.is_empty() and model.snapshot.is_empty() and flow.queue.is_empty() and not flow.pending and flow.editing==-1 and not editor.details_layer.visible and not editor.details_closing,"replacement retained quantity authority"):return
	for frame in 30:
		actions.poll(0.02);editor._process(0.02);await process_frame
	for received in actions._requests:
		if int(received)>=first_new_ticket:
			var item: Dictionary=actions._requests[received]
			new_requests[received]={"domain":item.domain,"request":item.request.duplicate(true)}
	actions.completed.disconnect(observe)
	write_json(evidence_prefix+"-restart-new-requests.json",new_requests)
	for item in new_requests.values():
		if not check(item.domain!="agreements" or not bool(item.request.get("tracker",false)),"replacement automatically submitted tracker work"):return
		if not check(item.domain!="areas" or int(item.request.get("operation",-1)) not in [Contract.AreaOperation.LocationQuantity,Contract.AreaOperation.LocationOpen,Contract.AreaOperation.LocationDetails,Contract.AreaOperation.LocationNameRead,Contract.AreaOperation.LocationNameChoices,Contract.AreaOperation.LocationNameEdit,Contract.AreaOperation.LocationRecognitionRead,Contract.AreaOperation.LocationRecognize,Contract.AreaOperation.LocationReligiousStaffRead,Contract.AreaOperation.LocationReligiousStaffRemove,Contract.AreaOperation.LocationReligiousCandidates,Contract.AreaOperation.LocationReligiousAssignmentRead,Contract.AreaOperation.LocationReligiousAssign,Contract.AreaOperation.LocationSpecializationRead,Contract.AreaOperation.LocationSpecializationSet,Contract.AreaOperation.LocationStaffAssignmentsRead],"replacement automatically submitted Location work"):return
	if not check(model.identity.is_empty() and not editor.details_layer.visible,"replacement reopened quantity editor"):return
	await capture(evidence_prefix+"_restart_retired")

func recognition_route(locations: Array) -> void:
	step="recognition scene fixture"
	var variant:=FileAccess.get_file_as_string(directory+"/recognition-variant.txt").strip_edges()
	var first:=variant in ["first","new"]
	var expected_action: int=Contract.LocationRecognitionState.RecognizePriesthood if first else Contract.LocationRecognitionState.RecognizeHighPriest
	var expected_rank:=1 if first else 2
	var setup:=await native("recognition_setup",{"variant":variant})
	if stopped:return
	var index:=-1
	for i in locations.size():
		if int(locations[i].id)==int(setup.location_id):index=i;break
	if not check(index>=0,"recognition temple absent from chooser"):return
	await click_control(editor.locations_view.choices[index].get_node("Details"))
	var details=editor.details_view
	var recognition=details.recognition_workflow.recognition
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and recognition.phase==recognition.Phase.Ready,"recognition Details and receipt"):return
	write_json("recognition-entry.json",{"details":editor.details_state.snapshot,"recognition":recognition.snapshot})
	# Native entry refresh recomputes the tier. Seed the controlled recognition
	# case after entry, then observe it through the ordinary read-only refresh.
	setup=await native("recognition_setup",{"variant":variant})
	editor.details_state.refresh()
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and recognition.phase==recognition.Phase.Ready and recognition.snapshot.state==expected_action,"controlled recognition tier after entry"):return
	if not check(details.recognition_view.visible and recognition.snapshot.state==expected_action,"recognition action missing"):return
	await capture("recognition_before")
	var disconnect_mode:=FileAccess.get_file_as_string(directory+"/recognition-scene.txt").strip_edges()
	if disconnect_mode=="restart":
		await recognition_restart();return
	if disconnect_mode=="late":
		await recognition_late();return
	if disconnect_mode in ["queued","sent"]:
		await recognition_disconnect(disconnect_mode=="sent");return
	step="recognition scene apply"
	await native("recognition_guard")
	await pointer_click(details.recognition_view.global_position+Vector2(116,18))
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and recognition.phase==recognition.Phase.Ready and recognition.snapshot.rank==expected_rank,"recognition applied and Details refreshed"):return
	if not check(not details.recognition_view.current.get("action",false) and recognition.snapshot.state==(Contract.LocationRecognitionState.NeedsComplex if first else Contract.LocationRecognitionState.NoAction),"completed recognition action retained"):return
	await native("recognition_readback",{"snapshot":recognition.snapshot,"revision":str(recognition.snapshot.revision)})
	var effects:=await native("recognition_applied")
	if stopped:return
	await capture("recognition_after")
	step="recognition scene completed click"
	await native("recognition_guard")
	await pointer_click(details.recognition_view.global_position+Vector2(116,18))
	await create_timer(0.1).timeout;actions.poll()
	await native("recognition_unchanged")
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.details_layer.visible,"recognition Details Back"):return
	write_json("recognition-scene-evidence.json",{"before":setup.before,"after":effects.after,"viewport_click":true,"details_refreshed":true,"details_closed":not editor.details_layer.visible,"completed_action_absent":true,"variant":variant})

func recognition_disconnect(sent: bool) -> void:
	step="recognition disconnect sent="+str(sent)
	var details=editor.details_view
	var recognition=details.recognition_workflow.recognition
	await native("recognition_guard")
	await pointer_click(details.recognition_view.global_position+Vector2(116,18))
	var ticket: int=recognition.ticket
	if not check(ticket>0 and recognition.phase==recognition.Phase.Applying,"recognition pending intent missing"):return
	if sent:
		var reply:=await quantity_unobserved(ticket)
		if stopped:return
		if not check(reply.area.location_recognition.rank==2,"unobserved recognition did not promote"):return
	world.detach_live();actions.poll()
	var outcome: Dictionary=actions.result(ticket)
	write_json("recognition-disconnect-outcome.json",outcome)
	if not check(outcome.get("outcome") == ("unknown" if sent else "not_sent"),"recognition disconnect outcome differs"):return
	if not check(recognition.identity.is_empty() and recognition.snapshot.is_empty() and recognition.ticket==0 and not editor.details_layer.visible,"disconnect retained recognition authority"):return
	if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active==0,"disconnected recognition remains dispatchable"):return
	await native("recognition_applied" if sent else "recognition_unchanged")
	if stopped:return
	await native("recognition_guard")
	if not check(world.attach(),"recognition reconnect failed"):return
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll();editor._process(0.02)
		if world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)):break
		await create_timer(0.02).timeout
	if not check(bool(world.poll_management().get("transport_alive",false)),"recognition reconnect timeout"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();editor._process(0.02);await process_frame
	if not check(actions._next_ticket==next_ticket and recognition.identity.is_empty() and recognition.snapshot.is_empty() and not editor.details_layer.visible,"reconnect replayed or reopened recognition"):return
	await native("recognition_unchanged")
	await capture("recognition_disconnect_retired")
	await quantity_lifecycle_open()
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"recognition fresh chooser"):return
	await quantity_lifecycle_choose(0)
	if not await wait_ui(func():return recognition.phase==recognition.Phase.Ready,"recognition fresh observation after reconnect"):return
	if not check(int(recognition.snapshot.rank)==(2 if sent else 1),"reopened recognition rank differs"):return
	await native("recognition_readback",{"snapshot":recognition.snapshot,"revision":str(recognition.snapshot.revision)})
	await capture("recognition_disconnect_reopened")
	write_json("recognition-disconnect-evidence.json",{"sent":sent,"outcome":outcome.outcome,"no_replay":true,"fresh_rank":recognition.snapshot.rank})
	editor.close_panel()

func recognition_late() -> void:
	step="recognition sent receipt after dismissal"
	var details=editor.details_view
	var recognition=details.recognition_workflow.recognition
	await native("recognition_guard")
	await pointer_click(details.recognition_view.global_position+Vector2(116,18))
	var ticket: int=recognition.ticket
	if not check(ticket>0,"late recognition intent missing"):return
	await quantity_unobserved(ticket)
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not check(not editor.details_layer.visible and recognition.identity.is_empty() and recognition.snapshot.is_empty(),"dismissal retained recognition authority"):return
	await quantity_lifecycle_choose(1)
	if stopped:return
	if not check(recognition.identity.is_empty() and recognition.snapshot.is_empty() and not details.recognition_view.visible,"late recognition revived in a different location"):return
	await native("recognition_applied")
	if stopped:return
	await capture("recognition_late_other_location")
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"late recognition chooser"):return
	await quantity_lifecycle_choose(0)
	if not await wait_ui(func():return recognition.phase==recognition.Phase.Ready,"late recognition fresh observation"):return
	# Reopening recomputes temple tier; native may show tier guidance even at rank2.
	if not check(recognition.snapshot.rank==2 and not details.recognition_view.current.get("action",false),"fresh recognition did not observe promotion"):return
	await native("recognition_readback",{"snapshot":recognition.snapshot,"revision":str(recognition.snapshot.revision)})
	write_json("recognition-late-evidence.json",{"old_ticket":ticket,"other_location":1,"old_owner_retired":true,"fresh_rank":recognition.snapshot.rank})
	editor.close_panel()

func recognition_restart() -> void:
	step="recognition producer restart"
	var details=editor.details_view
	var recognition=details.recognition_workflow.recognition
	await native("recognition_guard")
	await pointer_click(details.recognition_view.global_position+Vector2(116,18))
	var ticket: int=recognition.ticket
	if not check(ticket>0,"restart recognition intent missing"):return
	var reply:=await quantity_unobserved(ticket)
	if stopped:return
	if not check(reply.area.location_recognition.rank==2,"restart requires native promotion before replacement"):return
	await native("recognition_applied")
	if stopped:return
	await quantity_restart(ticket,"recognition")
	if stopped:return
	if not check(recognition.identity.is_empty() and recognition.snapshot.is_empty() and recognition.ticket==0 and not details.recognition_view.visible,"restart retained recognition authority"):return
	await quantity_lifecycle_open()
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"replacement recognition chooser"):return
	await quantity_lifecycle_choose(0)
	if not await wait_ui(func():return recognition.phase==recognition.Phase.Ready,"replacement recognition fresh observation"):return
	if not check(recognition.snapshot.rank==1,"replacement retained unsaved promotion or replayed it"):return
	await native("recognition_readback",{"snapshot":recognition.snapshot,"revision":str(recognition.snapshot.revision)})
	await capture("recognition_restart_reopened")
	write_json("recognition-restart-evidence.json",{"old_ticket":ticket,"old_owner_retired":true,"old_applied_rank":2,"fresh_rank":recognition.snapshot.rank})
	editor.close_panel()

func religious_staff_route(locations: Array) -> void:
	step="religious staff scene entry"
	var lifecycle:=FileAccess.get_file_as_string(directory+"/religious-staff-scene.txt").strip_edges()
	var setup:=await native("religious_setup",{"absent":lifecycle=="absent"})
	if stopped:return
	var index:=-1
	for i in locations.size():
		if int(locations[i].id)==0:index=i;break
	if not check(index>=0,"religious temple absent"):return
	await click_control(editor.locations_view.choices[index].get_node("Details"))
	var details=editor.details_view
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and details.recognition_workflow.recognition.phase==details.recognition_workflow.recognition.Phase.Ready,"religious Details entry"):return
	var view=details.staff_view
	if lifecycle=="tracker":
		await tracker_transport();return
	if lifecycle=="tracker-hud":
		await tracker_hud();return
	if lifecycle.begins_with("popup-"):
		await popup_lifecycle(lifecycle.trim_prefix("popup-"));return
	if lifecycle.begins_with("tracker-"):
		await tracker_lifecycle(lifecycle.trim_prefix("tracker-"));return
	if lifecycle.begins_with("indicators-"):
		await indicators_lifecycle(lifecycle.trim_prefix("indicators-"));return
	if lifecycle.begins_with("specialization-"):
		await specialization_lifecycle(lifecycle.trim_prefix("specialization-"));return
	if lifecycle=="none":
		await specialization_scene()
		if stopped:return
	var row_index:=-1
	for i in view.rows.size():
		if int(view.rows[i].get("source",-1))==1 and int(view.rows[i].assignment_id)==int(setup.assignment_id):row_index=i;break
	if not check(row_index>=view.first and row_index<view.first+int(view.geometry.visible_count),"religious holder not visible"):return
	var point: Vector2=view.global_position+Vector2((view.row_columns()-4)*8+16,(int(view.geometry.first_y)-6+(row_index-view.first)*3)*12+18)
	await capture("religious_staff_before")
	if lifecycle=="absent":
		var held: Dictionary=view.rows[row_index]
		if not check(int(held.unit_id)==-1 and int(held.histfig_id)==int(setup.holder_id) and int(held.names.holder_kind)==2,"historical holder fallback missing"):return
	if lifecycle=="restart":
		await religious_staff_restart(point,int(setup.holder_id),row_index);return
	if lifecycle=="late":
		await religious_staff_late(point,row_index);return
	if lifecycle in ["queued","sent"]:
		await religious_staff_disconnect(lifecycle=="sent",point,int(setup.holder_id),row_index);return
	step="religious staff scene remove"
	await native("religious_guard")
	await pointer_click(point)
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and not details.religious_staff_workflow.active and details.recognition_workflow.recognition.phase==details.recognition_workflow.recognition.Phase.Ready and int(details.staff_view.rows[row_index].histfig_id)==-1,"religious removal and Details refresh"):return
	var effects:=await native("religious_applied")
	if stopped:return
	await capture("religious_staff_after")
	if lifecycle=="absent":
		write_json("religious-absent-scene-evidence.json",{"holder_id":setup.holder_id,"holder_kind":2,"unit_id":-1,"removed":true,"native_effects":effects})
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not await wait_ui(func():return editor.details_origin.is_empty(),"historical holder Details Back"):return
		return
	step="religious vacant repeat"
	await native("religious_guard")
	await pointer_click(point)
	await create_timer(0.1).timeout;actions.poll()
	await native("religious_unchanged")
	step="religious assignment picker"
	var flow=details.religious_assignment_workflow
	var selector=details.staff_candidates_view
	var assign_point: Vector2=view.global_position+Vector2(208,(int(view.geometry.first_y)-6+(row_index-view.first)*3)*12+18)
	await pointer_click(assign_point)
	if not check(flow.mode==flow.Mode.Choosing and flow.candidates.ticket>0,"religious icon did not queue candidate read"):return
	var cancelled_ticket: int=flow.candidates.ticket
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	for i in 3:world.poll();actions.poll();await process_frame
	if not check(flow.mode==flow.Mode.Closed and actions.result(cancelled_ticket).get("outcome")=="not_sent" and editor.details_layer.visible,"queued religious cancel changed owner"):return
	await pointer_click(assign_point)
	if not await wait_ui(func():return selector.is_visible_in_tree() and selector.actions_enabled,"religious candidate picker visible"):return
	await native("religious_candidates_readback",{"rows":flow.candidates.rows})
	if lifecycle in ["assignment-late","assignment-restart"]:
		await religious_assignment_retire(lifecycle=="assignment-restart",row_index,int(setup.holder_id));return
	if lifecycle.begins_with("assignment-"):
		await religious_assignment_disconnect(lifecycle=="assignment-sent",row_index,lifecycle=="assignment-receipt");return
	await capture("religious_assignment_candidates")
	var input_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json"))
	for sample in input_reference.religious_staff_assignment_reference.interaction_reference.states:
		var label: String=sample.name
		if label.begins_with("sort-"):
			var header:=int(label.split("-")[1])-1
			await pointer_click(Vector2([432,512,584,680][header],70))
		else:
			await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
			await pointer_click(assign_point)
			if not await wait_ui(func():return selector.is_visible_in_tree() and selector.actions_enabled,"religious filter reopen"):return
			await pointer_click(Vector2(500,730))
			for character in label.trim_prefix("filter-"):
				for pressed in [true,false]:
					var event:=InputEventKey.new();event.unicode=character.unicode_at(0);event.keycode=character.to_upper().unicode_at(0);event.pressed=pressed
					root.push_input(event,true)
				await process_frame
		var actual: Array=[]
		for row in selector.rows:actual.append(int(row.unit_id))
		var expected: Array=[]
		for id in sample.ids:expected.append(int(id))
		if not check(actual==expected,"religious native order/filter differs: "+label):return
		if not check(selector.first==0 and selector.selected==0,"religious input did not reset cursor/scroll: "+label):return
	await capture("religious_assignment_filtered")
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	await pointer_click(assign_point)
	if not await wait_ui(func():return selector.is_visible_in_tree() and selector.actions_enabled,"religious assignment after filters"):return
	host.set_overlay_blocked(true)
	await pointer_key(KEY_ENTER);await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not check(flow.mode==flow.Mode.Choosing,"overlay admitted religious picker input"):return
	host.set_overlay_blocked(false)
	var chosen: Dictionary=selector.rows[0].duplicate(true)
	await native("religious_guard")
	await pointer_click(selector.global_position+Vector2(80,54))
	if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and flow.mode==flow.Mode.Closed and int(details.staff_view.rows[row_index].histfig_id)==int(chosen.histfig_id),"religious assignment and Details refresh"):return
	if not check(not selector.visible and selector.all_rows.is_empty(),"completed religious picker retained rows"):return
	await native("religious_assignment_applied",{"unit_id":chosen.unit_id,"histfig_id":chosen.histfig_id})
	await capture("religious_assignment_completed")
	write_json("religious-assignment-scene-evidence.json",{"unit_id":chosen.unit_id,"histfig_id":chosen.histfig_id,"viewport_click":true,"queued_cancel":"not_sent","overlay_blocked":true,"details_refreshed":true})
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.details_layer.visible,"religious Details Back"):return
	write_json("religious-staff-scene-evidence.json",{"before":setup.before,"after":effects.after,"event":effects.event,"viewport_click":true,"details_refreshed":true,"vacant_repeat_unchanged":true,"details_closed":true})

func specialization_scene() -> void:
	var details=editor.details_view
	var view=details.staff_view
	var reader=details.specialization_reader
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json"))
	var evidence: Array=[]
	for sample in fixture.specialization_reference.cases:
		var change: Dictionary=sample.changed[0]
		step="specialization scene "+str(change.unit_id)
		await native("religious_specialization_setup",{"unit_id":change.unit_id,"expected":change.before})
		if stopped:return
		var row: Dictionary={};var row_index:=-1
		for i in view.rows.size():
			if int(view.rows[i].get("names",{}).get("holder_id",-1))==int(change.unit_id):row=view.rows[i];row_index=i;break
		if not check(row_index>=view.first,"specialization row absent"):return
		if not await wait_ui(func():return not details.assignments_reader.receipt(row).is_empty(),"assignment indicator receipt"):return
		var assigned: Dictionary=details.assignments_reader.receipt(row)
		var expected_assignments:=await native("religious_assignments",{"unit_id":change.unit_id})
		if not check(assigned.entries.size()==expected_assignments.entries.size(),"visible assignment count"):return
		for i in assigned.entries.size():
			for key in ["kind","id","type","subtype","custom","name","custom_code"]:
				if not check(assigned.entries[i][key]==expected_assignments.entries[i][key],"visible assignment native field "+key):return
		var indicator_point: Vector2=view.global_position+Vector2((view.row_columns()-20)*8+16,(int(view.geometry.first_y)-6+(row_index-view.first)*3)*12+18)
		var indicator_hover:=InputEventMouseMotion.new();indicator_hover.position=indicator_point;indicator_hover.global_position=indicator_point;root.push_input(indicator_hover,true)
		await create_timer(0.65).timeout
		if not check(view.hover_help.displayed==("staff_work_detail" if int(change.unit_id)==5813 else "staff_performer"),"visible assignment tooltip"):return
		await capture("assignment_%d"%int(change.unit_id))
		if not await wait_ui(func():return reader.receipt(row).get("eligible",false),"specialization displayed receipt"):return
		if not check(reader.receipt(row).specialized==change.before.specialized,"specialization initial displayed state"):return
		var point: Vector2=view.global_position+view.specialization_rect(row_index-view.first).get_center()
		var hover:=InputEventMouseMotion.new();hover.position=point;hover.global_position=point;root.push_input(hover,true)
		await create_timer(0.65).timeout
		if not check(view.hover_help.visible and view.hover_help.displayed=="specialization_"+str(int(change.before.specialized)),"specialization native tooltip hit region point=%s local=%s rect=%s view_visible=%s key=%s displayed=%s owner=%s"%[point,view.get_local_mouse_position(),view.specialization_rect(row_index-view.first),view.is_visible_in_tree(),view.hover_help.state.key,view.hover_help.displayed,view.hover_help.state.owner]):return
		await native("religious_specialization_check",{"unit_id":change.unit_id,"expected":change.before})
		await capture("specialization_%d_before"%int(change.unit_id))
		host.set_overlay_blocked(true);await pointer_click(point);host.set_overlay_blocked(false)
		if not check(not details.specialization_workflow.active,"overlay admitted specialization gesture"):return
		for expected in [change.after,change.before]:
			await pointer_click(point)
			if not await wait_ui(func():return editor.details_state.phase==editor.details_state.Phase.Ready and not details.specialization_workflow.active and reader.receipt(row).get("specialized")==expected.specialized,"specialization click and refreshed native state"):return
			await native("religious_specialization_check",{"unit_id":change.unit_id,"expected":expected})
			if stopped:return
			await capture("specialization_%d_%s"%[int(change.unit_id),str(expected.specialized)])
		evidence.append({"unit_id":change.unit_id,"viewport_clicks":2,"native_effects_matched":true,"restored":true})
	write_json("specialization-scene-evidence.json",{"cases":evidence})

func tracker_hud() -> void:
	step="main scene petition tracker"
	editor.close_panel()
	var expected:=await native("religious_tracker",{"seed":true})
	if stopped:return
	var tracker=scene._ui.ensure_agreement_tracker()
	if not await wait_ui(func():return tracker.reader.ready,"HUD tracker rows"):return
	if not check(tracker.reader.snapshot().size()==expected.rows.size(),"HUD native row count"):return
	var samples: Array=[]
	for dimensions in [Vector2i(1200,800),Vector2i(960,600),Vector2i(1600,900)]:
		root.size=dimensions
		await process_frame;await process_frame
		var point: Vector2=(tracker.list_view.position+Vector2(24,60))*tracker.scale
		var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;root.push_input(event,true)
		await process_frame;await process_frame
		print("TRACKER_HUD_POINTER requested=",point," actual=",root.get_mouse_position()," gui=",root.gui_get_hovered_control()," active=",host.active," entered=",tracker.session_entered," list=",tracker.list_view.visible," rows=",tracker.list_view.displayed_rows," target=",tracker.popup_reader.target," ticket=",tracker.popup_reader.ticket," enabled=",scene._fortress_hud.enabled)
		if not await wait_ui(func():return tracker.popup_reader.ready and tracker.hover_claimed,"HUD petition pointer"):return
		if not check(scene._ui.tile_hover.obscured and not scene._ui.tile_hover.panel.visible,"terrain competes with petition"):return
		var row: Dictionary=tracker.popup_reader.target
		var facts:=await native("religious_tracker_details",{"agreement_id":row.agreement_id})
		if stopped:return
		for key in tracker.popup_reader.snapshot().details:
			if not check(tracker.popup_reader.snapshot().details[key]==facts.facts[key],"HUD native popup "+key):return
		await capture("tracker_hud_"+str(dimensions.x))
		samples.append({"viewport":[dimensions.x,dimensions.y],"row":row,"details":tracker.popup_reader.snapshot().details})
	# Existing Info owners keep the list but retire hover; close restores it.
	scene._ui.open_destination("Residents")
	await process_frame;await process_frame
	if not check(tracker.list_view.visible and not tracker.hover_claimed and not tracker.popup_view.visible,"Info tracker gates"):return
	host.close_active()
	if not await wait_ui(func():return tracker.popup_reader.ready,"HUD popup after Info"):return
	var leave:=InputEventMouseMotion.new();leave.position=Vector2(400,400);leave.global_position=leave.position;root.push_input(leave,true)
	await process_frame;await process_frame
	if not check(not tracker.hover_claimed and not scene._ui.tile_hover.obscured and not tracker.popup_view.visible,"HUD hover leave"):return
	tracker.retire()
	await native("religious_tracker",{"restore":true})
	if stopped:return
	write_json("tracker-hud-evidence.json",{"samples":samples,"info_gate":true,"terrain_priority":true,"pointer_leave":true})

func tracker_transport() -> void:
	step="native tracker typed transport"
	var reader=preload("res://scripts/continuing_agreements_reader.gd").new();reader.configure(actions)
	var popup_reader=preload("res://scripts/continuing_agreement_popup_reader.gd").new();popup_reader.configure(reader)
	var evidence: Array=[]
	for phase in ["empty","populated","restored"]:
		var expected:=await native("religious_tracker",{"seed":phase=="populated","restore":phase=="restored"})
		if stopped:return
		await native("religious_guard")
		reader.set_active(true);reader.refresh()
		var ticket: int=reader.ticket
		if not check(ticket>0,"tracker request not queued"):return
		if not await wait_ui(func():return not actions.result(ticket).is_empty(),"tracker native result"):return
		var result: Dictionary=actions.result(ticket)
		if not check(result.status==S.Ok and result.action==36 and result.agreement.tracker and result.agreement.agreements.is_empty(),"tracker typed result missing"):return
		if not check(reader.ready,"tracker reader did not become ready"):return
		var rows: Array=reader.snapshot()
		if not check(rows.size()==expected.rows.size() and rows.size()==(3 if phase=="populated" else 0),"tracker row count"):return
		for index in rows.size():
			for field in ["agreement_id","subject_id","entity_id","entity_type","tier","profession","year","year_tick","heading","applicant","date"]:
				if not check(rows[index][field]==expected.rows[index][field],"tracker native field "+field):return
		await native("religious_unchanged")
		if stopped:return
		var popups: Array=[]
		for row in rows:
			var expected_popup:=await native("religious_tracker_details",{"agreement_id":row.agreement_id})
			if stopped:return
			await native("religious_guard")
			popup_reader.display(row);popup_reader.refresh()
			var popup_ticket: int=popup_reader.ticket
			if not check(popup_ticket>0,"popup request not queued"):return
			if not await wait_ui(func():return not actions.result(popup_ticket).is_empty(),"popup native result"):return
			var popup: Dictionary=actions.result(popup_ticket)
			if not check(popup.status==S.Ok and popup.action==37 and popup.agreement.tracker and popup.agreement.tracker_rows==[row],"popup identity or mode differs"):return
			if not check(popup.agreement.has("tracker_details") and expected_popup.facts.valid,"popup facts absent"):return
			if not check(popup_reader.ready and popup_reader.snapshot().row==row and popup_reader.snapshot().details==popup.agreement.tracker_details,"popup reader facts differ"):return
			for field in ["required_value","matching_locations","location_id","location_value","location_tier","site_available","tier_met","location_name"]:
				if not check(popup.agreement.tracker_details[field]==expected_popup.facts[field],"popup field mismatch "+field):return
			await native("religious_unchanged")
			if stopped:return
			popups.append({"ticket":popup_ticket,"agreement_id":row.agreement_id,"facts":popup.agreement.tracker_details})
		if phase=="populated":
			popup_reader.display(rows[0]);var held: int=popup_reader.ticket
			await quantity_unobserved(held)
			if stopped:return
			popup_reader.display(rows[1]);var replacement: int=popup_reader.ticket
			if not check(replacement>held and not popup_reader.ready and popup_reader.snapshot().is_empty(),"hover switch retained old popup"):return
			actions.poll()
			if not check(popup_reader.target==rows[1] and popup_reader.snapshot().is_empty(),"late reply populated replacement hover"):return
			if not await wait_ui(func():return popup_reader.ready,"replacement hover receipt"):return
			if not check(popup_reader.snapshot().row==rows[1],"replacement hover has wrong row"):return
			popups.append({"held_ticket":held,"replacement_ticket":replacement,"late_reply_isolated":true})
		if phase=="restored":
			if not check(popup_reader.target.is_empty() and not popup_reader.ready and popup_reader.snapshot().is_empty(),"removed row retained popup reader"):return
			var missing: int=actions.submit("agreements",{"action":37,"tracker":true,"id":2147483502},Callable())
			if not await wait_ui(func():return not actions.result(missing).is_empty(),"removed popup refusal"):return
			var rejected: Dictionary=actions.result(missing)
			if not check(rejected.status==S.Rejected and not rejected.agreement.tracker and not rejected.agreement.has("tracker_details"),"removed popup retained facts"):return
		evidence.append({"phase":phase,"rows":rows,"ticket":ticket,"popups":popups})
	popup_reader.dispose();reader.dispose()
	write_json("tracker-transport-evidence.json",{"cases":evidence,"reader_retired":not reader.active and reader.snapshot().is_empty()})
	editor.close_panel()

func popup_lifecycle(mode: String) -> void:
	step="popup lifecycle "+mode
	var source=preload("res://scripts/continuing_agreements_reader.gd").new();source.configure(actions)
	var popup=preload("res://scripts/continuing_agreement_popup_reader.gd").new();popup.configure(source)
	await native("religious_tracker",{"seed":true})
	if stopped:return
	if not await wait_ui(func():return actions._active==0 and actions._queue.is_empty(),"popup initial queue drain"):return
	source.set_active(true)
	if not await wait_ui(func():return source.ready,"popup initial list"):return
	var row: Dictionary=source.snapshot()[1];popup.display(row)
	if not await wait_ui(func():return popup.ready,"popup initial observation"):return
	var original: Dictionary=popup.snapshot()
	popup.refresh();var ticket: int=popup.ticket
	if not check(ticket>0,"popup lifecycle read absent"):return
	if mode!="queued":
		var reply:=await quantity_unobserved(ticket)
		if stopped:return
		if not check(reply.agreement.tracker_details==original.details,"held popup receipt differs"):return
	if mode=="restart":
		await quantity_restart(ticket,"popup")
		if stopped:return
	else:
		world.detach_live();actions.poll()
		if not check(actions.result(ticket).get("outcome")==("not_sent" if mode=="queued" else "unknown"),"popup disconnect outcome"):return
		if not check(not actions._requests.has(ticket) and actions._active==0 and actions._queue.is_empty(),"popup request survived disconnect"):return
		if not check(world.attach(),"popup reconnect failed"):return
		if not await wait_ui(func():return world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)),"popup reconnect"):return
	if not check(not source.active and not source.ready and popup.target.is_empty() and popup.ticket==0 and not popup.ready and popup.snapshot().is_empty(),"popup session retained facts"):return
	if not check(not actions._requests.has(ticket),"popup request survived session loss"):return
	for item in actions._requests.values():
		if not check(item.domain!="agreements" or not bool(item.request.get("tracker",false)),"popup replayed during reconnect"):return
	if not await wait_ui(func():return actions._active==0 and actions._queue.is_empty(),"popup reconnect initialization drain"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();source.poll(0.1);popup.poll(0.1);editor._process(0.02);await process_frame
	if not check(actions._next_ticket==next_ticket and popup.target.is_empty(),"popup automatically replayed"):return
	source.set_active(true)
	if not await wait_ui(func():return source.ready,"popup fresh list"):return
	if mode=="restart":
		if not check(source.snapshot().is_empty(),"new fortress retained unsaved agreements"):return
		next_ticket=actions._next_ticket;popup.display(row)
		if not check(popup.target.is_empty() and actions._next_ticket==next_ticket,"old row opened popup in replacement fortress"):return
	else:
		popup.display(row)
		if not await wait_ui(func():return popup.ready,"popup explicit reopen"):return
		if not check(popup.snapshot()==original,"fresh popup facts differ"):return
		await native("religious_tracker",{"restore":true})
		if stopped:return
	popup.dispose();source.dispose()
	write_json("popup-lifecycle-evidence.json",{"mode":mode,"ticket":ticket,"retired":true,"no_replay":true,"fresh_state_verified":true})
	editor.close_panel()

func tracker_lifecycle(mode: String) -> void:
	step="tracker lifecycle "+mode
	var reader=preload("res://scripts/continuing_agreements_reader.gd").new();reader.configure(actions)
	var expected:=await native("religious_tracker",{"seed":true})
	if stopped:return
	if not await wait_ui(func():return actions._active==0 and actions._queue.is_empty(),"tracker initial queue drain"):return
	reader.set_active(true)
	if not await wait_ui(func():return reader.ready,"tracker initial rows"):return
	var original: Array=reader.snapshot()
	if not check(original.size()==expected.rows.size() and original.size()==3,"tracker fixture absent"):return
	reader.refresh();var ticket: int=reader.ticket
	if not check(ticket>0,"tracker lifecycle read absent"):return
	if mode!="queued":
		var reply:=await quantity_unobserved(ticket)
		if stopped:return
		if not check(reply.agreement.tracker and reply.agreement.tracker_rows==original,"tracker held receipt differs"):return
	if mode=="restart":
		await quantity_restart(ticket,"tracker")
		if stopped:return
		if not check(not reader.active and not reader.ready and reader.ticket==0 and reader.snapshot().is_empty(),"tracker restart retained old rows"):return
		var current:=await native("religious_tracker",{})
		if stopped:return
		if not check(current.rows.is_empty(),"replacement fortress retained unsaved tracker fixture"):return
		reader.set_active(true)
		if not await wait_ui(func():return reader.ready,"replacement tracker observation"):return
		if not check(reader.snapshot().is_empty(),"replacement tracker inherited old rows"):return
	elif mode=="late":
		reader.set_active(false)
		await native("religious_tracker",{"restore":true})
		if stopped:return
		reader.set_active(true);var replacement: int=reader.ticket
		if not check(replacement>ticket,"tracker replacement not queued"):return
		actions.poll()
		if not check(reader.snapshot().is_empty(),"late tracker receipt revived old rows"):return
		if not await wait_ui(func():return reader.ready,"tracker replacement rows"):return
		if not check(reader.snapshot().is_empty(),"tracker replacement retained old rows"):return
	else:
		world.detach_live();actions.poll()
		if not check(actions.result(ticket).get("outcome")==("not_sent" if mode=="queued" else "unknown"),"tracker disconnect outcome"):return
		if not check(not reader.active and not reader.ready and reader.ticket==0 and reader.snapshot().is_empty(),"tracker session retained rows"):return
		if not check(not actions._requests.has(ticket) and actions._active==0 and actions._queue.is_empty(),"tracker request survived disconnect"):return
		if not check(world.attach(),"tracker reconnect failed"):return
		if not await wait_ui(func():return world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)),"tracker reconnect"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:
			world.poll();actions.poll();reader.poll(0.1);editor._process(0.02);await process_frame
		if not check(actions._next_ticket==next_ticket and not reader.active and reader.snapshot().is_empty(),"tracker reconnect replayed"):return
		reader.set_active(true)
		if not await wait_ui(func():return reader.ready,"tracker fresh rows"):return
		if not check(reader.snapshot()==original,"tracker fresh facts differ"):return
		await native("religious_tracker",{"restore":true})
		if stopped:return
	reader.dispose()
	write_json("tracker-lifecycle-evidence.json",{"mode":mode,"ticket":ticket,"retired":not reader.active and reader.snapshot().is_empty(),"fresh_facts_verified":true})
	editor.close_panel()

func indicators_scroll() -> void:
	step="staff indicators scroll lifecycle"
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	await quantity_lifecycle_choose(2)
	if stopped:return
	var details=editor.details_view
	var view=details.staff_view
	var reader=details.assignments_reader
	var row: Dictionary=view.rows[0].duplicate(true)
	var snapshot: Dictionary=editor.details_state.snapshot.duplicate(true)
	var evidence: Array=[]
	for sent in [false,true]:
		if not await wait_ui(func():return reader.ticket==0 and details.specialization_reader.ticket==0 and not reader.receipt(row).is_empty() and actions._active==0 and actions._queue.is_empty(),"indicator scroll initial pass"):return
		var original: Dictionary=reader.receipt(row)
		reader.clear();reader.display(view.visible_rows())
		var ticket: int=reader.ticket
		if not check(ticket>0,"indicator scroll pending read absent"):return
		if sent:
			await quantity_unobserved(ticket)
			if stopped:return
		var bar=view.native_scroll
		await pointer_click(bar.global_position+Vector2(8,bar.size.y-6))
		if not check(view.first==1 and bar.first==1 and row not in view.visible_rows(),"indicator scroll did not retire first row"):return
		if not check(reader.receipt(row).is_empty() and row not in reader.rows and reader.ticket!=ticket,"scrolled-away indicator retained"):return
		if not await wait_ui(func():return reader.ticket==0 and details.specialization_reader.ticket==0 and actions._active==0 and actions._queue.is_empty(),"indicator scrolled pass"):return
		if not check(reader.receipt(row).is_empty() and view.assignment_slots(view.rows[1]).is_empty(),"old reply populated vacant row"):return
		var observed: Array=[]
		for visible in view.visible_rows():
			var holder: int=visible.get("names",{}).get("holder_id",-1)
			if holder<0:continue
			var facts: Dictionary=reader.receipt(visible)
			if not check(int(facts.get("unit_id",-1))==holder and int(facts.get("occupation_id",-1))==int(visible.occupation_id),"scrolled indicator row identity"):return
			observed.append(holder)
		if not check(6817 in observed,"newly visible surgeon facts missing"):return
		await capture("indicators_scroll_"+("sent" if sent else "queued"))
		await pointer_click(bar.global_position+Vector2(8,6))
		if not check(view.first==0,"indicator scroll back failed"):return
		if not await wait_ui(func():return not reader.receipt(row).is_empty(),"indicator scroll fresh original row"):return
		if not check(reader.receipt(row)==original and editor.details_state.snapshot==snapshot,"scroll changed facts or Details"):return
		evidence.append({"sent":sent,"ticket":ticket,"visible_units":observed,"old_row_retired":true,"fresh_facts_match":true})
	write_json("indicators-scroll-evidence.json",{"cases":evidence})
	editor.close_panel()

func indicators_lifecycle(mode: String) -> void:
	if mode=="scroll":
		await indicators_scroll();return
	step="staff indicators lifecycle "+mode
	var details=editor.details_view
	var reader=details.assignments_reader
	var row: Dictionary=details.staff_view.rows[0].duplicate(true)
	if not await wait_ui(func():return reader.ticket==0 and details.specialization_reader.ticket==0 and not reader.receipt(row).is_empty() and actions._active==0 and actions._queue.is_empty(),"indicator initial pass"):return
	var original: Dictionary=reader.receipt(row)
	reader.clear();reader.display(details.staff_view.visible_rows())
	var ticket: int=reader.ticket
	if not check(ticket>0,"indicator new pass absent"):return
	if mode!="queued":
		var reply:=await quantity_unobserved(ticket)
		if stopped:return
		if not check(int(reply.area.location_staff_assignments.unit_id)==int(original.unit_id),"indicator unobserved identity"):return
	if mode=="late":
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not check(reader.owner.is_empty() and reader.rows.is_empty() and reader.receipts.is_empty() and reader.ticket==0,"closed indicator owner retained"):return
		await quantity_lifecycle_choose(1)
		if stopped:return
		if not check(int(editor.details_state.identity.id)==1 and reader.receipt(row).is_empty(),"late indicator revived on another location"):return
	elif mode=="restart":
		await quantity_restart(ticket,"indicators")
		if stopped:return
		if not check(reader.owner.is_empty() and reader.rows.is_empty() and reader.receipts.is_empty() and reader.ticket==0,"indicator restart retained display"):return
		await quantity_lifecycle_open()
		if stopped:return
	else:
		world.detach_live();actions.poll()
		if not check(actions.result(ticket).get("outcome")==("not_sent" if mode=="queued" else "unknown"),"indicator disconnect outcome"):return
		if not check(reader.owner.is_empty() and reader.rows.is_empty() and reader.receipts.is_empty() and reader.ticket==0 and not editor.details_layer.visible,"indicator disconnect retained display"):return
		if not check(not actions._requests.has(ticket) and actions._active==0 and actions._queue.is_empty(),"indicator request survived disconnect"):return
		if not check(world.attach(),"indicator reconnect failed"):return
		if not await wait_ui(func():return world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)),"indicator reconnect"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:world.poll();actions.poll();editor._process(0.02);await process_frame
		if not check(actions._next_ticket==next_ticket and reader.owner.is_empty() and not editor.details_layer.visible,"indicator reconnect replayed or reopened"):return
		await quantity_lifecycle_open()
		if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"indicator fresh chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	if not await wait_ui(func():return not reader.receipt(row).is_empty(),"indicator fresh receipt"):return
	if not check(reader.receipt(row)==original,"indicator fresh facts differ"):return
	await capture("indicators_lifecycle_"+mode)
	write_json("indicators-lifecycle-evidence.json",{"mode":mode,"ticket":ticket,"owner_retired":true,"fresh_facts_match":true})
	editor.close_panel()

func specialization_lifecycle(mode: String) -> void:
	step="specialization lifecycle "+mode
	var details=editor.details_view
	var view=details.staff_view
	var flow=details.specialization_workflow
	var reader=details.specialization_reader
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json"))
	var change: Dictionary=fixture.specialization_reference.cases[0].changed[0]
	await native("religious_specialization_setup",{"unit_id":change.unit_id,"expected":change.before})
	if stopped:return
	var row: Dictionary=view.rows[0].duplicate(true)
	if not await wait_ui(func():return reader.ticket==0 and reader.receipt(row).get("eligible",false),"specialization lifecycle displayed facts"):return
	var point: Vector2=view.global_position+view.specialization_rect(0).get_center()
	await pointer_click(point)
	var ticket: int=flow.ticket
	if not check(ticket>0 and flow.phase==flow.Phase.Reading,"specialization pending fresh read missing"):return
	var mutated: bool=mode in ["sent","late","restart"]
	if mode=="receipt":
		await quantity_unobserved(ticket)
		if stopped:return
		var gate: Dictionary={"ticket":0}
		var disconnect:=func():
			if gate.ticket==0 and flow.phase==flow.Phase.Applying and flow.ticket>0:
				gate.ticket=flow.ticket;world.detach_live()
		flow.changed.connect(disconnect);actions.poll();flow.changed.disconnect(disconnect)
		ticket=int(gate.ticket)
		if not check(ticket>0,"specialization queued edit boundary absent"):return
	if mutated:
		await quantity_unobserved(ticket)
		if stopped:return
		actions.poll();ticket=flow.ticket
		if not check(ticket>0 and flow.phase==flow.Phase.Applying,"specialization pending edit missing"):return
		var reply:=await quantity_unobserved(ticket,false)
		if stopped:return
		if not check(reply.area.location_specialization.specialized==change.after.specialized,"specialization unobserved native effect missing"):return
	await native("religious_specialization_check",{"unit_id":change.unit_id,"expected":change.after if mutated else change.before})
	if stopped:return
	if mode=="late":
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not check(not editor.details_layer.visible and flow.owner.is_empty() and flow.target.is_empty(),"specialization dismissal retained owner"):return
		await quantity_lifecycle_choose(1)
		if stopped:return
		if not check(int(editor.details_state.identity.id)==1 and not flow.active and flow.owner.is_empty(),"specialization late success revived on other location"):return
	elif mode=="restart":
		await quantity_restart(ticket,"specialization")
		if stopped:return
		await quantity_lifecycle_open()
		if stopped:return
	else:
		world.detach_live();actions.poll()
		if not check(actions.result(ticket).get("outcome")==("unknown" if mutated else "not_sent"),"specialization disconnect outcome"):return
		if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active==0,"specialization remains dispatchable"):return
		if not check(flow.owner.is_empty() and flow.target.is_empty() and reader.owner.is_empty() and reader.rows.is_empty() and not editor.details_layer.visible,"specialization disconnect retained state"):return
		if not check(world.attach(),"specialization reconnect failed"):return
		var deadline:=Time.get_ticks_msec()+60000
		while Time.get_ticks_msec()<deadline:
			world.poll();actions.poll();editor._process(0.02)
			if world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)):break
			await create_timer(0.02).timeout
		if not check(bool(world.poll_management().get("transport_alive",false)),"specialization reconnect timeout"):return
		var next_ticket: int=actions._next_ticket
		for frame in 30:world.poll();actions.poll();editor._process(0.02);await process_frame
		if not check(actions._next_ticket==next_ticket and flow.owner.is_empty() and reader.owner.is_empty() and not editor.details_layer.visible,"specialization reconnect replayed or reopened"):return
		await native("religious_specialization_check",{"unit_id":change.unit_id,"expected":change.after if mutated else change.before})
		if stopped:return
		await quantity_lifecycle_open()
		if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"specialization fresh chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	var expected: bool=change.after.specialized if mutated and mode!="restart" else change.before.specialized
	if not await wait_ui(func():return reader.receipt(row).get("specialized")==expected,"specialization fresh observed state"):return
	if not check(not flow.active and flow.target.is_empty(),"specialization retired gesture revived"):return
	await capture("specialization_lifecycle_"+mode)
	write_json("specialization-lifecycle-evidence.json",{"mode":mode,"ticket":ticket,"mutated_before_retirement":mutated,"fresh_specialized":expected,"owner_retired":true,"no_replay":true})
	editor.close_panel()

func religious_assignment_retire(restart: bool, row_index: int, original_holder: int) -> void:
	step="religious assignment retire restart="+str(restart)
	var flow=editor.details_view.religious_assignment_workflow
	var selector=editor.details_view.staff_candidates_view
	var chosen: Dictionary=selector.rows[0].duplicate(true)
	await native("religious_guard")
	await pointer_click(selector.global_position+Vector2(80,54))
	await quantity_unobserved(flow.ticket)
	if stopped:return
	actions.poll()
	var ticket: int=flow.ticket
	if not check(ticket>0 and flow.mode==flow.Mode.Applying,"retirement assignment not pending"):return
	var reply:=await quantity_unobserved(ticket,false)
	if stopped:return
	if not check(int(reply.area.location_religious_staff.holder_id)==int(chosen.histfig_id),"retirement requires native assignment"):return
	await native("religious_assignment_applied",{"unit_id":chosen.unit_id,"histfig_id":chosen.histfig_id})
	if stopped:return
	if restart:
		await quantity_restart(ticket,"religious-assignment")
		if stopped:return
		if not check(flow.target.is_empty() and flow.owner.is_empty() and flow.selected.is_empty() and flow.ticket==0,"restart retained assignment authority"):return
		await quantity_lifecycle_open()
		if stopped:return
	else:
		await native("religious_guard")
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if not check(not editor.details_layer.visible and flow.target.is_empty() and flow.owner.is_empty(),"dismissal retained assignment owner"):return
		await quantity_lifecycle_choose(1)
		if stopped:return
		if not check(flow.target.is_empty() and flow.owner.is_empty() and flow.mode==flow.Mode.Closed and int(editor.details_state.identity.id)==1,"late assignment revived on another location"):return
		await native("religious_unchanged")
		await capture("religious_assignment_late_other_location")
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"retired assignment chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	var expected: int=original_holder if restart else int(chosen.histfig_id)
	var observed: Dictionary=editor.details_view.staff_view.rows[row_index]
	if not check(int(observed.histfig_id)==expected and flow.mode==flow.Mode.Closed,"fresh retired assignment holder differs"):return
	if restart:
		var restored:=await native("religious_setup")
		if not check(int(restored.holder_id)==original_holder,"restart preserved unsaved assignment"):return
	await capture("religious_assignment_retire_reopened")
	write_json("religious-assignment-retire-evidence.json",{"restart":restart,"old_ticket":ticket,"old_owner_retired":true,"applied_holder":chosen.histfig_id,"fresh_holder":observed.histfig_id})
	editor.close_panel()

func religious_assignment_disconnect(sent: bool, row_index: int, after_receipt:=false) -> void:
	step="religious assignment disconnect sent="+str(sent)+" after_receipt="+str(after_receipt)
	var flow=editor.details_view.religious_assignment_workflow
	var selector=editor.details_view.staff_candidates_view
	var chosen: Dictionary=selector.rows[0].duplicate(true)
	await native("religious_guard")
	await pointer_click(selector.global_position+Vector2(80,54))
	var ticket: int=flow.ticket
	if not check(ticket>0 and flow.mode==flow.Mode.Reading,"assignment pending read missing"):return
	if after_receipt:
		await quantity_unobserved(ticket)
		if stopped:return
		# Observe the real workflow enqueue, then lose transport before the same
		# service poll can dispatch the mutation. Do not replace native receipts.
		var gate: Dictionary={"ticket":0}
		var disconnect:=func():
			if gate.ticket==0 and flow.mode==flow.Mode.Applying and flow.ticket>0:
				gate.ticket=flow.ticket;world.detach_live()
		flow.changed.connect(disconnect)
		actions.poll()
		flow.changed.disconnect(disconnect)
		ticket=int(gate.ticket)
		if not check(ticket>0 and actions.result(ticket).get("outcome")=="not_sent","receipt boundary did not retire queued assignment"):return
	if sent:
		await quantity_unobserved(ticket)
		if stopped:return
		actions.poll()
		ticket=flow.ticket
		if not check(ticket>0 and flow.mode==flow.Mode.Applying,"assignment pending mutation missing"):return
		var reply:=await quantity_unobserved(ticket,false)
		if stopped:return
		if not check(int(reply.area.location_religious_staff.holder_id)==int(chosen.histfig_id),"unobserved assignment holder differs"):return
	world.detach_live();actions.poll()
	var outcome: Dictionary=actions.result(ticket)
	if not check(outcome.get("outcome")==("unknown" if sent else "not_sent"),"assignment disconnect outcome differs"):return
	if not check(flow.target.is_empty() and flow.owner.is_empty() and flow.selected.is_empty() and flow.ticket==0 and flow.mode in [flow.Mode.Closed,flow.Mode.Unavailable] and not editor.details_layer.visible,"disconnect retained assignment authority"):return
	if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active==0,"assignment remains dispatchable"):return
	await native("religious_assignment_applied" if sent else "religious_unchanged",{"unit_id":chosen.unit_id,"histfig_id":chosen.histfig_id})
	if stopped:return
	await native("religious_guard")
	if not check(world.attach(),"assignment reconnect failed"):return
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll();editor._process(0.02)
		if world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)):break
		await create_timer(0.02).timeout
	if not check(bool(world.poll_management().get("transport_alive",false)),"assignment reconnect timeout"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();editor._process(0.02);await process_frame
	if not check(actions._next_ticket==next_ticket and flow.target.is_empty() and flow.owner.is_empty() and not editor.details_layer.visible,"reconnect replayed or reopened assignment"):return
	await native("religious_unchanged")
	await quantity_lifecycle_open()
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"assignment fresh chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	var observed: Dictionary=editor.details_view.staff_view.rows[row_index]
	if not check(int(observed.histfig_id)==(int(chosen.histfig_id) if sent else -1) and flow.mode==flow.Mode.Closed,"fresh assignment holder differs"):return
	if not sent:
		var staff=editor.details_view.staff_view
		await pointer_click(staff.global_position+Vector2(208,(int(staff.geometry.first_y)-6+(row_index-staff.first)*3)*12+18))
		if not await wait_ui(func():return selector.is_visible_in_tree() and selector.actions_enabled,"fresh assignment gesture after reconnect"):return
		await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	await capture("religious_assignment_disconnect_reopened")
	write_json("religious-assignment-disconnect-evidence.json",{"sent":sent,"after_receipt":after_receipt,"outcome":outcome.outcome,"no_replay":true,"fresh_holder":observed.histfig_id,"target_retired":true})
	editor.close_panel()

func religious_staff_disconnect(sent: bool, point: Vector2, holder: int, row_index: int) -> void:
	step="religious staff disconnect sent="+str(sent)
	var flow=editor.details_view.religious_staff_workflow
	await native("religious_guard")
	await pointer_click(point)
	var ticket: int=flow.ticket
	if not check(ticket>0 and flow.phase==flow.Phase.Reading,"religious pending read missing"):return
	if sent:
		await quantity_unobserved(ticket)
		if stopped:return
		actions.poll() # Receives the read and dispatches exactly one mutation.
		ticket=flow.ticket
		if not check(ticket>0 and flow.phase==flow.Phase.Applying,"religious pending mutation missing"):return
		var reply:=await quantity_unobserved(ticket,false)
		if stopped:return
		if not check(not reply.area.location_religious_staff.removable and reply.area.location_religious_staff.holder_id==-1,"unobserved religious removal missing"):return
	world.detach_live();actions.poll()
	var outcome: Dictionary=actions.result(ticket)
	if not check(outcome.get("outcome")==("unknown" if sent else "not_sent"),"religious disconnect outcome differs"):return
	if not check(flow.target.is_empty() and flow.owner.is_empty() and flow.ticket==0 and not flow.active and not editor.details_layer.visible,"disconnect retained religious authority"):return
	if not check(not actions._requests.has(ticket) and actions._queue.is_empty() and actions._active==0,"religious request remains dispatchable"):return
	await native("religious_applied" if sent else "religious_unchanged")
	if stopped:return
	await native("religious_guard")
	if not check(world.attach(),"religious reconnect failed"):return
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll();editor._process(0.02)
		if world.terrain_loaded() and bool(world.poll_management().get("transport_alive",false)):break
		await create_timer(0.02).timeout
	if not check(bool(world.poll_management().get("transport_alive",false)),"religious reconnect timeout"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();editor._process(0.02);await process_frame
	if not check(actions._next_ticket==next_ticket and flow.target.is_empty() and flow.owner.is_empty() and not editor.details_layer.visible,"reconnect replayed or reopened religious action"):return
	await native("religious_unchanged")
	await capture("religious_disconnect_retired")
	await quantity_lifecycle_open()
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"religious fresh chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	var observed: Dictionary=editor.details_view.staff_view.rows[row_index]
	if not check(int(observed.histfig_id)==(-1 if sent else holder) and not flow.active,"fresh religious holder differs"):return
	await capture("religious_disconnect_reopened")
	write_json("religious-disconnect-evidence.json",{"sent":sent,"outcome":outcome.outcome,"no_replay":true,"fresh_holder":observed.histfig_id,"target_retired":true})
	editor.close_panel()

func religious_staff_late(point: Vector2, row_index: int) -> void:
	step="religious staff late completion"
	var flow=editor.details_view.religious_staff_workflow
	await native("religious_guard")
	await pointer_click(point)
	await quantity_unobserved(flow.ticket)
	if stopped:return
	actions.poll()
	var ticket: int=flow.ticket
	if not check(ticket>0 and flow.phase==flow.Phase.Applying,"late religious mutation missing"):return
	await quantity_unobserved(ticket,false)
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not check(not editor.details_layer.visible and flow.target.is_empty() and flow.owner.is_empty(),"dismissal retained religious owner"):return
	await quantity_lifecycle_choose(1)
	if stopped:return
	if not check(flow.target.is_empty() and flow.owner.is_empty() and not flow.active and int(editor.details_state.identity.id)==1,"late religious reply revived on another location"):return
	await native("religious_applied")
	if stopped:return
	await capture("religious_late_other_location")
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"religious late chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	if not check(int(editor.details_view.staff_view.rows[row_index].histfig_id)==-1 and not flow.active,"fresh religious observation missed removal"):return
	write_json("religious-late-evidence.json",{"old_ticket":ticket,"other_location":1,"old_owner_retired":true,"fresh_holder":-1})
	editor.close_panel()

func religious_staff_restart(point: Vector2, holder: int, row_index: int) -> void:
	step="religious staff producer restart"
	var flow=editor.details_view.religious_staff_workflow
	await native("religious_guard")
	await pointer_click(point)
	await quantity_unobserved(flow.ticket)
	if stopped:return
	actions.poll()
	var ticket: int=flow.ticket
	if not check(ticket>0 and flow.phase==flow.Phase.Applying,"restart religious mutation missing"):return
	var reply:=await quantity_unobserved(ticket,false)
	if stopped:return
	if not check(reply.area.location_religious_staff.holder_id==-1,"restart requires completed removal"):return
	await native("religious_applied")
	if stopped:return
	await quantity_restart(ticket,"religious")
	if stopped:return
	if not check(flow.target.is_empty() and flow.owner.is_empty() and flow.ticket==0 and not flow.active,"restart retained religious authority"):return
	await quantity_lifecycle_open()
	if stopped:return
	await pointer_click(Vector2(20,20),MOUSE_BUTTON_RIGHT)
	if not await wait_ui(func():return editor.details_origin.is_empty() and not editor.locations_state.busy(),"replacement religious chooser"):return
	await quantity_lifecycle_choose(0)
	if stopped:return
	var observed: Dictionary=editor.details_view.staff_view.rows[row_index]
	if not check(int(observed.histfig_id)==holder and not flow.active,"replacement retained unsaved removal or replayed it"):return
	var restored:=await native("religious_setup")
	if stopped:return
	if not check(int(restored.holder_id)==holder,"replacement native holder differs"):return
	await capture("religious_restart_reopened")
	write_json("religious-restart-evidence.json",{"old_ticket":ticket,"old_owner_retired":true,"old_applied_holder":-1,"fresh_holder":observed.histfig_id})
	editor.close_panel()
