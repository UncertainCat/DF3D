extends "res://tests/areas_controller_scene_live.gd"
# Actual fortress scene, viewport-routed location controls and native game readback.
# Raw zone creation/deletion below is fixture setup/cleanup, not workflow acceptance.
var candidate_portrait_audited := false
var details_parent_checked: Dictionary={}
var details_staff_count:=0
var quantity_cases:=0
func pointer_areas() -> void:
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
	write_json("naming-scene-evidence.json",{"locations":cases,"mutations":cases*5+1,"pending_close_cases":2,"assigned_routes":cases,"scope":"chooser and assigned quill entry, full choices, four edit modes and native readback, Done refresh, reopen/Escape/Back, queued cancellation and sent late receipt after dismissal"})
	print("LOCATION_NAMING_SCENE_PASS locations=",cases)
	editor.close_panel()

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

func quantity_unobserved(ticket: int) -> Dictionary:
	actions.poll()
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

func quantity_restart(ticket: int) -> void:
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
	write_json("quantity-lifecycle-outcome.json",outcome)
	write_json("quantity-restart.json",{"old_epoch":str(old_epoch),"new_epoch":str(epoch),"old_generation":old_generation,"new_generation":world.session_generation(),"pid":ack.pid})
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
	write_json("quantity-restart-new-requests.json",new_requests)
	for item in new_requests.values():
		if not check(item.domain!="areas" or int(item.request.get("operation",-1)) not in [Contract.AreaOperation.LocationQuantity,Contract.AreaOperation.LocationOpen,Contract.AreaOperation.LocationDetails],"replacement automatically submitted Location work"):return
	if not check(model.identity.is_empty() and not editor.details_layer.visible,"replacement reopened quantity editor"):return
	await capture("quantity_restart_retired")
