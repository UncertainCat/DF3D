extends "res://tests/areas_controller_live.gd"
# Actual main-scene viewport input. Broad callback coverage lives in the parent.
var scene

func run() -> void:
	directory = OS.get_environment("DF3D_AREAS_ACCEPTANCE")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Use areas_acceptance.ps1 -ControllerScene on a protected clone")
		quit(77); return
	OS.set_environment("DF3D_DF_PATH",FileAccess.get_file_as_string(directory+"/df-path.txt"))
	OS.set_environment("DF3D_FIXTURE","")
	var preferences = preload("res://scripts/presentation_settings.gd")
	preferences.loaded = true; preferences.ui_scale = 1.0; preferences.camera_mode = "df"
	root.size = Vector2i(1200,800)
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	scene = load("res://scenes/main.tscn").instantiate(); root.add_child(scene)
	world = scene.world
	var deadline := Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
	if check(scene._loader.entered,"main scene did not enter fortress"):
		actions = scene._ui.actions; host = scene._ui.host; interaction = scene._interaction
		actions.set_process(false)
		actions.completed.connect(func(_ticket,result): receipts.append(result.duplicate(true)))
		editor = scene._ui.controller("areas"); editor.set_process(false)
		await pointer_areas()
	var status := "failed" if failed else ("incomplete" if not reasons.is_empty() else "passed")
	write_json("result.json",{"status":status,"reasons":reasons,"surface":"main scene GPU; viewport input and native readback","driver":get_script().resource_path})
	print("AREAS_CONTROLLER_SCENE ",status)
	scene.queue_free(); await process_frame
	quit(1 if failed else (77 if status == "incomplete" else 0))

func pointer_click(position: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = position; motion.global_position = position
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.position = position; event.global_position = position
		event.button_index = button; event.pressed = pressed
		event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		root.push_input(event,true)
	await process_frame; await process_frame

func click_control(control: Control) -> void:
	# This driver disables automatic controller processing. Run layout as the
	# actual scene would before clicking controls after a mode transition.
	for frame in 2:
		editor._process(0); await process_frame
	await pointer_click(control.get_global_transform_with_canvas()*(control.size/2))

func capture(label: String) -> void:
	# Processing is manual in this driver; settle deferred font/container sizing.
	for frame in 4:
		editor._process(0); await process_frame
	await RenderingServer.frame_post_draw
	if editor.stockpile_view.visible:
		var clip: Rect2 = editor.content.get_parent().get_global_rect()
		if not check(clip.encloses(editor.stockpile_view.warning.get_global_rect()),"stockpile warning clipped: scroll="+str(clip)+" warning="+str(editor.stockpile_view.warning.get_global_rect())): return
		if not check(editor.panel.size.x == 324,"native stockpile panel width changed: "+str(editor.panel.size)+" minimum="+str(editor.panel.get_combined_minimum_size())): return
	check(root.get_texture().get_image().save_png(directory+"/scene_"+label+".png") == OK,"capture failed")

func pointer_areas() -> void:
	var p: Dictionary = fixture.origin
	var origin := Vector3i(int(p.x)+8,int(p.y)+8,int(p.z))
	world.set_top_z(origin.z)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	for destination in ["Stockpiles","Zones"]:
		step = "viewport "+destination
		var launcher: Button = scene._fortress_hud.navigation[destination]
		for frame in 12:
			launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
		# Candidate launchers are exposed only in this acceptance process.
		launcher.show(); await click_control(launcher)
		if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"pointer launcher"): return
		if destination == "Zones":
			await click_control(editor.zone_menu.buttons.Bedroom)
			if not check(editor.mode == "paint","zone button did not start painting"): return
		var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
		var position: Vector2 = editor.camera.unproject_position(target)
		var picked: Vector3i = world.pick_tile(editor.camera.project_ray_origin(position),editor.camera.project_ray_normal(position),world.get_top_z())
		if not check(picked == origin,"rendered picking disagrees with area fixture"): return
		await pointer_click(position)
		if not await wait_ui(func(): return settled() and not editor.paint_lookup,"pointer footprint lookup"): return
		if not check(editor.paint_state.cells.size() == 1,"pointer painting did not retain one tile"): return
		await elevation_round_trip(origin,destination+"_new")
		if stopped: return
		await capture(destination.to_lower()+"_draft")
		if stopped: return
		await click_control(editor.paint_view.accept_button)
		if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"pointer Accept"): return
		var id := int(editor.selected.id)
		await native("snapshot",{"id":id,"expected":{"kind":0 if destination == "Stockpiles" else 1,"tile_count":1}})
		if destination == "Zones":
			await native("snapshot",{"id":id,"expected":{"custom_name":""}})
			if not check(str(editor.selected.name) == "Unnamed bedroom" and editor.zone_menu.heading.text == "Unnamed bedroom","unnamed Bedroom must use native panel name"): return
		await capture(destination.to_lower()+"_created")
		if stopped: return
		if destination == "Zones": await pointer_owner(id,origin)
		else: await pointer_settings()
		if stopped: return
		await pointer_repaint(origin,id,destination)
		if stopped: return
		await click_control(editor.stockpile_view.controls.repaint if destination == "Stockpiles" else editor.zone_menu.controls.repaint)
		await click_control(editor.paint_view.buttons.remove)
		if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"pointer Remove"): return
		await native("removed",{"id":id})
		editor.close_panel()
	await pointer_zone_boundary_cells()
	if stopped: return
	await native("final")
	if not stopped: print("AREAS_POINTER_PASS")

func pointer_settings() -> void:
	step = "viewport stockpile settings categories"
	await native("category_before",{"id":int(editor.selected.id)})
	var custom := -1
	for index in editor.menu_data.presets.size():
		if int(editor.menu_data.presets[index].preset) == 0: custom = index
	if not check(custom >= 0,"Custom preset is missing"): return
	await click_control(editor.stockpile_view.preset_buttons[custom])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"settings initial columns"): return
	await native("category_after",{"id":int(editor.selected.id),"category":"ammo"})
	if not check(editor.settings_state.category == "ammo" and editor.settings_state.leaf == "ammo/type","initial Custom did not open Ammo/Type"): return
	var captured: Array = []
	for definition in editor.menu_data.categories:
		var category: String = definition.key
		var index := -1
		var visible_index := 0
		for row in editor.settings_state.rows[0]:
			if int(row.kind) != 1: continue
			if str(row.key) == category: index = visible_index
			visible_index += 1
		if not check(index >= 0,"Missing observed settings category: "+category): return
		var button: Control = editor.settings_view.rendered_rows[0][index]
		editor.settings_view.scrolls[0].ensure_control_visible(button)
		await native("category_before",{"id":int(editor.selected.id)})
		await click_control(button)
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"settings category "+category): return
		await native("category_after",{"id":int(editor.selected.id),"category":category})
		await native("guard_before")
		if not check(editor.settings_state.category == category,"Pointer selected wrong settings category: "+category): return
		for column in editor.settings_state.rows:
			for row in column:
				if not check(not bool(row.get("estimated",false)) and not "DF3D estimate" in str(row.label),"Settings exposed an estimated state or authored disclaimer"): return
		if category == "animals":
			if not check(editor.settings_state.leaf == "animals/animals" and not editor.settings_state.rows[2].is_empty(),"Animals lost its native creature list"): return
			if not check(editor.settings_state.rows[1].size() == 2,"Animals lost its cage options"): return
		if category == "ammo":
			var labels: Array = []
			for row in editor.settings_state.rows[1]: labels.append(str(row.label))
			if not check(labels == ["Type","Metal","Other materials","Core quality","Total quality"],"Ammo middle column differs from native"): return
			if not check(editor.settings_state.leaf == "ammo/type" and not editor.settings_state.rows[2].is_empty(),"Ammo Type list did not open"): return
			if not check(editor.settings_view.headers[2].visible and editor.settings_view.headers[3].visible,"Ammo middle-column All/None controls are hidden"): return
			var keys: Array = ["ammo/type","ammo/metal","ammo/other_materials","ammo/quality_core","ammo/quality_total"]
			for column_index in keys.size():
				await click_control(editor.settings_view.columns[1].get_child(column_index).get_child(0))
				if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Ammo native sublist"): return
				if not check(editor.settings_state.leaf == keys[column_index] and not editor.settings_state.rows[2].is_empty(),"Ammo sublist failed: "+keys[column_index]): return
				if column_index >= 3:
					if not check(settings_captions() == ["Standard","Well-crafted","Finely-crafted","Superior quality","Exceptional","Masterwork","Artifact"],"Native quality captions or grade order differ"): return
				await capture("settings_ammo_"+str(column_index))
			await click_control(editor.settings_view.columns[1].get_child(0).get_child(0))
			if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Ammo Type return"): return
		if category in ["cloth","sheet","gems"]:
			if not check(not editor.settings_state.rows[2].is_empty(),"Missing caption evidence rows: "+category): return
			var caption: String = editor.settings_state.rows[2][0].label
			if category == "cloth" and not check(caption.ends_with(" thread"),"Silk-thread caption omitted product noun"): return
			if category == "sheet" and not check(caption.ends_with(" sheet"),"Paper caption omitted product noun"): return
			if category == "gems":
				write_json("rough-gem-captions.json",editor.settings_state.rows[2])
				if not check(caption.to_lower() == "alexandrites","Rough-gem caption differs from captured native plural: "+caption): return
		if category in ["coins","corpses","wood"]:
			if not check(editor.settings_state.rows[1].is_empty(),"Direct category fabricated a middle column: "+category): return
		if category in ["finished_goods","refuse"]:
			var expected: Array = ["amulets","armor","backpacks","bracelets","chains","codices"] if category == "finished_goods" else ["ammunition","amulets","animal traps","anvils","armor","armor stands"]
			var actual: Array = []
			for row in editor.settings_state.rows[2].slice(0,expected.size()): actual.append(str(row.label).to_lower())
			if not check(actual == expected,"Native item captions/order differ in "+category+": "+str(actual)): return
		if category == "refuse":
			# Complete native1928 Refuse/Item types list, including independent hide flags.
			var expected: Array = ["Ammunition","Amulets","Animal traps","Anvils","Armor","Armor stands","Backpacks","Bags","Ballista arrow heads","Ballista parts","Barrels","Beds","Bins","Bolt thrower parts","Boxes","Bracelets","Buckets","Cabinets","Cages","Catapult parts","Chains","Cheese","Cloth","Codices","Coffins","Coins","Crowns","Crutches","Doors","Drinks","Earrings","Egg","Figurines","Fish","Flasks","Floodgates","Footwear","Fresh raw hide","Glob","Goblets","Grates","Handwear","Hatch covers","Headwear","Large gems","Leaves and fruit","Legwear","Liquid","Logs","Meat","Mechanisms","Millstones","Musical instruments","Pipe section","Plants","Powder","Prepared meals","Querns","Quivers","Raw fish","Remains","Rings","Rotten raw hide","Scepters","Seeds","Sheet","Shields/bucklers","Siege ammo","Slabs","Small live animals","Small tame animals","Splints","Statues","Tables","Tanned hides","Thread","Thrones","Tools","Totems","Toys","Traction benches","Trap components","Weapon racks","Weapons","Windows"]
			if not check(settings_captions() == expected,"Native Refuse membership/captions/order differ"): return
		if category in ["finished_goods","furniture"]:
			var expected: Array = ["amulets","armor","backpacks","bracelets","chains","codices","crowns","crutches","earrings","figurines","flasks","footwear","goblets","handwear","headwear","large gems","legwear","musical instruments","quivers","rings","scepters","splints","tools","totems","toys"] if category == "finished_goods" else ["anvils","armor stands","bags","ballista arrow heads","ballista parts","barrels","beds","bins","bolt thrower parts","boxes","buckets","cabinets","catapult parts","coffins","doors","floodgates","grates","hatch covers","large pots/food storage","mechanisms","millstones","minecarts","other large tools","pipe section","querns","sand bags","siege ammo","slabs","statues","tables","thrones","traction benches","weapon racks","wheelbarrows","windows"]
			var actual: Array = []
			for row in editor.settings_state.rows[2]: actual.append(str(row.label).to_lower())
			if not check(actual == expected,"Complete native type list differs in "+category+": "+str(actual)): return
		await caption_sublists(category)
		if stopped: return
		await capture("settings_"+category)
		if stopped: return
		captured.append({"category":category,"rows":editor.settings_state.rows.duplicate(true),"leaf":editor.settings_state.leaf})
		await native("guard_after")
	write_json("settings-captures.json",captured)
	await pointer_filtered_settings()
	if stopped: return
	await pointer_refuse_hides()
	if stopped: return
	await pointer_settings_scroll_refresh()
	if stopped: return
	step = "viewport global None preserves flags and resets sublist"
	for organic in [true,false]:
		await click_control(editor.settings_view.rendered_rows[0][2])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Armor selection for global None"): return
		await click_control(editor.settings_view.rendered_rows[1][8])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Armor core quality before global None"): return
		if not check(editor.settings_state.leaf == "armor/quality_core","global None test did not select Armor core quality"): return
		await replace_settings_search("armor")
		if stopped: return
		var previous_revision := int(editor.selected.revision)
		await native("global_none_prepare",{"id":int(editor.selected.id),"organic":organic})
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and int(editor.selected.revision) != previous_revision,"mixed native flag fixture"): return
		await click_control(editor.settings_view.headers[1])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"native global None"): return
		await native("global_none_verify",{"id":int(editor.selected.id)})
		if stopped: return
		if not check(editor.settings_state.category == "armor" and editor.settings_state.leaf == "armor/body","global None did not return Armor to Body"): return
		if not check(editor.settings_state.query == "ARMOR" and editor.settings_view.search.text == "ARMOR","global None lost native search"): return
		for row in editor.settings_state.rows[0]:
			if int(row.kind) == 1 and not check(int(row.state) == 1,"global None left an enabled category summary"): return
		await capture("global_none" if organic else "global_none_reverse")
	step = "viewport global All preserves Refuse and Corpses"
	for enabled in [false,true]:
		await click_control(editor.settings_view.rendered_rows[1][8])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Armor core quality before global All"): return
		var previous_revision := int(editor.selected.revision)
		await native("global_all_prepare",{"id":int(editor.selected.id),"enabled":enabled})
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and int(editor.selected.revision) != previous_revision,"excluded category fixture"): return
		await click_control(editor.settings_view.headers[0])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"native global All"): return
		await native("global_all_verify",{"id":int(editor.selected.id)})
		if stopped: return
		if not check(editor.settings_state.category == "armor" and editor.settings_state.leaf == "armor/body","global All did not return Armor to Body"): return
		if not check(editor.settings_state.query == "ARMOR" and editor.settings_view.search.text == "ARMOR","global All lost native search"): return
		await capture("global_all_enabled" if enabled else "global_all_disabled")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape)
	if not check(editor.stockpile_page == "types","Escape did not return from settings to stockpile"): return
	# This driver disables automatic controller processing. Apply the smaller
	# panel layout before subsequent viewport painting, as a normal frame does.
	editor._process(0)
	await process_frame; await process_frame

func replace_settings_search(value: String) -> void:
	await click_control(editor.settings_view.search)
	var select_all := InputEventKey.new(); select_all.keycode = KEY_A; select_all.ctrl_pressed = true; select_all.pressed = true
	root.push_input(select_all,true)
	var erase := InputEventKey.new(); erase.keycode = KEY_BACKSPACE; erase.pressed = true
	root.push_input(erase,true)
	for letter in value:
		var event := InputEventKey.new(); event.unicode = letter.unicode_at(0); event.pressed = true
		root.push_input(event,true)
	# LineEdit coalesces text_changed delivery. If the replacement equals the
	# old query, do not mistake that old receipt for completion of new input.
	await process_frame
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.query == value.to_upper(),"native uppercase search replacement"): return
	check(editor.settings_view.search.text == value.to_upper(),"displayed search differs from native uppercase input: "+editor.settings_view.search.text)

func pointer_filtered_settings() -> void:
	step = "viewport filtered stockpile All/None"
	var button: Control = editor.settings_view.rendered_rows[0][0]
	editor.settings_view.scrolls[0].ensure_control_visible(button)
	await click_control(button)
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Ammo filter setup"): return
	await click_control(editor.settings_view.rendered_rows[1][3])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Core quality filter setup"): return
	await click_control(editor.settings_view.headers[4])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"unfiltered quality All"): return
	await replace_settings_search("crafted")
	if stopped: return
	if not check(settings_captions() == ["Well-crafted","Finely-crafted"],"quality search differs from native captions"): return
	for enabled in [false,true]:
		await click_control(editor.settings_view.headers[4 if enabled else 5])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"filtered quality All/None"): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{"settings":{"ammo":{"quality_core":{"Ordinary":true,"WellCrafted":enabled,"FinelyCrafted":enabled,"Superior":true,"Exceptional":true,"Masterful":true,"Artifact":true}}}}})
		if stopped: return
		await capture("filtered_quality_all" if enabled else "filtered_quality_none")
	await click_control(editor.settings_view.headers[3])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"middle None ignores search"): return
	await native("snapshot",{"id":int(editor.selected.id),"expected":{"settings":{"ammo":{"quality_core":{"Ordinary":false,"WellCrafted":false,"FinelyCrafted":false,"Superior":false,"Exceptional":false,"Masterful":false,"Artifact":false}}}}})
	await click_control(editor.settings_view.rendered_rows[1][2])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Other materials filter setup"): return
	if not check(editor.settings_state.query == "CRAFTED" and editor.settings_view.search.text == "CRAFTED" and editor.settings_state.rows[2].is_empty(),"sublist navigation lost native search or displayed unfiltered rows"): return
	await replace_settings_search("wood")
	if stopped: return
	await click_control(editor.settings_view.headers[4])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"filtered material All"): return
	# Native ammo.other_mats is Wood=0, Bone=1, independent of displayed sorting.
	await native("snapshot",{"id":int(editor.selected.id),"expected":{"settings":{"ammo":{"other_mats":{"Wood":1,"Bone":0}}}}})

func pointer_refuse_hides() -> void:
	step = "viewport Refuse raw-hide settings"
	var index := -1
	for i in editor.settings_state.rows[0].size():
		if str(editor.settings_state.rows[0][i].key) == "refuse": index = i
	if not check(index >= 0,"Refuse category missing"): return
	var button: Control = editor.settings_view.rendered_rows[0][index]
	editor.settings_view.scrolls[0].ensure_control_visible(button)
	await click_control(button)
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Refuse leaf"): return
	if not check(editor.settings_state.query == "WOOD" and editor.settings_view.search.text == "WOOD","category navigation lost native search"): return
	await replace_settings_search("")
	if stopped: return
	await click_control(editor.settings_view.headers[5])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Refuse None"): return
	await replace_settings_search("raw hide")
	if stopped: return
	if not check(settings_captions() == ["Fresh raw hide","Rotten raw hide"],"Raw-hide search must show both native booleans"): return
	await click_control(editor.settings_view.headers[4])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"raw-hide filtered All"): return
	await native("snapshot",{"id":int(editor.selected.id),"expected":{"settings":{"refuse":{"fresh_raw_hide":true,"rotten_raw_hide":true}}}})
	if stopped: return
	await click_control(editor.settings_view.rendered_rows[2][0])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"fresh raw-hide row toggle"): return
	await native("snapshot",{"id":int(editor.selected.id),"expected":{"settings":{"refuse":{"fresh_raw_hide":false,"rotten_raw_hide":true}}}})
	await capture("refuse_raw_hides")
	# Simulate a native/external edit with the simulation paused. No reopen or
	# manual refresh: the panel must observe the changed native revision itself.
	var previous_revision := int(editor.selected.revision)
	await native("external_hide_change",{"id":int(editor.selected.id)})
	await native("guard_before")
	await request({"action":11,"operation":2,"id":int(editor.selected.id),"kind":0,"expected_revision":previous_revision,"list_key":"refuse/type","row_key":"refuse/type/fresh_raw_hide","scope":1,"value":1},"Area changed; inspect again")
	await native("guard_after")
	if stopped: return
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.rows[2].size() == 2 and int(editor.settings_state.rows[2][0].state) == 2 and int(editor.settings_state.rows[2][1].state) == 1,"paused external raw-hide refresh"): return
	if not check(editor.settings_state.category == "refuse" and editor.settings_state.leaf == "refuse/type" and editor.settings_state.query == "RAW HIDE","external refresh lost settings navigation/search"): return
	await capture("refuse_external_refresh")
	previous_revision = int(editor.selected.revision)
	await native("external_material_change",{"id":int(editor.selected.id)})
	await native("guard_before")
	await request({"action":11,"operation":2,"id":int(editor.selected.id),"kind":0,"expected_revision":previous_revision,"list_key":"ammo/other_materials","row_key":"ammo/other_materials/0","scope":1,"value":2},"Area changed; inspect again")
	await native("guard_after")
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and int(editor.selected.revision) != previous_revision,"same-size external material revision"): return
	# Hold a page request in the action queue while the external edit invalidates
	# its revision. This deterministically exercises terminal stale-read recovery.
	var receipt_start := receipts.size()
	editor.settings_state.read(2,editor.settings_state.leaf)
	await native("external_hide_change",{"id":int(editor.selected.id),"fresh":false})
	await native("guard_before")
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.rows[2].size() == 2 and int(editor.settings_state.rows[2][0].state) == 1 and int(editor.settings_state.rows[2][1].state) == 2,"stale in-flight page recovery"): return
	await native("guard_after")
	var saw_rejection := false
	for result in receipts.slice(receipt_start):
		if not check(int(result.action) == 9,"read recovery submitted a mutation"): return
		if int(result.status) == 3 and str(result.message) == "Area changed; inspect again": saw_rejection = true
	if not check(saw_rejection and editor.settings_state.query == "RAW HIDE" and editor.settings_state.leaf == "refuse/type","race was not exercised or navigation was lost"): return
	await capture("refuse_read_recovery")

func pointer_settings_scroll_refresh() -> void:
	step = "viewport paged settings refresh"
	var index := -1
	for i in editor.settings_state.rows[0].size():
		if str(editor.settings_state.rows[0][i].key) == "sheet": index = i
	if not check(index >= 0,"Sheet category missing"): return
	var button: Control = editor.settings_view.rendered_rows[0][index]
	editor.settings_view.scrolls[0].ensure_control_visible(button)
	await click_control(button)
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Sheet page"): return
	await click_control(editor.settings_view.rendered_rows[1][1])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"Parchment page"): return
	if not check(editor.settings_state.query == "RAW HIDE" and editor.settings_state.rows[2].is_empty(),"category/sublist transition did not retain raw-hide filter"): return
	await replace_settings_search("")
	if stopped: return
	if not check(editor.settings_state.rows[2].size() == 128 and int(editor.settings_state.receipts[2].next_cursor) != 0,"Parchment must exercise multiple pages"): return
	await process_frame; await process_frame
	editor.settings_view.scrolls[2].ensure_control_visible(editor.settings_view.rendered_rows[2][-1])
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.rows[2].size() > 200,"Parchment second page"): return
	await process_frame; await process_frame
	editor.settings_view.scrolls[2].ensure_control_visible(editor.settings_view.rendered_rows[2][200])
	await capture("parchment_before_refresh")
	var before_scroll: int = editor.settings_view.scrolls[2].scroll_vertical
	var before_count: int = editor.settings_state.rows[2].size()
	var raw_index: int = editor.settings_state.rows[2][200].index
	var row_key: String = editor.settings_state.rows[2][200].key
	if not check(before_scroll > 128*36,"Refresh test must be beyond first-page scroll extent"): return
	await native("external_parchment_change",{"id":int(editor.selected.id),"raw_index":raw_index})
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.rows[2].size() >= before_count and str(editor.settings_state.rows[2][200].key) == row_key and int(editor.settings_state.rows[2][200].state) == 2,"paged external refresh"): return
	await capture("parchment_after_refresh")
	if not check(editor.settings_view.scrolls[2].scroll_vertical == before_scroll,"external refresh changed deep scroll position"): return

func settings_captions() -> Array:
	var labels: Array = []
	for row in editor.settings_state.rows[2]:
		var label := str(row.label)
		labels.append(label.left(1).to_upper()+label.substr(1))
	return labels

func caption_sublists(category: String) -> void:
	# Expected text comes from protected native screenshots in settings-native-2011.
	var cases: Dictionary = {
		"ammo": {"other_materials":["Bone","Wood"]},
		"armor": {"other_materials":["Bone","Clear Glass","Crystal Glass","Green Glass","Leather","Plant Cloth","Shell","Silk","Wood","Yarn"]},
		"finished_goods": {"other_materials":["Amber","Bone","Clear Glass","Coral","Crystal Glass","Green Glass","Horn","Leather","Pearl","Plant Cloth","Shell","Silk","Tooth","Wax","Wood","Yarn"]},
		"furniture": {"other_materials":["Amber","Bone","Clear glass","Coral","Crystal glass","Green glass","Horn","Leather","Pearl","Plant cloth","Shell","Silk","Tooth","Wood","Yarn"]},
		"bars_blocks": {"bars_other":["Ash","Coal","Pearlash","Potash","Soap"],"blocks_other":["Clear Glass","Crystal Glass","Green Glass","Wood"]},
		"cloth": {"thread_plant":["Cotton thread","Hemp thread","Jute thread","Kenaf thread","Linen thread","Pig tail thread","Ramie thread","Rope reed thread"],"thread_yarn":["Alpaca wool yarn","Llama wool yarn","Sheep wool yarn","Troll fur yarn"],"thread_metal":["Adamantine strands"],"cloth_metal":["Adamantine cloth"]},
		"gems": {"rough_glass":["Clear glass","Crystal glass","Green glass"],"cut_glass":["Clear glass","Crystal glass","Green glass"]}
	}
	var checks: Dictionary = cases.get(category,{}).duplicate(true)
	if category == "cloth":
		for key in ["cloth_silk","cloth_plant","cloth_yarn"]: checks[key] = []
	if category == "sheet": checks["parchment"] = []
	if category == "gems": checks["cut_gem"] = []
	for key in checks:
		var index := -1
		for row_index in editor.settings_state.rows[1].size():
			if str(editor.settings_state.rows[1][row_index].key) == category+"/"+key: index = row_index
		if not check(index >= 0,"Missing native sublist: "+category+"/"+key): return
		var button: Control = editor.settings_view.rendered_rows[1][index]
		editor.settings_view.scrolls[1].ensure_control_visible(button)
		await click_control(button)
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"caption sublist "+key): return
		var labels := settings_captions()
		write_json("captions_"+category+"_"+key+".json",labels)
		if not check(not labels.is_empty(),"Empty native caption sublist: "+key): return
		if not checks[key].is_empty():
			if not check(labels == checks[key],"Native captions differ for "+category+"/"+key+": "+str(labels)): return
		else:
			var expected: String = {"cloth_silk":"Brown recluse spider man silk cloth","cloth_plant":"Cotton cloth","cloth_yarn":"Alpaca wool cloth","parchment":"Aardvark man parchment sheet","cut_gem":"Alexandrites"}[key]
			if not check(labels[0] == expected,"Native first caption differs for "+key+": "+str(labels[0])): return
		await capture("captions_"+category+"_"+key)

func tile_screen(tile: Vector3i) -> Vector2:
	var height := float(world.selection_height(tile))
	var target := Vector3(tile.x+0.5,tile.z+maxf(0,height),tile.y+0.5)
	return editor.camera.unproject_position(target)

func pointer_drag(first: Vector2, last: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = first; motion.global_position = first
	root.push_input(motion,true)
	var press := InputEventMouseButton.new(); press.position = first; press.global_position = first
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press,true)
	motion = InputEventMouseMotion.new(); motion.position = last; motion.global_position = last
	motion.relative = last-first; motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	var release := InputEventMouseButton.new(); release.position = last; release.global_position = last
	release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	root.push_input(release,true)
	await process_frame; await process_frame

func pointer_repaint(origin: Vector3i, id: int, destination: String) -> void:
	step = "viewport repaint "+destination
	for cancel in ["right","escape","reset",""]:
		await native("guard_before")
		await click_control(editor.stockpile_view.controls.repaint if destination == "Stockpiles" else editor.zone_menu.controls.repaint)
		if not check(editor.mode == "paint","repaint control did not enter paint mode for "+cancel): return
		await click_control(editor.paint_view.buttons.brush)
		await pointer_drag(tile_screen(origin),tile_screen(origin+Vector3i(2,0,0)))
		if editor.paint_state.cells.size() != 3:
			await capture("repaint_stroke_failure")
			write_json("repaint_stroke_failure.json",{"cells":str(editor.paint_state.cells),"paint_z":editor.paint_state.z,"top_z":world.get_top_z(),"current_z":editor.current_z,"mode":editor.mode,"tool":editor.paint_tool,"ticket":editor.request_ticket,"focus":str(root.gui_get_focus_owner()),"first":str(tile_screen(origin)),"last":str(tile_screen(origin+Vector3i(2,0,0))),"selected":editor.selected})
		if not check(editor.paint_state.cells.size() == 3,"viewport brush did not connect its stroke: "+str(editor.paint_state.cells)): return
		await elevation_round_trip(origin,destination+"_repaint_"+cancel)
		if stopped: return
		await click_control(editor.paint_view.buttons.erase)
		await pointer_click(tile_screen(origin))
		if not check(editor.paint_state.cells.size() == 2,"viewport erase did not remove the original tile"): return
		await native("guard_after")
		if not cancel.is_empty():
			if cancel == "right": await pointer_click(tile_screen(origin),MOUSE_BUTTON_RIGHT)
			elif cancel == "escape": await pointer_key(KEY_ESCAPE)
			else:
				await pointer_key(KEY_F10)
				if not check(not editor.panel.visible and editor.paint_state.cells.is_empty(),"UI reset retained a paint draft"): return
				var launcher: Button = scene._fortress_hud.navigation[destination]
				for frame in 4:
					launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
				launcher.show(); await click_control(launcher)
				if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"reopen after reset"): return
				await pointer_click(tile_screen(origin))
				if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"reinspect after reset"): return
			if not check(editor.mode == "inspect" and int(editor.selected.id) == id,cancel+" did not cancel repaint"): return
			await native("snapshot",{"id":id,"expected":{"tile_count":1,"x":origin.x,"y":origin.y}})
		else:
			await capture(destination.to_lower()+"_mixed_draft")
			if stopped: return
			var before := receipts.size()
			await click_control(editor.paint_view.accept_button)
			if not await wait_ui(func(): return settled() and editor.mode == "inspect","pointer repaint Accept"): return
			if not check(receipts.size() == before+1,"accepted viewport repaint submitted more than one request"): return
			await native("snapshot",{"id":id,"expected":{"tile_count":2,"x":origin.x+1,"y":origin.y,"width":2,"height":1}})
			await capture(destination.to_lower()+"_repainted")

func pointer_key(key: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new(); event.keycode = key; event.physical_keycode = key; event.pressed = pressed
		root.push_input(event,true)
	await process_frame; await process_frame

func pointer_owner(id: int, origin: Vector3i) -> void:
	step = "pointer owner selector"
	await click_control(editor.zone_menu.controls.owner)
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy() and not editor.candidates_state.rows.is_empty(),"owner rows"): return
	await verify_candidate_rows(id,1)
	if stopped: return
	if not await wait_ui(func():
		var visible_count := 0
		var clip: Rect2 = editor.candidates_view.scroll.get_global_rect()
		for slot in editor.candidates_view.portrait_slots:
			if not clip.intersects(slot.view.get_global_rect()) or world.unit_tile(int(slot.id)).x < 0: continue
			visible_count += 1
			if slot.view.texture == null: return false
		return visible_count > 0,"visible owner portraits"): return
	var index := -1
	var clip: Rect2 = editor.candidates_view.scroll.get_global_rect()
	for candidate in editor.candidates_view.portrait_slots.size():
		var slot: Dictionary = editor.candidates_view.portrait_slots[candidate]
		if slot.view.texture != null and clip.encloses(editor.candidates_view.choices[candidate].get_global_rect()) and not editor.candidates_view.focus_buttons[candidate].disabled:
			index = candidate; break
	if not check(index >= 0,"no visible native owner portrait with observed position"): return
	var unit := int(editor.candidates_state.rows[index].id)
	await capture("zone_owner_candidates")
	var tile: Vector3i = world.unit_tile(unit)
	await click_control(editor.candidates_view.focus_buttons[index])
	if not check(is_equal_approx(scene.camera_rig.position.x,tile.x+0.5) and is_equal_approx(scene.camera_rig.position.z,tile.y+0.5),"owner recenter did not focus observed unit"): return
	await native("snapshot",{"id":id,"expected":{"owner_id":-1}})
	await click_control(editor.candidates_view.choices[index])
	if not await wait_ui(func(): return settled() and editor.stockpile_page=="types","pointer owner assignment"): return
	await native("snapshot",{"id":id,"expected":{"owner_id":unit,"owner_name":str(editor.selected.owner_name),"owner_profession":str(editor.selected.owner_profession)}})
	if not await wait_ui(func(): return editor.zone_menu.owner_portrait.texture != null,"assigned owner portrait"): return
	await capture("zone_owner_assigned")
	await click_control(editor.zone_menu.controls.owner)
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner removal rows"): return
	await capture("zone_owner_remove")
	if not check(editor.stockpile_page=="owner" and not editor.candidates_view.remove.disabled,"owner removal control unavailable"): return
	var before_remove := receipts.size()
	await click_control(editor.candidates_view.remove)
	if not await wait_ui(func(): return settled() and editor.stockpile_page=="types","pointer remove owner"): return
	if not check(receipts.size()>before_remove,"owner removal click sent no request"): return
	await native("snapshot",{"id":id,"expected":{"owner_id":-1}})
	world.set_top_z(origin.z)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)

func elevation_round_trip(origin: Vector3i, label: String) -> void:
	var cells: Dictionary = editor.paint_state.cells.duplicate()
	var identity: Dictionary = editor.paint_state.area.duplicate(true)
	var before := receipts.size()
	world.set_top_z(origin.z+1); editor._process(0); await process_frame
	if not check(editor.mode == "paint" and editor.paint_state.cells == cells and editor.paint_state.area == identity,"elevation discarded "+label): return
	if not check(not editor.outline.visible,"off-plane outline visible for "+label): return
	await capture(label.to_lower()+"_away")
	world.set_top_z(origin.z); editor._process(0); await process_frame
	if not check(editor.paint_state.cells == cells and editor.outline.visible,"return failed to restore "+label): return
	check(receipts.size() == before,"camera elevation submitted a request for "+label)

func pointer_zone_boundary_cells() -> void:
	step = "native zone boundary extents"
	if not fixture.has("zone_wall_origin") or not fixture.has("zone_fortification"):
		incomplete("native wall/fortification reference tiles unavailable",true); return
	var p: Dictionary = fixture.zone_wall_origin
	var origin := Vector3i(int(p.x),int(p.y),int(p.z))
	var f: Dictionary = fixture.zone_fortification
	var fort := Vector3i(int(f.x),int(f.y),int(f.z))
	var cases := [
		{"name":"mixed","first":origin,"last":origin+Vector3i(2,2,0),"count":9},
		{"name":"wall_only","first":origin+Vector3i(1,0,0),"last":origin+Vector3i(1,0,0),"count":1},
		{"name":"fortification","first":fort,"last":fort,"count":1}]
	for sample in cases:
		step = "zone boundary "+str(sample.name)
		var first: Vector3i = sample.first; var last: Vector3i = sample.last
		world.set_top_z(first.z)
		scene.camera_rig.focus_on(Vector3(first.x+1,first.z+1,first.y+1),30)
		var launcher: Button = scene._fortress_hud.navigation.Zones
		# Reopening after removal must settle the deferred HUD layout, just as
		# the first launcher in pointer_areas does.
		for frame in 12:
			launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
		launcher.show()
		await click_control(launcher)
		if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"boundary zone launcher"):
			write_json("boundary_launcher_failure.json",{"visible":editor.panel.visible,"available":editor.available,"ticket":editor.request_ticket,"launcher_visible":launcher.is_visible_in_tree(),"launcher_rect":str(launcher.get_global_rect()),"mode":editor.mode})
			await capture("boundary_launcher_failure")
			return
		await click_control(editor.zone_menu.buttons.MeetingHall)
		if not await wait_ui(func():
			for tile: Vector3i in [first,last]:
				var pos := tile_screen(tile)
				if world.pick_tile(editor.camera.project_ray_origin(pos),editor.camera.project_ray_normal(pos),world.get_top_z()) != tile: return false
			return true,"boundary tiles loaded/pickable"): return
		await pointer_drag(tile_screen(first),tile_screen(last))
		if not check(editor.paint_state.cells.size() == int(sample.count),"boundary rectangle did not retain all selected cells"): return
		await click_control(editor.paint_view.accept_button)
		if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"boundary Accept"): return
		var id := int(editor.selected.id)
		var expected_extents: Array = []
		expected_extents.resize(int(sample.count)); expected_extents.fill(1)
		await native("snapshot",{"id":id,"expected":{"kind":1,"tile_count":int(sample.count),"x":first.x,"y":first.y,"z":first.z,"width":last.x-first.x+1,"height":last.y-first.y+1,"extents":expected_extents}})
		await capture("zone_boundary_"+str(sample.name))
		if sample.name == "mixed":
			await click_control(editor.zone_menu.controls.repaint)
			await click_control(editor.paint_view.buttons.brush)
			await pointer_click(tile_screen(origin+Vector3i(2,3,0)))
			if not check(editor.paint_state.cells.size() == 10,"repaint failed to add boundary wall"): return
			await click_control(editor.paint_view.accept_button)
			if not await wait_ui(func(): return settled() and editor.mode == "inspect","boundary repaint Accept"): return
			await native("snapshot",{"id":id,"expected":{"tile_count":10,"width":3,"height":4,"extents":[1,1,1,1,1,1,1,1,1,0,0,1]}})
		await click_control(editor.zone_menu.controls.repaint)
		await click_control(editor.paint_view.buttons.remove)
		if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"boundary cleanup"): return
		await native("removed",{"id":id})
		editor.close_panel()
