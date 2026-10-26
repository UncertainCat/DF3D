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
	var next_progress := Time.get_ticks_msec()+10000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
		if Time.get_ticks_msec() >= next_progress:
			print("AREAS_SCENE_STARTUP phase=",scene._loader.phase," attached=",world.is_attached()," blocks=",world.known_block_count(),"/",world.map_block_count()," pending=",world.pending_block_count()," error=",world.last_error())
			next_progress = Time.get_ticks_msec()+10000
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

func click_control(control: Control, staged_launcher := false) -> void:
	# This driver disables automatic controller processing. Run layout as the
	# actual scene would before clicking controls after a mode transition.
	for frame in 2:
		editor._process(0); await process_frame
	if control == scene._fortress_hud.navigation.Stockpiles:
		if not check(not staged_launcher and control.visible and not control.disabled,"Stockpiles must be reachable through its unmodified public launcher"): return
	if staged_launcher:
		# HUD availability refreshes every frame and leaves staged slots
		# disabled. Enable only this test click after normal layout settles.
		if not check(scene._fortress_hud.enabled,"staged launcher requires an entered playable fortress"): return
		control.disabled = false
	await pointer_click(control.get_global_transform_with_canvas()*(control.size/2))

func capture(label: String) -> void:
	# Processing is manual in this driver; settle deferred font/container sizing.
	for frame in 4:
		editor._process(0); await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory+"/scene_"+label+".png") == OK,"capture failed")
	if editor.stockpile_view.visible:
		var clip: Rect2 = editor.content.get_parent().get_global_rect()
		if not check(clip.grow(0.001).encloses(editor.stockpile_view.warning.get_global_rect()),"stockpile warning clipped: scroll="+str(clip)+" warning="+str(editor.stockpile_view.warning.get_global_rect())): return
		if not check(editor.panel.size.x == 324,"native stockpile panel width changed: "+str(editor.panel.size)+" minimum="+str(editor.panel.get_combined_minimum_size())): return

func pointer_areas() -> void:
	var p: Dictionary = fixture.origin
	var origin := Vector3i(int(p.x)+8,int(p.y)+8,int(p.z))
	world.set_top_z(origin.z)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	var stockpiles_only := FileAccess.file_exists(directory+"/stockpiles-only.json")
	var zone_animals_only := FileAccess.file_exists(directory+"/zone-animals-only.json")
	var zone_owner_only := FileAccess.file_exists(directory+"/zone-owner-only.json")
	var zone_rename_only := FileAccess.file_exists(directory+"/zone-rename-only.json")
	var zone_gather_only := FileAccess.file_exists(directory+"/zone-gather-only.json")
	var zone_overlap_only := FileAccess.file_exists(directory+"/zone-overlap-only.json")
	var destinations := ["Zones"] if zone_animals_only or zone_owner_only or zone_rename_only or zone_gather_only or zone_overlap_only else (["Stockpiles"] if stockpiles_only else ["Stockpiles","Zones"])
	for destination in destinations:
		step = "viewport "+destination
		var launcher: Button = scene._fortress_hud.navigation[destination]
		for frame in 12:
			scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
		# Zones is still staged; Stockpiles must use ordinary public availability.
		if destination == "Zones": launcher.show()
		await click_control(launcher,destination == "Zones")
		if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"pointer launcher"): return
		if destination == "Zones":
			await click_control(editor.zone_menu.buttons.Pond if zone_animals_only else (editor.zone_menu.buttons.PlantGathering if zone_gather_only else editor.zone_menu.buttons.Bedroom))
			if not check(editor.mode == "paint","zone button did not start painting"): return
		var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
		var position: Vector2 = editor.camera.unproject_position(target)
		var picked: Vector3i = world.pick_tile(editor.camera.project_ray_origin(position),editor.camera.project_ray_normal(position),world.get_top_z())
		if not check(picked == origin,"rendered picking disagrees with area fixture"): return
		await pointer_click(position)
		if not await wait_ui(func(): return settled(),"pointer footprint lookup"): return
		if not check(editor.dragging and editor.paint_state.cells.is_empty(),"first rectangle click must retain a corner without painting"): return
		await pointer_click(position)
		if not await wait_ui(func(): return settled(),"pointer second corner lookup"): return
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
			var default_name := "Unnamed pit/pond" if zone_animals_only else ("Unnamed plant gathering area" if zone_gather_only else "Unnamed bedroom")
			if not check(str(editor.selected.name) == default_name and editor.zone_menu.heading.text == default_name,"unnamed zone must use native panel name"): return
		await capture(destination.to_lower()+"_created")
		if stopped: return
		if destination == "Zones":
			if zone_overlap_only:
				await pointer_zone_overlap(origin,id); return
			if zone_gather_only:
				await pointer_zone_gathering(id)
				if stopped: return
				await click_control(editor.zone_menu.controls.remove)
				if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"remove gathering zone"): return
				await native("removed",{"id":id}); await native("final"); return
			if zone_animals_only:
				await pointer_animals(id)
				if stopped:return
				await click_control(editor.zone_menu.controls.remove)
				if not await wait_ui(func():return settled() and editor.selected.is_empty(),"remove animal test zone"):return
				await native("removed",{"id":id});await native("final");return
			if zone_owner_only:
				await pointer_owner(id,origin)
				if stopped: return
				await click_control(editor.zone_menu.controls.remove)
				if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"remove owner test zone"): return
				await native("removed",{"id":id}); await native("final"); return
			await pointer_stockpile_name(origin)
			if stopped: return
			if zone_rename_only:
				await click_control(editor.zone_menu.controls.remove)
				if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"remove renamed zone"): return
				await native("removed",{"id":id}); await native("final"); return
			await pointer_owner(id,origin)
		elif not FileAccess.file_exists(directory+"/stockpile-paint-only.json"):
			await stockpile_name_contract()
			if not stopped: await pointer_stockpile_name(origin)
			if not stopped: await pointer_stockpile_help()
			if stopped: return
			await pointer_storage_limits()
			if not stopped: await pointer_stockpile_fit(origin)
			if not stopped: await link_unloaded_target()
			if not stopped and FileAccess.file_exists(directory+"/stockpile-fit-only.json"):
				await native("final"); return
			if not stopped: await pointer_settings()
		if stopped: return
		await pointer_repaint(origin,id,destination)
		if stopped: return
		await click_control(editor.stockpile_view.controls.repaint if destination == "Stockpiles" else editor.zone_menu.controls.repaint)
		await click_control(editor.paint_view.buttons.remove)
		if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"pointer Remove"): return
		await native("removed",{"id":id})
		if destination == "Stockpiles":
			await pointer_stockpile_empty(origin)
			if stopped: return
			await pointer_stockpile_noop(origin)
			if stopped: return
			await pointer_stockpile_transfer(origin)
			if stopped: return
		editor.close_panel()
	if not stockpiles_only: await pointer_zone_boundary_cells()
	if stopped: return
	await native("final")
	if not stopped: print("AREAS_POINTER_PASS")

func pointer_zone_gathering(id: int) -> void:
	step = "viewport native gathering flags"
	var expected := {"gather_trees":1,"gather_shrubs":1,"gather_fallen":1}
	if not check(editor.selected.zone_settings.gather_fallen == 1,"new gathering zone did not expose native fallen default"): return
	await native("zone_settings",{"id":id,"expected":expected})
	for key in expected.keys():
		var button: Button
		for index in editor.zone_menu.SETTINGS.size():
			if str(editor.zone_menu.SETTINGS[index][1]) == key: button = editor.zone_menu.setting_buttons[index]
		if not check(button != null and button.visible and not button.disabled,"gathering control unavailable: "+key): return
		for value in [0,1]:
			await click_control(button)
			if not await wait_ui(settled,"gathering toggle "+key): return
			expected[key] = value
			await native("zone_settings",{"id":id,"expected":expected})
			for other in expected:
				if not check(int(editor.selected.zone_settings[other]) == int(expected[other]),"gathering observation differs for "+other): return
			if key == "gather_fallen": await capture("zone_fallen_"+str(value))

func stockpile_name_contract() -> void:
	# Semantic field acceptance only; actual inline rename input is separate.
	step = "stockpile custom name contract"
	if not check(editor.selected.get("custom_name",null) == "","unnamed custom string missing"): return
	for value in ["Stockpile #2","Caf\u00e9",""]:
		editor.rename_area(value)
		if not await wait_ui(settled,"custom name write"): return
		var observed := await native("snapshot",{"id":int(editor.selected.id),"expected":{"custom_name":value}})
		if stopped: return
		if not check(editor.selected.get("custom_name",null) == value and editor.selected.name == observed.area.name,"custom/display name differs from native"): return

func name_text(value: String) -> void:
	for character in value:
		for pressed in [true,false]:
			var event := InputEventKey.new(); event.pressed = pressed; event.unicode = character.unicode_at(0)
			root.push_input(event,true)

func hover_stockpile_button(control: Button, key: String, suffix := "") -> void:
	for frame in 3:
		editor._process(0); await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_transform_with_canvas()*(control.size/2)
	motion.global_position = motion.position; root.push_input(motion,true)
	await create_timer(0.65).timeout
	if not check(editor.stockpile_help.visible and editor.stockpile_help.displayed == key,"native stockpile hover missing: "+key): return
	var source: Dictionary = preload("res://scripts/area_menu_data.gd").read()
	var rows: Array = source.paint_tools if key.begins_with("paint/") else source.stockpile_controls
	var expected: Array = []
	for row in rows:
		if str(row.key) == key.get_slice("/",1): expected = row.hover_lines
	if not check(not expected.is_empty() and editor.stockpile_help.lines == expected,"native hover source text changed: "+key): return
	if not check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(screen_rect(editor.stockpile_help)),"stockpile tooltip outside viewport"): return
	await capture("stockpile_help_"+key.replace("/","_")+suffix)

func pointer_stockpile_help() -> void:
	step = "viewport stockpile instruction hovers"
	for row in editor.menu_data.stockpile_controls:
		await hover_stockpile_button(editor.stockpile_view.controls[row.key],"palette/"+str(row.key))
		if stopped: return
	await click_control(editor.stockpile_view.controls.repaint)
	if not await wait_ui(func(): return settled() and editor.paint_view.visible,"hover repaint"): return
	for row in editor.menu_data.paint_tools:
		await hover_stockpile_button(editor.paint_view.buttons[row.key],"paint/"+str(row.key))
		if stopped: return
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and editor.stockpile_view.visible,"hover return"): return
	if not check(not editor.stockpile_help.visible,"paint tooltip survived navigation"): return

func pointer_stockpile_name(origin: Vector3i) -> void:
	step = "viewport inline stockpile name"
	var id := int(editor.selected.id)
	var zone := int(editor.selected.kind) == 1
	var menu = editor.zone_menu if zone else editor.stockpile_view
	var destination := "Zones" if zone else "Stockpiles"
	var prefix := "zone" if zone else "stockpile"
	var initial_size: Vector2 = editor.panel.size
	await click_control(menu.controls.rename)
	if not check(editor.rename_field.editing and editor.rename_field.value == "","native empty inline name absent"): return
	await click_control(menu.controls.rename)
	if not check(editor.rename_field.visible and editor.stockpile_page == "rename","repeated quill hid inline name"): return
	name_text("Aa1 B")
	if not await wait_ui(settled,"immediate rename without Enter"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":"Aa1 B"}})
	if not check(editor.panel.size == initial_size and editor.rename_field.get_parent() == (menu.selected_panel if zone else menu),"rename changed palette layout"): return
	await capture(prefix+"_rename_inline")
	await pointer_key(KEY_ENTER)
	if not check(editor.panel.visible and not editor.rename_field.editing,"Enter did not end entry"): return
	await click_control(menu.controls.rename)
	name_text("X")
	if not await wait_ui(settled,"append existing name"): return
	await pointer_key(KEY_BACKSPACE)
	if not await wait_ui(settled,"name backspace"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":"Aa1 B"}})
	name_text("a".repeat(40))
	if not await wait_ui(settled,"native name limit"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":"Aa1 B"+"a".repeat(15)}})
	await capture(prefix+"_rename_limit")
	# Deliver Backspace and Escape before the action service polls. Explicit
	# text must drain even though the panel closes immediately.
	for index in 20:
		var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_BACKSPACE; root.push_input(key,true)
	await pointer_key(KEY_ESCAPE)
	if not check(not editor.panel.visible,"Escape did not close palette"): return
	if not await wait_ui(func(): return actions._active == 0 and actions._queue.is_empty(),"closed rename drain"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":""}})
	await click_control(scene._fortress_hud.navigation[destination],zone)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"rename reopen launcher"): return
	await pointer_click(tile_screen(origin))
	if not await wait_ui(func(): return settled() and int(editor.selected.get("id",-1)) == id,"renamed pile reselection"): return
	if not check(editor.selected.custom_name == "" and menu.heading.text == editor.selected.name,"cleared name did not restore default heading"): return
	await click_control(menu.controls.rename)
	name_text("R")
	await pointer_click(tile_screen(origin),MOUSE_BUTTON_RIGHT)
	if not check(not editor.panel.visible,"right-click did not close rename palette"): return
	if not await wait_ui(func(): return actions._active == 0 and actions._queue.is_empty(),"right-click rename drain"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":"R"}})
	await click_control(scene._fortress_hud.navigation[destination],zone)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"right-click reopen launcher"): return
	await pointer_click(tile_screen(origin))
	if not await wait_ui(func(): return settled() and int(editor.selected.get("id",-1)) == id,"right-click pile reselection"): return
	await click_control(menu.controls.rename)
	await pointer_key(KEY_BACKSPACE); await pointer_key(KEY_ENTER)
	if not await wait_ui(settled,"restore unnamed stockpile"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":""}})

	if zone: return # Native Windows text cases below are separately established for stockpiles.
	var samples = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_rename.json")).window_text.cases
	for index in samples.size():
		var sample: Dictionary = samples[index]
		await click_control(menu.controls.rename)
		for count in 20:
			var event := InputEventKey.new(); event.pressed = true; event.keycode = KEY_BACKSPACE; root.push_input(event,true)
		name_text(str(sample.typed))
		if not await wait_ui(settled,"native Windows name case "+str(index)): return
		await native("snapshot",{"id":id,"expected":{"custom_name":str(sample.native.stored)}})
		if not check(editor.rename_field.value == str(sample.native.stored),"rendered name differs from native Windows text"): return
		if index in [1,5]: await capture("stockpile_name_windows_"+str(index))
		await pointer_key(KEY_ENTER)
	await click_control(menu.controls.rename)
	for count in 20:
		var event := InputEventKey.new(); event.pressed = true; event.keycode = KEY_BACKSPACE; root.push_input(event,true)
	await pointer_key(KEY_ENTER)
	if not await wait_ui(settled,"restore unnamed after native text cases"): return
	await native("snapshot",{"id":id,"expected":{"custom_name":""}})

func pointer_storage_limits() -> void:
	step = "viewport native storage limits"
	if not check(int(editor.selected.get("storage_limit",-1)) == 1 and int(editor.selected.tile_count) == 1,"one-tile native bound absent"): return
	await click_control(editor.stockpile_view.controls.containers)
	if not await wait_ui(func(): return settled() and editor.storage_view.visible,"storage popup inspection"): return
	for key in ["barrels","bins","wheelbarrows"]:
		await click_control(editor.storage_view.controls[key][1])
		if not check(editor.request_ticket != 0 and not editor.message.visible,"pending stockpile request exposes generic status copy"): return
		if key == "bins": await capture("stockpile_storage_pending")
		if not await wait_ui(func(): return settled() and int(editor.selected[key]) == 1,"storage increment " + key): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{key:1,"tile_count":1}})
		if not check(editor.storage_view.controls[key][1].disabled,"increment remains enabled at native limit"): return
		await capture("storage_limit_" + key)
		await click_control(editor.storage_view.controls[key][2])
		if not await wait_ui(func(): return settled() and int(editor.selected[key]) == 0,"storage decrement " + key): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{key:0,"tile_count":1}})
	for key in ["barrels","bins","wheelbarrows"]:
		await click_control(editor.storage_view.controls[key][0])
		if not check(editor.storage_view.entry.has_focus(),"numeric entry did not focus"): return
		var digit := InputEventKey.new(); digit.unicode = 57; digit.pressed = true
		root.push_input(digit,true)
		if not await wait_ui(func(): return settled() and int(editor.selected[key]) == 1,"immediate numeric entry " + key): return
		if not check(editor.storage_view.editing == key and editor.storage_view.entry.text == "9","accepted numeric reply ended or rewrote entry"): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{key:1}})
		await capture("storage_numeric_" + key)
		await pointer_key(KEY_BACKSPACE)
		if not await wait_ui(func(): return settled() and int(editor.selected[key]) == 0,"empty numeric entry " + key): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{key:0}})
		root.push_input(digit,true)
		await pointer_key(KEY_ESCAPE)
		if not check(editor.stockpile_page == "types","Escape did not close numeric popup"): return
		if not await wait_ui(func(): return settled() and int(editor.selected[key]) == 1,"closed popup numeric receipt " + key): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{key:1}})
		await click_control(editor.stockpile_view.controls.containers)
		if not await wait_ui(func(): return settled() and editor.storage_view.visible,"reopened numeric popup"): return
		await click_control(editor.storage_view.controls[key][2])
		if not await wait_ui(func(): return settled() and int(editor.selected[key]) == 0,"restore numeric entry " + key): return
	editor.handle_back(); editor._process(0)
	if not check(editor.stockpile_page == "types","storage popup did not return to pile"): return

func screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO,control.size)

func pointer_stockpile_fit(origin: Vector3i) -> void:
	var preferences = preload("res://scripts/presentation_settings.gd")
	var old_auto: bool = preferences.ui_auto_scale
	var old_scale: float = preferences.ui_scale
	for dimensions in [Vector2i(912,600),Vector2i(1200,800),Vector2i(960,600),Vector2i(640,480),Vector2i(1920,1080)]:
		step = "stockpile viewport fit " + str(dimensions)
		root.size = dimensions
		preferences.ui_auto_scale = dimensions.x == 912; preferences.ui_scale = 1.5
		scene._fortress_hud.apply_ui_scale()
		for frame in 8: editor._process(0); await process_frame
		var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
		var panel_rect := screen_rect(editor.panel)
		var header_rect := screen_rect(scene._fortress_hud.status_panel)
		await capture("stockpile_fit_layout_%dx%d" % [dimensions.x,dimensions.y])
		if stopped: return
		if not check(viewport.encloses(panel_rect),"stockpile panel extends beyond viewport"): return
		if not check(not panel_rect.intersects(header_rect),"stockpile panel overlaps HUD header"): return
		if not check(not panel_rect.intersects(screen_rect(scene._fortress_hud.actions)),"stockpile palette overlaps bottom actions"): return
		await hover_stockpile_button(editor.stockpile_view.controls.links_only,"palette/links_only","_%dx%d" % [dimensions.x,dimensions.y])
		if stopped: return
		await click_control(editor.stockpile_view.controls.containers)
		if not await wait_ui(func(): return settled() and editor.storage_view.visible,"scaled storage open"): return
		if not check(viewport.encloses(screen_rect(editor.storage_view)),"storage popup extends beyond viewport"): return
		await click_control(editor.storage_view.controls.bins[1])
		if not await wait_ui(func(): return settled() and int(editor.selected.bins)==1,"scaled storage increment"): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{"bins":1}})
		await capture("stockpile_fit_%dx%d" % [dimensions.x,dimensions.y])
		await click_control(editor.storage_view.controls.bins[2])
		if not await wait_ui(func(): return settled() and int(editor.selected.bins)==0,"scaled storage decrement"): return
		await native("snapshot",{"id":int(editor.selected.id),"expected":{"bins":0}})
		await pointer_key(KEY_ESCAPE)
		if not await wait_ui(func(): return settled() and editor.stockpile_page=="types","scaled storage close"): return
		var custom := -1
		for index in editor.menu_data.presets.size():
			if int(editor.menu_data.presets[index].preset)==0: custom=index
		if not check(custom>=0,"scaled Custom preset missing"): return
		await click_control(editor.stockpile_view.preset_buttons[custom])
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"scaled settings open"): return
		await capture("stockpile_fit_settings_%dx%d" % [dimensions.x,dimensions.y])
		if stopped: return
		panel_rect=screen_rect(editor.panel)
		if not check(viewport.encloses(panel_rect) and not panel_rect.intersects(header_rect),"settings panel clips or overlaps header"): return
		if not check(not panel_rect.intersects(screen_rect(scene._fortress_hud.actions)),"settings panel overlaps bottom actions"): return
		for column in editor.settings_view.scrolls:
			if not check(panel_rect.encloses(screen_rect(column)),"settings rows extend beyond their panel"): return
		if not check(not panel_rect.intersects(screen_rect(scene._fortress_hud.minimap_panel)),"settings panel overlaps minimap"): return
		var pages := {1920:14}
		if pages.has(dimensions.x) and not check(editor.settings_view.page_rows==int(pages[dimensions.x]),"scaled settings visible row count"): return
		write_json("fit_%dx%d.json" % [dimensions.x,dimensions.y],{"canvas_scale":str(editor.canvas.scale),"hud_scale":str(scene._fortress_hud.ui_scale_vector()),"page_rows":editor.settings_view.page_rows,"leaf_width":editor.settings_view.column_widths[2],"panel":str(panel_rect)})
		for enabled in [true,false]:
			var button: Button = editor.settings_view.headers[4 if enabled else 5]
			if dimensions.x == 912:
				if not check(viewport.encloses(screen_rect(button)) and not (editor.content.get_parent() as ScrollContainer).clip_contents,"native minimum-width item header clipped"): return
			else:
				if not check(panel_rect.encloses(screen_rect(button)),"scaled item header clipped"): return
			await click_control(button)
			if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"scaled item All/None"): return
			var expected: Dictionary = {}
			for row in editor.settings_state.rows[2]: expected[str(int(row.index))] = 1 if enabled else 0
			await native("snapshot",{"id":int(editor.selected.id),"expected":{"settings":{"ammo":{"type":expected}}}})
		if dimensions.x == 912:
			for button in editor.settings_view.rendered_rows[0]:
				if button.tooltip_text == "Food":
					editor.settings_view.scrolls[0].ensure_control_visible(button)
					await click_control(button); break
			if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"minimum width Food rows"): return
			if not check(editor.settings_view.scrolls[2].clip_contents,"narrow item column is not clipped"): return
			if not check(not editor.settings_view.rendered_rows[2].is_empty(),"narrow item names missing"): return
			for button in editor.settings_view.rendered_rows[2]:
				var label: Label = button.get_child(0)
				if not check(label.visible and label.clip_text and label.position.x+label.size.x <= editor.settings_view.scrolls[2].size.x,"narrow item name exceeds column"): return
			await capture("stockpile_clipped_text")
			var bar: Control = editor.settings_view.native_scrolls[2]
			await pointer_click(bar.get_global_transform_with_canvas()*Vector2(8,bar.size.y-6))
			if not await wait_ui(func(): return settled() and not editor.settings_state.busy(),"clipped leaf scroll"): return
			await capture("stockpile_clipped_text_scrolled")
		await pointer_key(KEY_ESCAPE)
		if not await wait_ui(func(): return settled() and editor.stockpile_page=="types","scaled settings close"): return
		await pointer_stockpile_fit_actions(origin,dimensions)
		if stopped: return
	preferences.ui_auto_scale = old_auto; preferences.ui_scale = old_scale
	root.size = Vector2i(1200,800); scene._fortress_hud.apply_ui_scale()
	for frame in 8: editor._process(0); await process_frame

func link_unloaded_target() -> void:
	step = "unloaded in-map link target"
	var wp: Dictionary = fixture.workshop_origin
	var target := Vector3i(int(wp.x),int(wp.y),int(wp.z))
	var query := {"action":9,"kind":0,"operation":26,"id":int(editor.selected.id),"expected_revision":int(editor.selected.revision),"origin":target,"give":true}
	await native("guard_before")
	var loaded := await request(query)
	if not check(loaded.get("links",[]).size()==1 and int(loaded.links[0].id)==int(fixture.workshop),"loaded control target absent"): return
	await native("link_unloaded_prepare",{"id":int(editor.selected.id),"x":target.x,"y":target.y,"z":target.z})
	var missing := await request(query)
	await native("link_unloaded_restore")
	if stopped: return # Teardown also restores the block after an early failure.
	if not check(missing.get("links",[]).is_empty(),"unloaded in-map target disclosed a building"): return
	var restored := await request(query)
	if not check(restored.get("links",[]).size()==1 and int(restored.links[0].id)==int(fixture.workshop),"restored target lookup differs"): return
	await native("guard_after")
	write_json("link-unloaded-evidence.json",{"source":int(editor.selected.id),"target":int(fixture.workshop),"tile":str(target),"loaded":loaded.links.size(),"unloaded":missing.get("links",[]).size(),"restored":restored.links.size()})

func pointer_stockpile_fit_actions(origin: Vector3i, dimensions: Vector2i) -> void:
	var id := int(editor.selected.id)
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	for frame in 8: await process_frame
	await click_control(editor.stockpile_view.controls.repaint)
	await hover_stockpile_button(editor.paint_view.buttons.remove,"paint/remove","_%dx%d" % [dimensions.x,dimensions.y])
	if stopped: return
	await click_control(editor.paint_view.buttons.brush)
	var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
	if not check(viewport.encloses(screen_rect(editor.paint_view.tools)),"scaled paint toolbar outside viewport"): return
	await pointer_click(tile_screen(origin+Vector3i(1,0,0)))
	if not await wait_ui(func(): return settled() and editor.paint_state.cells.size()==2,"scaled brush add"): return
	await native("snapshot",{"id":id,"expected":{"tile_count":2}})
	await click_control(editor.paint_view.buttons.erase)
	await pointer_click(tile_screen(origin+Vector3i(1,0,0)))
	if not await wait_ui(func(): return settled() and editor.paint_state.cells.size()==1,"scaled brush erase"): return
	await native("snapshot",{"id":id,"expected":{"tile_count":1}})
	await capture("stockpile_fit_paint_%dx%d" % [dimensions.x,dimensions.y])
	if stopped: return
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and editor.mode=="inspect","scaled paint Accept"): return
	await click_control(editor.stockpile_view.controls.links)
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"scaled links open"): return
	if not check(viewport.encloses(screen_rect(editor.links_view)),"scaled links outside viewport"): return
	if not check(not screen_rect(editor.links_view).intersects(screen_rect(scene._fortress_hud.actions)),"scaled links overlap bottom actions"): return
	var wp: Dictionary = fixture.workshop_origin
	var target := Vector3i(int(wp.x),int(wp.y),int(wp.z))
	scene.camera_rig.focus_on(Vector3(target.x+0.5,target.z+1.0,target.y+0.5),30)
	for frame in 8: await process_frame
	await click_control(editor.links_view.add_buttons[0])
	await pointer_click(tile_screen(target))
	if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"scaled workshop link"): return
	await native("link",{"id":int(fixture.workshop),"pile_id":id,"give":false,"linked":true})
	await capture("stockpile_fit_links_%dx%d" % [dimensions.x,dimensions.y])
	if stopped: return
	await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"scaled workshop unlink"): return
	await native("link",{"id":int(fixture.workshop),"pile_id":id,"give":false,"linked":false})
	await click_control(editor.links_view.close)
	if not await wait_ui(func(): return settled() and editor.stockpile_page=="types","scaled links close"): return
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	for frame in 8: await process_frame

func pointer_settings() -> void:
	step = "viewport stockpile settings categories"
	await native("category_before",{"id":int(editor.selected.id),"category":"ammo"})
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
		await native("category_before",{"id":int(editor.selected.id),"category":category})
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
		if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.category == "armor","Armor selection for global None"): return
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

func replace_settings_search(value: String, expected = null) -> void:
	var normalized: String = value.to_upper() if expected == null else str(expected)
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
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.query == normalized,"native uppercase search replacement"): return
	check(editor.settings_view.search.text == normalized,"displayed search differs from native uppercase input: "+editor.settings_view.search.text)

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
	await native("guard_before")
	await replace_settings_search("é12Ω-!","")
	if stopped: return
	if not check(settings_captions().size() == 7,"rejected characters must leave unfiltered quality rows"): return
	await replace_settings_search("a".repeat(120),"A".repeat(76))
	if stopped: return
	if not check(settings_captions().is_empty(),"native-length unmatched query must show no quality rows"): return
	await replace_settings_search("cráa1f-tedΩ","CRAFTED")
	if stopped: return
	await native("guard_after")
	await capture("settings_native_search_input")
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
	var bar = editor.settings_view.native_scrolls[2]
	var total := int(editor.settings_state.receipts[2].settings_count)
	if not check(total > before_count + 16,"Parchment must exercise a distant unloaded range"): return
	var grip: Vector2i = bar.thumb()
	var start: Vector2 = bar.get_global_transform_with_canvas() * Vector2(8,(grip.x+0.5)*12)
	var finish: Vector2 = bar.get_global_transform_with_canvas() * Vector2(8,bar.size.y-18)
	var press := InputEventMouseButton.new(); press.position = start; press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT; press.button_mask = MOUSE_BUTTON_MASK_LEFT; press.pressed = true
	root.push_input(press,true)
	var motion := InputEventMouseMotion.new(); motion.position = finish; motion.global_position = finish
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT; root.push_input(motion,true)
	var release := InputEventMouseButton.new(); release.position = finish; release.global_position = finish
	release.button_index = MOUSE_BUTTON_LEFT; root.push_input(release,true)
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.row_starts[2] == total-16,"native scrollbar distant drag"): return
	await capture("parchment_distant_range")
	if not check(editor.settings_view.rendered_rows[2].size() == 16 and editor.settings_view.scrolls[2].scroll_vertical == (total-16)*36,"distant drag did not render final native range"): return

	await scaled_settings_range(total)

func scaled_settings_range(total: int) -> void:
	step = "settings UI preference scaling and range input"
	var preferences = preload("res://scripts/presentation_settings.gd")
	var old_auto: bool = preferences.ui_auto_scale
	var old_scale: float = preferences.ui_scale
	root.size = Vector2i(1920,1080)
	preferences.ui_auto_scale = false; preferences.ui_scale = 1.5
	scene._fortress_hud.apply_ui_scale()
	for frame in 6: editor._process(0); await process_frame
	var view = editor.settings_view
	var bar = view.native_scrolls[2]
	if not check(editor.canvas.scale == Vector2(1.5,1.5) and bar.page == 14,"settings did not follow product UI scale and native page count"): return
	bar.move_to(0)
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.row_starts[2] == 0,"scaled settings first range"): return
	var point: Vector2 = view.get_global_transform_with_canvas() * (view.scrolls[2].position + Vector2(50,30))
	for page in [false,true]:
		var wheel := InputEventMouseButton.new(); wheel.position = point; wheel.global_position = point
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true; wheel.shift_pressed = page
		root.push_input(wheel,true); await process_frame; await process_frame
		if not check(bar.first == (15 if page else 1),"scaled settings wheel/page increment: first="+str(bar.first)+" page="+str(page)+" scroll="+str(view.scrolls[2].scroll_vertical)): return
	var grip: Vector2i = bar.thumb()
	await pointer_drag(bar.get_global_transform_with_canvas()*Vector2(8,(grip.x+0.5)*12),bar.get_global_transform_with_canvas()*Vector2(8,bar.size.y-18))
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and editor.settings_state.row_starts[2] == total-14,"scaled settings distant range"): return
	if not check(view.rendered_rows[2].size() == 14 and view.scrolls[2].scroll_vertical == (total-14)*36,"scaled settings range count or origin"): return
	await capture("settings_scale_150_distant")
	preferences.ui_auto_scale = old_auto; preferences.ui_scale = old_scale
	root.size = Vector2i(1200,800); scene._fortress_hud.apply_ui_scale()
	for frame in 6: editor._process(0); await process_frame
	if not await wait_ui(func(): return settled() and not editor.settings_state.busy() and not view.layout_pending.has(true),"restored settings size and range"): return

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
	if destination == "Stockpiles":
		await pointer_stockpile_repaint(origin,id); return
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
					scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
				if destination == "Zones": launcher.show()
				await click_control(launcher,destination == "Zones")
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

func pointer_stockpile_repaint(origin: Vector3i, id: int) -> void:
	for ending in ["right","escape","reset","accept"]:
		step = "immediate stockpile repaint "+ending
		await click_control(editor.stockpile_view.controls.repaint)
		if not check(editor.mode == "paint" and int(editor.selected.get("id",-1)) == id,"repaint click lost inspected identity; mode="+str(editor.mode)+" selected="+str(editor.selected)): return
		await click_control(editor.paint_view.buttons.brush)
		if not check(int(editor.selected.get("id",-1)) == id,"brush tool click lost inspected identity"): return
		await pointer_drag(tile_screen(origin),tile_screen(origin+Vector3i(2,0,0)))
		if not await wait_ui(func(): return settled(),"sampled brush receipts"): return
		if not check(editor.paint_state.cells.size() == 2 and not editor.paint_state.cells.has(Vector2i(origin.x+1,origin.y)),"unexpected brush cells="+str(editor.paint_state.cells)+" selected="+str(editor.selected)+" tool="+str(editor.paint_tool)+" erase="+str(editor.paint_erasing)): return
		await native("snapshot",{"id":id,"expected":{"tile_count":2,"extents":[1,0,1]}})
		await elevation_round_trip(origin,"stockpiles_repaint_"+ending)
		if stopped: return
		await click_control(editor.paint_view.buttons.erase)
		await pointer_click(tile_screen(origin))
		if not await wait_ui(func(): return settled(),"erase receipt before exit"): return
		await native("snapshot",{"id":id,"expected":{"tile_count":1,"x":origin.x,"y":origin.y,"width":3,"height":1,"extents":[0,0,1]}})
		await capture("stockpiles_immediate_"+ending)
		if ending == "accept":
			var before := receipts.size()
			await click_control(editor.paint_view.accept_button)
			if not await wait_ui(func(): return settled() and editor.mode == "inspect","repaint Accept"): return
			if not check(receipts.size() == before,"Accept replayed already committed paint"): return
		else:
			# A pending rectangle does not change Escape/right-click's whole-tool exit.
			await click_control(editor.paint_view.buttons.rectangle)
			await pointer_click(tile_screen(origin+Vector3i(1,0,0)))
			if not check(editor.dragging,"partial rectangle corner missing"): return
			if ending == "right": await pointer_click(tile_screen(origin),MOUSE_BUTTON_RIGHT)
			elif ending == "escape": await pointer_key(KEY_ESCAPE)
			else: await pointer_key(KEY_F10)
			if not check(not editor.panel.visible,"paint exit left panel visible"): return
			await native("snapshot",{"id":id,"expected":{"tile_count":1,"extents":[0,0,1]}})
			var launcher: Button = scene._fortress_hud.navigation.Stockpiles
			for frame in 4:
				scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
			await click_control(launcher)
			if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"reopen stockpiles"): return
			# Exercise initial brush-hit lookup against an existing pile.
			await click_control(editor.paint_view.buttons.brush)
			await pointer_click(tile_screen(origin+Vector3i(2,0,0)))
			if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"existing pile hit"): return
			if not check(int(editor.selected.id) == id and editor.mode == "inspect","initial brush hit created instead of selecting"): return
			await native("snapshot",{"id":id,"expected":{"tile_count":1,"extents":[0,0,1]}})

func pointer_stockpile_empty(origin: Vector3i) -> void:
	for ending in ["escape","right"]:
		step = "viewport empty stockpile "+ending
		if not editor.panel.visible:
			var launcher: Button = scene._fortress_hud.navigation.Stockpiles
			for frame in 4:
				scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
			await click_control(launcher)
			if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"empty test launcher"): return
		await pointer_click(tile_screen(origin)); await pointer_click(tile_screen(origin))
		if not await wait_ui(func(): return settled(),"empty test creation"): return
		if not check(editor.paint_session != null and not editor.paint_session.area.is_empty(),"empty test missing created pile"): return
		var id: int = editor.paint_session.area.id
		await click_control(editor.paint_view.buttons.brush)
		await click_control(editor.paint_view.buttons.erase)
		await pointer_click(tile_screen(origin))
		if not await wait_ui(func(): return settled(),"erase last cell"): return
		if not check(editor.paint_view.accept_button.disabled and editor.paint_session.area.id == id,"empty pile must retain identity with Accept disabled"): return
		await native("snapshot",{"id":id,"expected":{"tile_count":0,"extents":[0]}})
		await capture("stockpiles_empty_"+ending)
		await click_control(editor.paint_view.buttons.erase)
		await pointer_click(tile_screen(origin))
		if not await wait_ui(func(): return settled(),"regrow empty pile"): return
		await native("snapshot",{"id":id,"expected":{"tile_count":1,"extents":[1]}})
		if not check(not editor.paint_view.accept_button.disabled,"regrown pile must enable Accept"): return
		await click_control(editor.paint_view.buttons.erase)
		await pointer_click(tile_screen(origin))
		# Exit before polling the final erase receipt. The owner must drain then delete.
		var owner = editor.paint_session
		if ending == "escape": await pointer_key(KEY_ESCAPE)
		else: await pointer_click(tile_screen(origin),MOUSE_BUTTON_RIGHT)
		if not check(not editor.panel.visible,"empty exit left paint panel open"): return
		if not await wait_ui(func(): return not is_instance_valid(owner) or owner.stopped,"empty exit deletion receipt"): return
		await native("removed",{"id":id})

func pointer_stockpile_noop(origin: Vector3i) -> void:
	step = "viewport all-clipped stockpile creation"
	var launcher: Button = scene._fortress_hud.navigation.Stockpiles
	for frame in 4:
		scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
	await click_control(launcher)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"no-op test launcher"): return
	await native("creation_noop_prepare",{"x":origin.x,"y":origin.y,"z":origin.z})
	await pointer_click(tile_screen(origin)); await pointer_click(tile_screen(origin))
	if not await wait_ui(func(): return settled(),"all-clipped creation receipt"): return
	if not check(editor.paint_session != null and editor.paint_session.area.is_empty() and editor.paint_state.cells.is_empty() and editor.paint_view.accept_button.disabled,"no-op must retain empty painter with Accept disabled"): return
	await capture("stockpiles_noop_creation")
	await native("creation_noop_restore")
	await pointer_click(tile_screen(origin)); await pointer_click(tile_screen(origin))
	if not await wait_ui(func(): return settled(),"valid creation after no-op"): return
	if not check(not editor.paint_session.area.is_empty() and not editor.paint_view.accept_button.disabled,"valid gesture after no-op must create normally"): return
	var id: int = editor.paint_session.area.id
	await native("snapshot",{"id":id,"expected":{"tile_count":1}})
	await click_control(editor.paint_view.buttons.remove)
	if not await wait_ui(func(): return settled(),"remove after no-op"): return
	await native("removed",{"id":id})

func pointer_stockpile_transfer(origin: Vector3i) -> void:
	step = "viewport multi-donor transfer and linked donor deletion"
	editor.close_panel()
	var ids: Array[int] = []
	for offset in [0,2,4]:
		var made := await request({"action":10,"kind":0,"operation":5,"paint_mode":1,"paint_z":origin.z,
			"spans":[{"x":origin.x+offset,"y":origin.y,"length":2 if offset==4 else 1}]})
		if stopped: return
		ids.append(int(made.areas[0].id))
		await native("pile_designations",{"id":ids.back()})
	for pair in [[ids[0],ids[1]],[ids[2],ids[1]],[ids[0],ids[2]]]:
		for give in [true,false]:
			var current := await inspect(pair[0])
			await request({"action":13,"kind":0,"id":pair[0],"link_id":pair[1],"give":give,"expected_revision":current.revision})
			if stopped: return
			await native("pile_link",{"id":pair[0],"target_id":pair[1],"give":give,"linked":true})
	for pile_id in [ids[1],ids[2]]:
		for give in [true,false]:
			var current := await inspect(pile_id)
			await request({"action":13,"kind":2,"id":int(fixture.workshop),"operation":15,"link_id":pile_id,
				"give":give,"expected_revision":current.revision})
			if stopped: return
	var launcher: Button = scene._fortress_hud.navigation.Stockpiles
	for frame in 4:
		scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
	await click_control(launcher)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"transfer launcher"): return
	await pointer_click(tile_screen(origin))
	if not await wait_ui(func(): return settled() and editor.mode=="inspect" and int(editor.selected.get("id",-1))==ids[0],"select transfer recipient"): return
	await click_control(editor.stockpile_view.controls.repaint)
	await click_control(editor.paint_view.buttons.rectangle)
	await pointer_click(tile_screen(origin+Vector3i(2,0,0)))
	await pointer_click(tile_screen(origin+Vector3i(4,0,0)))
	if not await wait_ui(func(): return settled(),"multi-donor transfer receipt"): return
	await native("snapshot",{"id":ids[0],"expected":{"tile_count":4,"width":5,"height":1,"extents":[1,0,1,1,1]}})
	await native("snapshot",{"id":ids[2],"expected":{"tile_count":1,"width":2,"height":1,"extents":[0,1]}})
	await native("transfer_links",{"deleted":ids[1],"survivors":[ids[0],ids[2],int(fixture.workshop)]})
	for give in [true,false]:
		await native("pile_link",{"id":ids[0],"target_id":ids[2],"give":give,"linked":not give})
		await native("link",{"id":int(fixture.workshop),"pile_id":ids[2],"give":give,"linked":not give})
	await capture("stockpiles_multi_transfer")
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and editor.mode=="inspect","transfer Accept"): return
	await click_control(editor.stockpile_view.controls.links)
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"transfer surviving links"): return
	for row in editor.observed_links:
		if not check(int(row.id)!=ids[1],"deleted donor remains in rendered links"): return
	await capture("stockpiles_transfer_links")
	await click_control(editor.links_view.add_buttons[1])
	await pointer_click(tile_screen(origin+Vector3i(5,0,0)))
	if not await wait_ui(func(): return settled(),"duplicate link receipt"): return
	if not check(editor.links_picking,"duplicate selection closed picker"): return
	await pointer_click(tile_screen(origin))
	if not await wait_ui(func(): return settled(),"self link selection"): return
	if not check(editor.links_picking and not editor.request_problem and not editor.message.visible and not editor.stockpile_view.controls.links.disabled,"self selection changed picker"): return
	await capture("stockpiles_link_duplicate_self")
	await native("guard_before")
	await pointer_click(tile_screen(origin+Vector3i(1,0,0)))
	if not await wait_ui(func(): return settled(),"empty link target"): return
	if not check(editor.links_picking and not editor.request_problem and not editor.message.visible,"empty ground changed picker"): return
	var dp: Dictionary = fixture.link_door_origin
	var door_tile := Vector3i(int(dp.x),int(dp.y),int(dp.z))
	scene.camera_rig.focus_on(Vector3(door_tile.x+0.5,door_tile.z+1.0,door_tile.y+0.5),30)
	for frame in 12: await process_frame
	await pointer_click(tile_screen(door_tile))
	if not await wait_ui(func(): return settled(),"ineligible door target"): return
	if not check(editor.links_picking and not editor.request_problem and not editor.message.visible,"door changed picker"): return
	await native("guard_after")
	await capture("stockpiles_link_no_target")
	scene.camera_rig.focus_on(Vector3(origin.x+0.5,origin.z+1.0,origin.y+0.5),30)
	for frame in 12: await process_frame
	await click_control(editor.links_view.close)
	await click_control(editor.links_view.add_buttons[0])
	await pointer_click(tile_screen(origin+Vector3i(5,0,0)))
	if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"reversed link receipt"): return
	await native("pile_link",{"id":ids[0],"target_id":ids[2],"give":true,"linked":true})
	await native("pile_link",{"id":ids[0],"target_id":ids[2],"give":false,"linked":false})
	await capture("stockpiles_link_reversed")
	await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"unlink pile receipt"): return
	await native("pile_link",{"id":ids[0],"target_id":ids[2],"give":true,"linked":false})
	var wp: Dictionary = fixture.workshop_origin
	var workshop_tile := Vector3i(int(wp.x),int(wp.y),int(wp.z))
	scene.camera_rig.focus_on(Vector3(workshop_tile.x+0.5,workshop_tile.z+1.0,workshop_tile.y+0.5),30)
	for frame in 12: await process_frame
	for give in [true,false]:
		await click_control(editor.links_view.add_buttons[0 if give else 1])
		await pointer_click(tile_screen(workshop_tile))
		if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"viewport workshop link"): return
		await native("link",{"id":int(fixture.workshop),"pile_id":ids[0],"give":not give,"linked":true})
		await native("link",{"id":int(fixture.workshop),"pile_id":ids[0],"give":give,"linked":false})
		await capture("stockpiles_workshop_give" if give else "stockpiles_workshop_take")
	await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"unlink workshop receipt"): return
	await native("link",{"id":int(fixture.workshop),"pile_id":ids[0],"give":true,"linked":false})
	step = "link target visibility and overlap progression"
	var query := {"action":9,"kind":0,"operation":26,"id":ids[0],"expected_revision":int(editor.selected.revision),"origin":workshop_tile,"give":true}
	await native("guard_before")
	var found := await request(query)
	if not check(found.get("links",[]).size()==1 and int(found.links[0].id)==int(fixture.workshop),"revealed workshop query"): return
	await request(query.merged({"expected_revision":int(editor.selected.revision)+1},true),"Area changed; inspect again")
	var outside := await request(query.merged({"origin":Vector3i(32767,32767,32767)},true))
	if not check(outside.get("links",[]).is_empty(),"outside-map target disclosed a building"): return
	await native("link_hidden_prepare",{"x":workshop_tile.x,"y":workshop_tile.y,"z":workshop_tile.z})
	var hidden := await request(query)
	await native("link_hidden_restore")
	if not check(hidden.get("links",[]).is_empty(),"hidden target disclosed a building"): return
	await native("guard_after")
	var overlap_ids: Array[int] = []
	for offset in [7,9]:
		var made := await request({"action":10,"kind":0,"operation":5,"paint_mode":1,"paint_z":origin.z,
			"spans":[{"x":origin.x+offset,"y":origin.y,"length":1}]})
		if stopped: return
		overlap_ids.append(int(made.areas[0].id))
	await native("link_overlap_prepare",{"targets":overlap_ids,"x":workshop_tile.x,"y":workshop_tile.y,"z":workshop_tile.z})
	for target_id in overlap_ids+[int(fixture.workshop)]:
		await click_control(editor.links_view.add_buttons[0])
		await pointer_click(tile_screen(workshop_tile))
		if not await wait_ui(func(): return settled() and not editor.links_picking and editor.links_pending.is_empty(),"overlapping target receipt"): return
		if target_id==int(fixture.workshop):
			await native("link",{"id":target_id,"pile_id":ids[0],"give":false,"linked":true})
		else: await native("pile_link",{"id":ids[0],"target_id":target_id,"give":true,"linked":true})
	await native("guard_before")
	await click_control(editor.links_view.add_buttons[0])
	await pointer_click(tile_screen(workshop_tile))
	if not await wait_ui(func(): return settled(),"exhausted overlap receipt"): return
	if not check(editor.links_picking and not editor.message.visible,"exhausted overlap changed picker"): return
	await native("guard_after")
	await capture("stockpiles_link_overlap_exhausted")
	await click_control(editor.links_view.close)
	for index in 3:
		await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
		if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"overlap unlink"): return
	await native("link_overlap_restore")
	step = "native four-group link list order"
	var groups := [{"id":overlap_ids[0],"kind":0,"direction":1},{"id":overlap_ids[1],"kind":0,"direction":2},
		{"id":int(fixture.workshop),"kind":2,"direction":1},{"id":int(fixture.second_workshop),"kind":2,"direction":2}]
	for row in groups:
		var current := await inspect(ids[0])
		var edit := {"action":13,"kind":0,"id":ids[0],"link_id":int(row.id),"give":int(row.direction)==1,"expected_revision":current.revision}
		if int(row.kind)==2:
			edit.merge({"operation":15,"kind":2,"id":int(row.id),"link_id":ids[0],"give":int(row.direction)==2},true)
		await request(edit)
		if stopped: return
	editor.use_area(await inspect(ids[0])); editor.stockpile_control("links")
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"four-group rows"): return
	await native("link_rows",{"id":ids[0],"rows":editor.observed_links})
	for index in editor.observed_links.size():
		if not check(editor.links_view.rows_box.get_child(index).get_child(1).text==str(editor.observed_links[index].name),"rendered link row order differs"): return
	await capture("stockpiles_links_four_groups")
	for index in 4:
		var first: Dictionary = editor.observed_links[0].duplicate()
		await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
		if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"ordered first-row removal"): return
		if int(first.kind)==0: await native("pile_link",{"id":ids[0],"target_id":int(first.id),"give":int(first.direction)==1,"linked":false})
		else: await native("link",{"id":int(first.id),"pile_id":ids[0],"give":int(first.direction)==2,"linked":false})
		await native("link_rows",{"id":ids[0],"rows":editor.observed_links})
	await pointer_link_scroll(ids[0])
	if stopped: return
	editor.close_panel()
	for pile_id in [ids[0],ids[2]]+overlap_ids:
		var current := await inspect(pile_id)
		await request({"action":12,"kind":0,"id":pile_id,"expected_revision":current.revision})
		if stopped: return
		await native("removed",{"id":pile_id})

func pointer_link_scroll(source_id: int) -> void:
	step = "native link scrollbar viewport input"
	for target_id in fixture.link_scroll_workshops:
		var current := await inspect(source_id)
		await request({"action":13,"operation":15,"kind":2,"id":int(target_id),"link_id":source_id,"give":true,"expected_revision":current.revision})
		if stopped: return
	editor.use_area(await inspect(source_id)); editor.stockpile_control("links")
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"long link list"): return
	await native("link_rows",{"id":source_id,"rows":editor.observed_links})
	var bar = editor.links_view.scrollbar
	for factor in [1.0,1.5]:
		editor.links_view.scale = Vector2.ONE * factor
		bar.move_to(0)
		for frame in 4: await process_frame
		var point: Vector2 = editor.links_view.body.get_global_transform_with_canvas() * Vector2(100,150)
		for page in [false,true]:
			var wheel := InputEventMouseButton.new(); wheel.position = point; wheel.global_position = point
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true; wheel.shift_pressed = page
			root.push_input(wheel,true); await process_frame; await process_frame
			if not check(bar.first == (10 if page else 1) and editor.links_view.scroll.scroll_vertical == bar.first*36,"link wheel row increment at scale "+str(factor)): return
		bar.move_to(0); await process_frame
		var grip: Vector2i = bar.thumb()
		var start: Vector2 = bar.get_global_transform_with_canvas()*Vector2(8,(grip.x+0.5)*12)
		var finish: Vector2 = bar.get_global_transform_with_canvas()*Vector2(8,bar.size.y-18)
		await pointer_drag(start,finish)
		if not check(bar.first==11 and editor.links_view.scroll.scroll_vertical==396,"link drag end at scale "+str(factor)): return
		await capture("stockpiles_links_scroll_"+str(factor))
	# Remove the first visible row at the scaled bottom, not the offscreen first row.
	var selected_row: Dictionary = editor.observed_links[11].duplicate()
	await click_control(editor.links_view.rows_box.get_child(11).get_child(2))
	if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"scrolled row removal"): return
	await native("link",{"id":int(selected_row.id),"pile_id":source_id,"give":true,"linked":false})
	await native("link_rows",{"id":source_id,"rows":editor.observed_links})
	editor.links_view.scale = Vector2.ONE
	for index in 19:
		bar.move_to(0); await process_frame
		await click_control(editor.links_view.rows_box.get_child(0).get_child(2))
		if not await wait_ui(func(): return settled() and editor.links_pending.is_empty(),"long list cleanup"): return
	await native("link_rows",{"id":source_id,"rows":editor.observed_links})

func pointer_key(key: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new(); event.keycode = key; event.physical_keycode = key; event.pressed = pressed
		root.push_input(event,true)
	await process_frame; await process_frame

func owner_scroll_workflow() -> bool:
	var view = editor.candidates_view
	var bar = view.owner_scrollbar
	var total: int = editor.candidates_state.rows.size()+(1 if view.remove.visible else 0)
	if not check(editor.candidates_state.cursor==0 and bar.count==total and total>32,"owner controls enabled before complete membership"): return false
	for factor in [1.0,0.75]:
		view.scale = Vector2.ONE*factor
		await process_frame
		for probe in [[MOUSE_BUTTON_WHEEL_DOWN,false,1],[MOUSE_BUTTON_WHEEL_DOWN,true,17],[MOUSE_BUTTON_WHEEL_UP,false,16],[MOUSE_BUTTON_WHEEL_UP,true,0]]:
			var wheel := InputEventMouseButton.new(); wheel.pressed=true; wheel.button_index=probe[0];wheel.shift_pressed=probe[1]
			wheel.position=view.scroll.get_global_transform_with_canvas()*Vector2(20,200);wheel.global_position=wheel.position
			root.push_input(wheel,true);await process_frame
			if not check(bar.first==probe[2] and view.scroll.scroll_vertical==int(probe[2])*36 and view.owner_selected==0,"owner wheel row/page or selection changed at scale "+str(factor)):return false
		for probe in [[594,1],[6,0],[400,16],[18,0]]:
			await pointer_click(bar.get_global_transform_with_canvas()*Vector2(8,probe[0]))
			if not check(bar.first==probe[1] and view.owner_selected==0,"owner arrow/track differs at scale "+str(factor)):return false
		var press := InputEventMouseButton.new();press.position=bar.get_global_transform_with_canvas()*Vector2(8,30);press.global_position=press.position
		press.button_index=MOUSE_BUTTON_LEFT;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.pressed=true;root.push_input(press,true)
		var drag := InputEventMouseMotion.new();drag.position=bar.get_global_transform_with_canvas()*Vector2(8,590);drag.global_position=drag.position;drag.button_mask=MOUSE_BUTTON_MASK_LEFT
		root.push_input(drag,true)
		var release := InputEventMouseButton.new();release.position=drag.position;release.global_position=release.position;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
		root.push_input(release,true);await process_frame;await process_frame
		if not check(bar.first==total-16 and view.scroll.scroll_vertical==(total-16)*36 and view.owner_selected==0 and not bar.dragging,"owner tail drag differs at scale "+str(factor)):return false
		if factor==1.0:
			var first_unit: int = bar.first-(1 if view.remove.visible else 0)
			if not await wait_ui(func():return view.portrait_slots[first_unit].view.texture!=null,"owner tail portrait"):return false
			var clip: Rect2 = view.scroll.get_global_rect()
			var complete := 0
			for button in view.choices:
				if clip.encloses(button.get_global_rect()):complete+=1
				elif clip.intersects(button.get_global_rect()):
					check(false,"owner tail includes partial row");return false
			if not check(complete==16,"owner tail does not show 16 complete rows"):return false
			await capture("zone_owner_scroll_tail")
		# Drag back to the top independently of keyboard selection.
		press.position=bar.get_global_transform_with_canvas()*Vector2(8,570);press.global_position=press.position;root.push_input(press,true)
		drag.position=bar.get_global_transform_with_canvas()*Vector2(8,6);drag.global_position=drag.position;root.push_input(drag,true)
		release.position=drag.position;release.global_position=release.position;root.push_input(release,true);await process_frame
		if not check(bar.first==0 and view.owner_selected==0,"owner drag did not return to top"):return false
	view.scale=Vector2.ONE;await process_frame
	for index in range(ceili(float(total)/16)+1): await pointer_key(KEY_PAGEDOWN)
	await pointer_key(KEY_DOWN)
	if not check(view.owner_selected==total-1 and bar.first==total-16,"owner keyboard tail clamp"):return false
	await pointer_key(KEY_PAGEUP)
	if not check(view.owner_selected==total-17 and bar.first==total-17,"owner Page Up from tail"):return false
	for index in range(ceili(float(total)/16)+1): await pointer_key(KEY_PAGEUP)
	if not check(view.owner_selected==0 and bar.first==0,"owner keyboard return to top"):return false
	return true

func pointer_owner(id: int, origin: Vector3i) -> void:
	step = "pointer owner selector"
	await click_control(editor.zone_menu.controls.owner)
	if not await wait_ui(func(): return settled() and not editor.candidates_state.busy() and not editor.candidates_state.rows.is_empty(),"owner rows"): return
	if not await owner_scroll_workflow(): return
	var help = editor.candidates_view.native_help
	var hover := InputEventMouseMotion.new()
	hover.position=editor.candidates_view.owner_search.get_global_rect().get_center();hover.global_position=hover.position
	root.push_input(hover,true);await process_frame
	if not check(help.displayed=="owner_filter" and not editor.hud.minimap_layer.visible,"filter hover did not immediately replace minimap"):return
	await capture("zone_owner_filter_help")
	hover=InputEventMouseMotion.new();hover.position=Vector2(800,700);hover.global_position=hover.position
	root.push_input(hover,true);await process_frame
	if not check(not help.visible and editor.hud.minimap_layer.visible,"filter pointer leave did not restore minimap"):return
	var help_target: Button
	for button in editor.candidates_view.focus_buttons:
		if not button.disabled and editor.candidates_view.scroll.get_global_rect().encloses(button.get_global_rect()):help_target=button;break
	if not check(help_target!=null,"no owner recenter hover target"):return
	hover=InputEventMouseMotion.new();hover.position=help_target.get_global_rect().get_center();hover.global_position=hover.position
	root.push_input(hover,true);await process_frame
	if not check(not help.visible,"filter tooltip incorrectly warmed recenter delay"):return
	if not await wait_ui(func():return help.displayed=="owner_recenter","owner recenter hover delay"):return
	await capture("zone_owner_recenter_help")
	await pointer_click(Vector2(800,700),MOUSE_BUTTON_RIGHT)
	if not check(editor.stockpile_page=="types" and not help.visible and editor.hud.minimap_layer.visible,"closed owner picker retained tooltip"):return
	await click_control(editor.zone_menu.controls.owner)
	if not await wait_ui(func():return settled() and not editor.candidates_state.busy() and not editor.candidates_state.rows.is_empty(),"owner rows after tooltip close"):return
	var refreshed_unit := int(editor.candidates_state.rows[0].id)
	var refreshed_button: Button = editor.candidates_view.choices[0]
	var refresh_receipt := int(editor.candidates_state.receipt)
	var original_line := str(editor.candidates_state.rows[0].owner_display.first_line)
	editor.candidates_view.owner_search.grab_focus()
	await native("owner_fact_name",{"unit_id":refreshed_unit,"name":"OwnerFactsLive"})
	if not await wait_ui(func():return str(editor.candidates_state.rows[0].owner_display.first_line).contains("OwnerFactsLive"),"automatic owner name refresh"):return
	if not check(editor.candidates_view.choices[0]==refreshed_button and editor.candidates_state.receipt==refresh_receipt and editor.candidates_view.owner_search.has_focus() and not editor.candidates_state.busy(),"background owner refresh changed controls, receipt or input"):return
	await capture("zone_owner_facts_refreshed")
	await native("owner_fact_restore")
	if not await wait_ui(func():return str(editor.candidates_state.rows[0].owner_display.first_line)==original_line,"automatic owner name restoration"):return
	var shortcut := InputEventKey.new(); shortcut.pressed=true; shortcut.keycode=KEY_F; shortcut.ctrl_pressed=true
	root.push_input(shortcut,true)
	if not check(editor.candidates_view.owner_search.has_focus(),"Ctrl+F did not focus owner filter"):return
	for sample in [233,-1,-1,77,73,78,69,82]:
		var key := InputEventKey.new(); key.pressed = true
		if sample < 0: key.keycode = KEY_BACKSPACE
		else: key.unicode = sample
		root.push_input(key,true)
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner byte filter"): return
		var ids: Array=[]
		for row in editor.candidates_state.rows: ids.append(int(row.id))
		# These samples are small except the empty query, which must page fully.
		while editor.candidates_state.cursor != 0:
			editor.candidates_state.more()
			if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner filtered continuation"): return
		ids=[]
		for row in editor.candidates_state.rows: ids.append(int(row.id))
		await native("zone_owner_candidates",{"id":id,"ids":ids,"query_bytes":Array(editor.candidates_state.query_bytes)})
		if stopped: return
	await capture("zone_owner_byte_filter")
	var enter := InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER;root.push_input(enter,true)
	if not check(not editor.candidates_view.owner_search.has_focus() and editor.stockpile_page=="owner","focused Enter assigned owner"):return
	await native("snapshot",{"id":id,"expected":{"owner_id":-1}})
	# Cancel and reopen restores the unfiltered candidate snapshot.
	root.push_input(shortcut,true)
	await pointer_click(Vector2(800,700),MOUSE_BUTTON_RIGHT)
	if not check(editor.stockpile_page=="owner" and not editor.candidates_view.owner_search.has_focus(),"first right-click must leave only textbox focus"):return
	await pointer_click(Vector2(800,700),MOUSE_BUTTON_RIGHT)
	if not check(editor.stockpile_page=="types" and editor.panel.visible,"second right-click must close only owner picker"):return
	await click_control(editor.zone_menu.controls.owner)
	if not await wait_ui(func():return settled() and not editor.candidates_state.busy(),"reopened owner rows"):return
	await verify_candidate_rows(id,1)
	if stopped: return
	var recipe_receipt := int(editor.candidates_state.receipt)
	var recipe_count: int = editor.candidates_state.rows.size()
	var first_recipe_button: Button = editor.candidates_view.choices[0]
	for direction in [KEY_PAGEDOWN,KEY_PAGEUP]:
		for page_index in 4:
			var paging := InputEventKey.new();paging.pressed=true;paging.keycode=direction;root.push_input(paging,true)
			await process_frame
		var first_visible := maxi(0,int(editor.candidates_view.scroll.scroll_vertical/36)-1)
		if direction==KEY_PAGEDOWN and not check(first_visible>36,"owner paging did not reach an evicted recipe"):return
		if not await wait_ui(func():return editor.candidates_state.rows[first_visible].has("sheet_icon") and editor.candidates_view.portrait_slots[first_visible].view.texture!=null,"scrolled owner portrait reacquisition"):return
		var retained := 0
		for row in editor.candidates_state.rows:
			if row.has("sheet_icon"):retained+=1
		if not check(retained<=36 and editor.candidates_state.rows.size()==recipe_count and editor.candidates_state.receipt==recipe_receipt and editor.candidates_view.choices[0]==first_recipe_button,"owner recipe window changed membership, controls or retention bound"):return
		if direction==KEY_PAGEDOWN and not check(not editor.candidates_state.rows[0].has("sheet_icon"),"distant scroll retained first portrait recipe"):return
		await capture("zone_owner_recipe_away" if direction==KEY_PAGEDOWN else "zone_owner_recipe_return")
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
	var recenter_area: Dictionary = editor.selected.duplicate(true)
	for method in ["click","control-c"]:
		var before_recenter := receipts.size()
		if method=="click": await click_control(editor.candidates_view.focus_buttons[index])
		else:
			for row_step in index+1:
				var navigation := InputEventKey.new();navigation.pressed=true;navigation.keycode=KEY_DOWN;root.push_input(navigation,true)
			var recenter := InputEventKey.new();recenter.pressed=true;recenter.keycode=KEY_C;recenter.ctrl_pressed=true;root.push_input(recenter,true)
		if not check(not editor.panel.visible and host.active==null,"owner recenter did not leave Zones: "+method):return
		if not check(is_equal_approx(scene.camera_rig.position.x,tile.x+0.5) and is_equal_approx(scene.camera_rig.position.z,tile.y+0.5),"owner recenter did not focus observed unit"): return
		if not check(receipts.size()==before_recenter,"owner recenter submitted a mutation"):return
		await capture("zone_owner_recenter_"+method)
		await native("snapshot",{"id":id,"expected":{"owner_id":-1}})
		editor.open_panel()
		if not await wait_ui(func(): return settled() and editor.available,"owner recenter reopen Zones"):return
		editor.use_area(recenter_area);editor._process(0)
		await click_control(editor.zone_menu.controls.owner)
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner recenter reopen picker"):return
		index=-1
		for candidate in editor.candidates_state.rows.size():
			if int(editor.candidates_state.rows[candidate].id)==unit:index=candidate;break
		if not check(index>=0,"recenter target absent from reopened owner list"):return
	write_json("owner-key-before.json",{"index":index,"selected":editor.candidates_view.owner_selected,"busy":editor.candidates_state.busy(),"focused":editor.candidates_view.owner_search.has_focus(),"allowed":host.allows_panel_input(editor),"visible":editor.candidates_view.is_visible_in_tree(),"ticket":editor.request_ticket,"page":editor.stockpile_page})
	for row_step in index+1:
		var down := InputEventKey.new(); down.pressed=true; down.keycode=KEY_DOWN;root.push_input(down,true)
	if not check(editor.candidates_view.owner_selected==index+1,"owner Down did not select intended row"):return
	var choose := InputEventKey.new(); choose.pressed=true; choose.keycode=KEY_ENTER
	root.push_input(choose,true); root.push_input(choose,true)
	write_json("owner-key-after.json",{"selected":editor.candidates_view.owner_selected,"busy":editor.candidates_state.busy(),"mutating":editor.candidates_state.mutating,"ticket":editor.request_ticket,"page":editor.stockpile_page})
	if not check(editor.candidates_state.mutating,"owner Enter did not submit assignment"):return
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
	var escape_area: Dictionary = editor.selected.duplicate(true)
	# Escape follows native Options routing both with and without filter focus.
	for focused in [false,true]:
		await click_control(editor.zone_menu.controls.owner)
		if not await wait_ui(func(): return settled() and not editor.candidates_state.busy(),"owner Escape rows"): return
		if focused: root.push_input(shortcut,true)
		var before_escape := receipts.size()
		await pointer_key(KEY_ESCAPE)
		if not check(not editor.panel.visible and scene._ui.native_options.visible and host.overlay_blocked,"owner Escape did not open Options"): return
		if not check(receipts.size()==before_escape,"owner Escape submitted a mutation"): return
		await capture("zone_owner_escape_"+str(focused))
		await pointer_key(KEY_ESCAPE)
		if not check(not scene._ui.native_options.visible and not host.overlay_blocked,"Options Escape did not release input"): return
		editor.open_panel()
		if not await wait_ui(func(): return settled() and editor.available,"Zones reopen after Options"): return
		editor.use_area(escape_area); editor._process(0)
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
			scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
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

func pointer_zone_overlap(origin: Vector3i, first_id: int) -> void:
	step = "viewport native zone overlap"
	var first_revision: int = editor.selected.revision
	if not check(int(editor.selected.overlapping) == 0 and not editor.zone_menu.overlap_label.visible,"new isolated bedroom must be clear"): return
	await native("snapshot",{"id":first_id,"expected":{"overlapping":0}})
	await click_control(editor.zone_menu.buttons.MeetingHall)
	var target := Vector3(origin.x+0.5,origin.z+float(world.floor_height()),origin.y+0.5)
	var position: Vector2 = editor.camera.unproject_position(target)
	for corner in 2:
		await pointer_click(position)
		if not await wait_ui(settled,"overlapping zone corner"): return
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"overlapping zone Accept"): return
	var second_id := int(editor.selected.id)
	if not check(second_id != first_id and int(editor.selected.overlapping) == 1,"second zone must observe native overlap"): return
	if not check(editor.zone_menu.overlap_label.visible and editor.zone_menu.type_label.get_theme_color("font_color") == Color.RED,"native red heading missing"): return
	await native("snapshot",{"id":first_id,"expected":{"overlapping":1}})
	await native("snapshot",{"id":second_id,"expected":{"overlapping":1}})
	await capture("zone_overlapping")
	await pointer_zone_names(second_id,position)
	if stopped: return
	await pointer_zone_overlap_repaint(origin,first_id,second_id,position)
	if stopped: return
	await request({"action":11,"kind":1,"id":first_id,"expected_revision":first_revision,"active":0},"Area changed; inspect again")
	if stopped: return
	await native("snapshot",{"id":first_id,"expected":{"active":true,"overlapping":1}})
	# Map selection and the native previous-zone control must refresh the old zone.
	await pointer_click(position)
	if not await wait_ui(settled,"overlap map selection"): return
	await click_control(editor.zone_menu.controls.previous)
	if not await wait_ui(settled,"previous overlapping zone"): return
	if not check(int(editor.selected.id) == first_id and int(editor.selected.revision) != first_revision and int(editor.selected.overlapping) == 1,"old zone overlap/revision did not refresh"): return
	await capture("zone_overlap_previous")
	await native("overlap_prepare",{"scenario":"floor","site":{"x":origin.x,"y":origin.y,"z":origin.z}})
	await click_control(editor.zone_menu.controls.repaint)
	await click_control(editor.paint_view.buttons.remove)
	if not await wait_ui(func(): return settled() and editor.selected.is_empty(),"remove overlapping zone"): return
	await native("removed",{"id":first_id})
	await native("snapshot",{"id":second_id,"expected":{"overlapping":0}})
	await native("overlap_measure",{"require_unchanged":true})
	await native("overlap_clear")
	await pointer_click(position)
	if not await wait_ui(func(): return settled() and int(editor.selected.get("id",-1)) == second_id,"select surviving zone"): return
	if not check(int(editor.selected.overlapping)==0 and not editor.zone_menu.overlap_label.visible and not editor.zone_menu.type_label.has_theme_color_override("font_color"),"survivor retained overlap heading after removal"): return
	await capture("zone_overlap_survivor")
	# An unrelated isolated selection must also remain clear.
	await click_control(editor.zone_menu.buttons.Bedroom)
	var isolated := origin+Vector3i(2,0,0)
	position = editor.camera.unproject_position(Vector3(isolated.x+0.5,isolated.z+float(world.floor_height()),isolated.y+0.5))
	for corner in 2:
		await pointer_click(position)
		if not await wait_ui(settled,"isolated zone corner"): return
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"isolated zone Accept"): return
	if not check(int(editor.selected.overlapping) == 0 and not editor.zone_menu.overlap_label.visible and not editor.zone_menu.type_label.has_theme_color_override("font_color"),"clear selection retained overlap heading"): return
	await native("snapshot",{"id":int(editor.selected.id),"expected":{"overlapping":0}})
	await capture("zone_overlap_clear")
	await native("final")

func pointer_zone_names(id: int, position: Vector2) -> void:
	step = "viewport native meeting names"
	if not check(editor.selected.name == "Unnamed meeting hall","empty meeting area name differs from native"): return
	for entry in [["empty","meeting hall",[]],["coffin","memorial hall",["coffin"]],["slab","memorial hall",["slab"]],
		["statue","sculpture garden",["statue"]],["cage","zoo",["cage"]],["chain","zoo",["chain"]],["display","museum",["display"]],
		["statue-cage-tie","zoo",["statue","cage"]],["statue-display-tie","museum",["statue","display"]],
		["cage-display-tie","museum",["cage","display"]],["memorial-priority","memorial hall",["coffin","statue","statue","cage","display"]]]:
		var previous: Dictionary = editor.selected.duplicate(true)
		await native("zone_name_contents",{"id":id,"members":entry[2]})
		await pointer_click(position)
		if not await wait_ui(settled,"meeting contents refresh"): return
		var expected: String = "Unnamed "+str(entry[1])
		if not check(editor.selected.name == expected and editor.zone_menu.heading.text == expected,"meeting heading differs: "+str(entry[0])): return
		if str(previous.name) != expected:
			if not check(int(previous.revision) != int(editor.selected.revision),"changed meeting heading retained revision"): return
		if entry[0] in ["statue","display","memorial-priority"]: await capture("meeting_name_"+str(entry[0]))
	await native("zone_name_restore")
	await pointer_click(position)
	if not await wait_ui(settled,"restored meeting contents"): return
	if not check(editor.selected.name == "Unnamed meeting hall","restored empty meeting heading"): return

func pointer_zone_overlap_repaint(origin: Vector3i, first_id: int, second_id: int, position: Vector2) -> void:
	step = "viewport native repaint overlap effects"
	await native("overlap_prepare",{"scenario":"floor","site":{"x":origin.x,"y":origin.y,"z":origin.z}})
	await click_control(editor.zone_menu.controls.repaint)
	await click_control(editor.paint_view.buttons.erase)
	for corner in 2:
		await pointer_click(position)
		if not await wait_ui(settled,"zone erase corner"): return
	await native("snapshot",{"id":second_id,"expected":{"overlapping":0,"tile_count":0}})
	await native("overlap_result",{"ids":[first_id,second_id],"expected":false})
	if not check(editor.paint_session != null and int(editor.paint_session.area.overlapping) == 0 and editor.paint_view.accept_button.disabled,"empty repaint must retain clear zone with disabled Accept"): return
	# The native reference capture moves the pointer off the map. Match that
	# state rather than comparing a live hover preview against an idle caption.
	var motion := InputEventMouseMotion.new()
	motion.position = editor.paint_view.accept_button.get_global_rect().get_center()
	motion.global_position = motion.position; root.push_input(motion,true)
	await process_frame
	if not await wait_ui(func(): return settled() and not editor.paint_counts.values.is_empty(),"empty repaint count observation"): return
	write_json("zone_empty_paint_counts.json",{"values":editor.paint_counts.values,"caption":editor.paint_view.zone_caption.text})
	if not check(int(editor.paint_counts.values.get("painted",-1)) == 0 and int(editor.paint_counts.values.get("preview",-1)) == 0,"empty repaint count differs from native 0 + 0"): return
	if not check(editor.paint_view.zone_caption.text.ends_with(": 0 + 0"),"empty repaint count caption missing"): return
	await capture("zone_repaint_overlap_erased")
	await click_control(editor.paint_view.buttons.erase)
	for corner in 2:
		await pointer_click(position)
		if not await wait_ui(settled,"zone regrow corner"): return
	await native("snapshot",{"id":second_id,"expected":{"overlapping":1,"tile_count":1}})
	await native("overlap_result",{"ids":[first_id,second_id],"expected":true})
	await native("overlap_clear")
	await click_control(editor.paint_view.accept_button)
	if not await wait_ui(func(): return settled() and editor.mode == "inspect","zone regrow Accept"): return
	if not check(editor.zone_menu.overlap_label.visible,"regrown zone warning missing"): return
	await capture("zone_repaint_overlap_regrown")

func pointer_animals(id: int) -> void:
	step="main scene animal picker"
	await click_control(editor.zone_menu.controls.animals)
	if not await wait_ui(func():return settled() and not editor.candidates_state.busy(),"pointer animal open"):return
	if not await wait_ui(func():
		for slot in editor.candidates_view.portrait_slots:
			if slot.view.texture==null:return false
		return not editor.candidates_view.portrait_slots.is_empty(),"animal visible portraits"):return
	await capture("animal_picker")
	var panel_reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_panel_pixels
	var panel_image:=root.get_texture().get_image();panel_image.convert(Image.FORMAT_RGB8)
	for sample in panel_reference.samples:
		var r:Array=sample.rect;var crop:=panel_image.get_region(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])))
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if not check(digest.finish().hex_encode()==str(sample.rgb_sha256),"animal native panel pixels differ: "+str(sample.name)):return
	var view=editor.candidates_view
	if not check(view.body.global_position==Vector2(376,64) and view.size==Vector2(392,708),"animal native panel geometry differs: body="+str(view.body.global_position)+" panel="+str(view.size)):return
	var unit_index:=-1
	for index in editor.candidates_state.rows.size():
		var row:Dictionary=editor.candidates_state.rows[index]
		if int(row.get("entity",0))==1 and int(row.id)==int(fixture.caged):unit_index=index;break
	if not check(unit_index>=0,"caged unit absent from Pond picker"):return
	var target=view.choices[unit_index].get_node_or_null("AnimalContainmentHover")
	if not check(target!=null,"caged unit has no containment hover"):return
	var motion:=InputEventMouseMotion.new();motion.position=target.get_global_rect().get_center();motion.global_position=motion.position
	root.push_input(motion,true)
	if not await wait_ui(func():return view.native_help.visible,"animal containment hover"):return
	await capture("animal_containment_hover")
	var unit:=int(fixture.caged)
	await native("assignment_before",{"unit_id":unit})
	for assigned in [true,false]:
		unit_index=-1
		for index in editor.candidates_state.rows.size():
			var row:Dictionary=editor.candidates_state.rows[index]
			if int(row.get("entity",0))==1 and int(row.id)==unit:unit_index=index;break
		if not check(unit_index>=0,"assigned unit disappeared"):return
		await pointer_click(view.choices[unit_index].global_position+Vector2(296,18))
		if not await wait_ui(func():return settled() and not editor.candidates_state.busy(),"pointer animal checkbox"):return
		await native("assignment",{"id":id,"unit_id":unit,"assign":assigned})
		if stopped:return
	var item:=int(fixture.critter)
	await native("item_assignment_before",{"item_id":item})
	for assigned in [true,false]:
		var item_index:=-1
		for index in editor.candidates_state.rows.size():
			var row:Dictionary=editor.candidates_state.rows[index]
			if int(row.get("entity",0))==2 and int(row.id)==item:item_index=index;break
		if not check(item_index>=0,"critter item absent"):return
		await pointer_click(view.choices[item_index].global_position+Vector2(296,18))
		if not await wait_ui(func():return settled() and not editor.candidates_state.busy(),"pointer item checkbox"):return
		await native("item_assignment",{"id":id,"item_id":item,"assign":assigned})
		if stopped:return
	await capture("animal_cleared")
	await pointer_click(Vector2(800,700),MOUSE_BUTTON_RIGHT)
	if not check(editor.stockpile_page=="types" and not view.visible,"animal right-click did not close selector"):return
