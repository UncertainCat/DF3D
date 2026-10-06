extends "res://tests/areas_acceptance_live.gd"
# Actual controller/buttons + action service + live bridge. Headless coverage;
# pointer routing and GPU parity require the separate rendered main-scene lane.
var editor
var actions
var host
var interaction
var camera
var receipts: Array = []

func wait_ui(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	while not stopped and Time.get_ticks_msec() < deadline:
		world.poll(); actions.poll(); editor._process(0.02)
		if predicate.call(): return check(not editor.request_problem,label+": "+editor.message.text)
		await create_timer(0.02).timeout
	return check(false,label+" timed out; no command replay")

func settled() -> bool:
	return editor.request_ticket == 0

func exercise() -> void:
	step = "controller setup"
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	if not check(fixture.has("origin"),"no native fixture footprint"): return
	if not check(world.load_assets(FileAccess.get_file_as_string(directory+"/df-path.txt")),"installed assets unavailable"): return
	var p: Dictionary = fixture.origin
	var origin := Vector3i(int(p.x),int(p.y),int(p.z))
	world.set_top_z(origin.z)
	interaction = preload("res://tests/areas_test.gd").FakeInteraction.new(); root.add_child(interaction)
	host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	actions = preload("res://scripts/semantic_action_service.gd").new(); actions.configure(world); root.add_child(actions); actions.set_process(false)
	actions.completed.connect(func(ticket,result):
		receipts.append(result.duplicate(true))
		print("AREA_CONTROLLER_RECEIPT ",ticket," action=",result.get("action")," status=",result.get("status")," ",result.get("message")))
	editor = preload("res://scripts/areas.gd").new()
	editor.world = world; editor.action_service = actions; editor.ui_host = host; editor.interaction = interaction
	camera = Camera3D.new(); root.add_child(camera); editor.camera = camera
	root.add_child(editor); host.register(editor); editor.set_process(false)
	editor.open_panel()
	if await wait_ui(func(): return editor.available and settled(),"catalog"):
		await exercise_ui(origin)
	editor.close_panel(); editor.free(); camera.free(); actions.free(); host.free(); interaction.free()
	await process_frame
	if not stopped: await native("final")
	if not stopped: print("AREAS_CONTROLLER_LIVE_PASS")

func exercise_ui(origin: Vector3i) -> void:
	step = "controller cancel draft"
	await native("guard_before")
	editor.paint_pointer(origin,true); editor.paint_pointer(origin+Vector3i(1,1,0),false)
	editor.handle_back()
	if not check(editor.paint_state.cells.is_empty(),"cancel retained local footprint"): return
	await native("guard_after")
	step = "controller stockpile create"
	editor.paint_pointer(origin,true); editor.paint_pointer(origin+Vector3i(1,1,0),false)
	editor.paint_view.accept_button.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"create stockpile"): return
	var pile := int(editor.selected.id)
	await native("snapshot",{"id":pile,"expected":{"kind":0,"tile_count":4}})
	editor.stockpile_view.controls.rename.pressed.emit()
	editor.rename_field.text_submitted.emit("Controller stockpile")
	if not await wait_ui(settled,"rename"): return
	await native("snapshot",{"id":pile,"expected":{"custom_name":"Controller stockpile"}})
	editor.stockpile_view.controls.links_only.pressed.emit()
	if not await wait_ui(settled,"links only"): return
	await native("snapshot",{"id":pile,"expected":{"links_only":true}})
	await stockpile_selectors(pile)
	if stopped: return
	await controller_workshop_links(pile)
	if stopped: return
	await controller_stockpile_links(pile,origin)
	if stopped: return
	step = "controller mixed repaint"
	editor.stockpile_view.controls.repaint.pressed.emit()
	editor.paint_pointer(origin+Vector3i(0,2,0),true); editor.paint_pointer(origin+Vector3i(1,2,0),false)
	editor.paint_view.buttons.erase.pressed.emit()
	editor.paint_pointer(origin,true); editor.paint_pointer(origin,false)
	editor.paint_pointer(origin,true); editor.paint_pointer(origin,false)
	var before := receipts.size()
	editor.paint_view.accept_button.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.mode == "inspect","repaint"): return
	if not check(receipts.size() == before+1,"one accepted repaint emitted multiple bridge requests"): return
	await native("snapshot",{"id":pile,"expected":{"tile_count":5}})
	editor.stockpile_view.controls.remove.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"remove stockpile"): return
	await native("removed",{"id":pile})
	step = "controller retired native target"
	var stale_origin := origin+Vector3i(4,4,0)
	editor.paint_pointer(stale_origin,true); editor.paint_pointer(stale_origin,false)
	editor.paint_pointer(stale_origin,true); editor.paint_pointer(stale_origin,false)
	editor.paint_view.accept_button.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"stale fixture create"): return
	var stale_id := int(editor.selected.id)
	await native("remove_target",{"id":stale_id})
	if stopped: return
	editor.stockpile_view.controls.links_only.pressed.emit()
	var deadline := Time.get_ticks_msec()+30000
	while editor.request_ticket != 0 and Time.get_ticks_msec()<deadline:
		world.poll(); actions.poll(); editor._process(0.02); await create_timer(0.02).timeout
	if not check(editor.request_ticket == 0 and editor.selected.is_empty() and not editor.available
		and editor.message.text.get_slice("\n",0) == "Area no longer exists","retired target remained armed or hid rejection"): return
	await native("removed",{"id":stale_id})
	step = "controller native zone overlap navigation"
	editor.close_panel(); editor.set_area_kind(1); editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"zone catalog"): return
	editor.inspect_tile(origin+Vector3i(21,0,0))
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"overlap lookup"): return
	if not check(editor.zone_overlaps.size() == fixture.zones.size(),"overlap lookup omitted fixture zones"): return
	var seen := {}
	for index in fixture.zones.size():
		seen[int(editor.selected.id)] = true
		if not check(editor.zone_menu.visible and int(editor.selected.revision)>0,"zone type lacks inspected native panel"): return
		editor.zone_menu.controls.previous.pressed.emit()
		if not await wait_ui(settled,"previous zone"): return
	for id in fixture.zones.values():
		if not check(seen.has(int(id)),"native arrows skipped observed zone"): return
	await assignment_selectors()
	if stopped: return
	await zone_setting_controls()
	if stopped: return
	step = "controller new bedroom and owner"
	editor.zone_menu.buttons.Bedroom.pressed.emit()
	var bed_origin := origin+Vector3i(8,8,0)
	editor.paint_pointer(bed_origin,true); editor.paint_pointer(bed_origin,false)
	editor.paint_pointer(bed_origin+Vector3i(1,1,0),true); editor.paint_pointer(bed_origin+Vector3i(1,1,0),false)
	editor.paint_view.accept_button.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"create bedroom"): return
	var bedroom := int(editor.selected.id)
	await native("snapshot",{"id":bedroom,"expected":{"kind":1,"tile_count":4}})
	editor.zone_menu.controls.owner.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner candidates"): return
	var owner := int(fixture.owner)
	var found := false
	while not stopped:
		for index in editor.candidates_state.rows.size():
			if int(editor.candidates_state.rows[index].id) == owner:
				editor.candidates_view.choices[index].pressed.emit(); found = true; break
		if found or editor.candidates_state.cursor == 0: break
		editor.candidates_state.more()
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner page"): return
	if not check(found,"fixture owner absent from native candidates"): return
	if not await wait_ui(func(): return settled() and editor.stockpile_page == "types","owner assignment"): return
	await native("snapshot",{"id":bedroom,"expected":{"owner_id":owner}})
	await location_selector(bedroom)
	if stopped: return
	editor.zone_menu.controls.suspend.pressed.emit()
	if not await wait_ui(settled,"suspend"): return
	await native("snapshot",{"id":bedroom,"expected":{"active":false}})
	editor.zone_menu.controls.remove.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"remove bedroom"): return
	await native("removed",{"id":bedroom})

func stockpile_selectors(pile: int) -> void:
	step = "controller presets and storage"
	var retained := {"barrels":int(editor.selected.barrels),"bins":int(editor.selected.bins),
		"wheelbarrows":int(editor.selected.wheelbarrows),"links_only":bool(editor.selected.links_only)}
	for index in editor.menu_data.presets.size():
		if int(editor.menu_data.presets[index].preset) == 15:
			editor.stockpile_view.preset_buttons[index].pressed.emit(); break
	if not await wait_ui(settled,"Wood preset"): return
	await native("preset",{"id":pile,"preset":15,"category":"wood","retained":retained})
	editor.stockpile_view.controls.containers.pressed.emit()
	for key in ["barrels","bins","wheelbarrows"]:
		editor.storage_view.controls[key][0].pressed.emit()
		editor.storage_view.entry.text_submitted.emit("2" if key == "barrels" else "1")
		if not await wait_ui(settled,"storage "+key): return
	await native("snapshot",{"id":pile,"expected":{"barrels":2,"bins":1,"wheelbarrows":1}})
	editor.storage_view.controls.barrels[1].pressed.emit()
	if not await wait_ui(settled,"increase barrels"): return
	editor.storage_view.controls.barrels[2].pressed.emit()
	if not await wait_ui(settled,"decrease barrels"): return
	await native("snapshot",{"id":pile,"expected":{"barrels":2}})
	editor.storage_view.done.emit()
	step = "controller custom settings"
	for index in editor.menu_data.presets.size():
		if int(editor.menu_data.presets[index].preset) == 0:
			editor.stockpile_view.preset_buttons[index].pressed.emit(); break
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Custom settings"): return
	var found := false
	for index in editor.settings_state.rows[0].size():
		if str(editor.settings_state.rows[0][index].key) == "wood":
			editor.settings_view.rendered_rows[0][index].pressed.emit(); found = true; break
	if not check(found,"observed Wood category absent"): return
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"wood leaves"): return
	if not check(not editor.settings_state.rows[2].is_empty() and editor.settings_state.rows[1].is_empty(),"Wood leaves must occupy native third column"): return
	var row: Dictionary = editor.settings_state.rows[2][0]
	var value := 1 if int(row.state) == 2 else 2
	editor.settings_view.rendered_rows[2][0].pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"wood leaf edit"): return
	await native("wood",{"id":pile,"row_key":str(row.key),"value":value})
	for state in [1,2]:
		editor.settings_view.headers[5 if state == 1 else 4].pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"wood header edit"): return
		await native("wood",{"id":pile,"value":state})
	editor.handle_back()

func location_selector(bedroom: int) -> void:
	step = "controller location assignment"
	editor.zone_menu.controls.location.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations"): return
	var found := false
	while not stopped:
		for index in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[index].id) == int(fixture.tavern):
				editor.locations_view.choices[index].pressed.emit(); found = true; break
		if found or editor.locations_state.cursor == 0: break
		editor.locations_state.more()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"location page"): return
	if not check(found,"fixture tavern absent from location list"): return
	if not await wait_ui(func(): return settled() and editor.stockpile_page == "types","assign location"): return
	await native("location",{"id":bedroom,"location_id":int(fixture.tavern),"location_kind":int(editor.selected.location_kind)})
	editor.zone_menu.controls.location.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations to create"): return
	editor.locations_view.create_buttons[2].pressed.emit()
	if not await wait_ui(func(): return settled() and editor.stockpile_page == "types","create library"): return
	if not check(int(editor.selected.location_kind) == 3,"created library type missing from zone summary"): return
	await native("location",{"id":bedroom,"location_id":int(editor.selected.location_id),"location_kind":3})
	editor.zone_menu.controls.location.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations to cancel removal"): return
	await native("guard_before")
	editor.locations_view.remove.pressed.emit()
	var ticket := int(editor.request_ticket)
	editor.handle_back(); actions.poll()
	if not check(actions.result(ticket).get("outcome","") == "not_sent","Back failed to cancel queued location removal"): return
	await native("guard_after")
	editor.zone_menu.controls.location.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations to remove"): return
	editor.locations_view.remove.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.stockpile_page == "types","remove location assignment"): return
	await native("location",{"id":bedroom,"location_id":-1,"location_kind":0})

func controller_workshop_links(pile: int) -> void:
	step = "controller workshop links"
	if not check(fixture.has("workshop_origin"),"fixture lacks observed workshop position"): return
	var position: Dictionary = fixture.workshop_origin
	var tile := Vector3i(int(position.x),int(position.y),int(position.z))
	editor.stockpile_view.controls.links.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"links list"): return
	for give in [true,false]:
		editor.links_view.add_buttons[0 if give else 1].pressed.emit()
		if not check(editor.links_picking,"link button did not enter map selection"): return
		editor.link_target_tile(tile)
		if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"workshop link"): return
		await native("link",{"id":int(fixture.workshop),"pile_id":pile,"give":not give,"linked":true})
		var found := false
		for index in editor.observed_links.size():
			var row: Dictionary = editor.observed_links[index]
			if int(row.id) == int(fixture.workshop) and int(row.kind) == 2 and int(row.direction) == (1 if give else 2):
				editor.links_view.rows_box.get_child(index).get_child(2).pressed.emit()
				found = true; break
		if not check(found,"workshop link row missing or direction reversed"): return
		if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"remove workshop link"): return
		await native("link",{"id":int(fixture.workshop),"pile_id":pile,"give":not give,"linked":false})
	editor.links_view.close.pressed.emit()
	if not check(editor.stockpile_page == "types","links Done did not return to stockpile"): return


func select_fixture_zone(name: String) -> bool:
	var id := int(fixture.zones[name])
	for index in editor.zone_overlaps.size():
		if int(editor.selected.get("id",-1)) == id: return true
		editor.zone_menu.controls.previous.pressed.emit()
		if not await wait_ui(settled,"select "+name): return false
	return check(false,"observed zone missing: "+name)

func candidate_index(id: int) -> int:
	while not stopped:
		for index in editor.candidates_state.rows.size():
			if int(editor.candidates_state.rows[index].id) == id: return index
		if editor.candidates_state.cursor == 0: break
		editor.candidates_state.more()
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"candidate page"): return -1
	check(false,"fixture candidate absent: "+str(id))
	return -1

func assignment_selectors() -> void:
	step = "controller animal assignments"
	if not await select_fixture_zone("Pen"): return
	var pen := int(editor.selected.id)
	editor.zone_menu.controls.animals.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"animal candidates"): return
	for header in editor.candidates_view.headers:
		for reverse in 2:
			header.pressed.emit()
			if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"animal sort"): return
			await verify_candidate_rows(pen,2)
			if stopped: return
	for key in ["grazer","caged"]:
		var unit := int(fixture[key])
		editor.candidates_view.search.text = str(unit)
		editor.candidates_view.search.text_changed.emit(str(unit))
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"animal search"): return
		await verify_candidate_rows(pen,2)
		if stopped: return
		await native("assignment_before",{"unit_id":unit})
		for assigned in [true,false]:
			var index := await candidate_index(unit)
			if index < 0: return
			if not check(bool(editor.candidates_state.rows[index].assigned) != assigned,"animal assignment did not refresh"): return
			editor.candidates_view.choices[index].pressed.emit()
			if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"animal assignment"): return
			if not check(editor.stockpile_page == "animals","animal edit lost selector"): return
			if not check(editor.candidates_state.query == str(unit) and editor.candidates_view.search.text == str(unit)
				and editor.candidates_state.sort == 3 and editor.candidates_state.descending,"animal edit lost search/sort"): return
			await verify_candidate_rows(pen,2)
			if stopped: return
			await native("assignment",{"id":pen,"unit_id":unit,"assign":assigned})
			if stopped: return
	editor.handle_back()
	step = "controller squad room use"
	if not await select_fixture_zone("Barracks"): return
	var barracks := int(editor.selected.id)
	var squad := int(fixture.squad)
	editor.zone_menu.controls.squads.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"squad candidates"): return
	var expected := 0
	for bit_index in [0,1,2,3,0,1,2,3]:
		var index := await candidate_index(squad)
		if index < 0: return
		if not check(int(editor.candidates_state.rows[index].squad_use) == expected,"squad controls have stale use"): return
		editor.candidates_view.squad_buttons[index*4+bit_index].pressed.emit()
		expected = expected ^ (1 << bit_index)
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"squad room use"): return
		if not check(editor.stockpile_page == "squads" and editor.candidates_state.squad_mask == 15,"squad edit lost selector mode"): return
		await native("squad",{"id":barracks,"squad_id":squad,"use":expected})
		if stopped: return
	editor.handle_back()

func zone_setting_controls() -> void:
	step = "controller native zone settings"
	for name in ["Pond","Tomb","PlantGathering","ArcheryRange"]:
		if not await select_fixture_zone(name): return
		var id := int(editor.selected.id)
		for index in editor.zone_menu.SETTINGS.size():
			var entry: Array = editor.zone_menu.SETTINGS[index]
			if entry[0] != name: continue
			var button: Button = editor.zone_menu.setting_buttons[index]
			var key := str(entry[1])
			if key == "gather_fallen":
				if not check(button.disabled,"unobserved fallen-fruit setting must stay unavailable"): return
				continue
			if not check(button.visible and not button.disabled,"supported setting button unavailable: "+key): return
			var value := int(entry[2]) if int(entry[2]) >= 0 else 1-int(editor.selected.zone_settings[key])
			button.pressed.emit()
			if not await wait_ui(settled,"setting "+key): return
			await native("zone_settings",{"id":id,"expected":{key:value}})
			if stopped: return
	# Archery exposes only the native training bit, with reciprocal room effects.
	editor.zone_menu.controls.squads.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"archery squads"): return
	if not check(editor.candidates_state.squad_mask == 2,"archery must expose only Train"): return
	for use in [2,0]:
		var index := await candidate_index(int(fixture.squad))
		if index < 0: return
		editor.candidates_view.squad_buttons[index].pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"archery squad use"): return
		await native("squad",{"id":int(editor.selected.id),"squad_id":int(fixture.squad),"use":use})
		if stopped: return
	editor.handle_back()

func controller_stockpile_links(pile: int, origin: Vector3i) -> void:
	step = "controller stockpile links"
	var target := int(fixture.pile)
	editor.stockpile_view.controls.links.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"stockpile links list"): return
	await native("guard_before")
	editor.links_view.add_buttons[0].pressed.emit()
	editor.links_view.close.pressed.emit()
	if not check(not editor.links_picking and editor.stockpile_page == "links","cancel link selection lost links panel"): return
	await native("guard_after")
	for give in [true,false]:
		editor.links_view.add_buttons[0 if give else 1].pressed.emit()
		editor.link_target_tile(origin+Vector3i(21,21,0))
		if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"stockpile link"): return
		await native("pile_link",{"id":pile,"target_id":target,"give":give,"linked":true})
		var found := false
		for index in editor.observed_links.size():
			var row: Dictionary = editor.observed_links[index]
			if int(row.id) == target and int(row.kind) == 0 and int(row.direction) == (1 if give else 2):
				editor.links_view.rows_box.get_child(index).get_child(2).pressed.emit()
				found = true; break
		if not check(found,"stockpile link row missing or direction reversed"): return
		if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"remove stockpile link"): return
		await native("pile_link",{"id":pile,"target_id":target,"give":give,"linked":false})
	editor.links_view.close.pressed.emit()

func verify_candidate_rows(id: int, kind: int) -> void:
	while not stopped and editor.candidates_state.cursor != 0:
		editor.candidates_state.more()
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"complete candidates"): return
	await native("candidates",{"id":id,"kind":kind,"sort":editor.candidates_state.sort,
		"descending":editor.candidates_state.descending,"query":editor.candidates_state.query,
		"rows":editor.candidates_state.rows})
