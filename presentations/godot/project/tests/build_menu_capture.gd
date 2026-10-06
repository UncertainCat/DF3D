extends SceneTree
const Menu = preload("res://scripts/build_menu_view.gd")
var directory: String

func _initialize() -> void:
	call_deferred("run")

func catalog(rows: Array, result: Array) -> void:
	for row in rows:
		if row.has("children"): catalog(row.children, result)
		else:
			var key := str(row.catalog_key)
			var reason := ""
			if "Magma" in key: reason = "Magma placement rule not captured"
			elif key == "Windmill": reason = "Windmill placement rule not captured"
			result.append({"key":key,"supported":reason.is_empty(),"reason":reason})

func capture(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK

func pressure_pointer(controller, kind: String, value: int) -> bool:
	var target: BaseButton
	for control in controller.pressure_view.find_children("*","BaseButton",true,false):
		if control.get_meta("pressure_kind","") == kind and control.get_meta("pressure_value",-999) == value: target = control
	if target == null or target.disabled: push_error("Pressure pointer target absent: " + kind); return false
	var point := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new(); motion.position = point
	root.push_input(motion,true); await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.position = point
		root.push_input(event,true); await process_frame
	print("PRESSURE_POINTER ",kind,"=",value," profile=",controller.draft.pressure_plate)
	return true

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Build menu captures require a real renderer")
		quit(77); return
	directory = OS.get_environment("DF3D_BUILD_MENU_CAPTURE")
	if directory.is_empty(): directory = ProjectSettings.globalize_path("res://../../../build/qa/03-U")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: quit(1); return
	root.size = Vector2i(1200,800)
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	var menu := Menu.new(); root.add_child(menu); menu.configure(assets)
	var rows: Array = []; catalog(menu.entries, rows); menu.set_catalog(rows)
	menu.layout(Vector2(1200,800),Vector2(568,760))
	var captures := {"top":[],"workshops":[0],"clothing_leather":[0,0],"farming":[0,1],"furnaces":[0,2],"furniture":[1],"doors_hatches":[2],"constructions":[3],"machines_fluids":[4],"cages_restraints":[5],"traps":[6],"military":[7]}
	for name in captures:
		menu.open()
		var choices: Array = captures[name]
		for level in choices.size(): menu.activate(level,int(choices[level]))
		if not await capture(name): quit(1); return
	menu.free()
	# Exercise the connected controller, not just isolated widget rendering.
	var test = preload("res://tests/construction_test.gd")
	var world = test.FakeWorld.new(); world.assets = assets; root.add_child(world)
	var interaction = test.FakeInteraction.new(); root.add_child(interaction)
	var service = preload("res://scripts/semantic_action_service.gd").new(); service.configure(world); root.add_child(service); service.set_process(false)
	var host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	var controller = preload("res://scripts/construction.gd").new()
	controller.world = world; controller.action_service = service; controller.ui_host = host; controller.interaction = interaction
	controller.camera = Camera3D.new(); root.add_child(controller.camera); root.add_child(controller); host.register(controller); controller.set_process(false)
	var definitions: Array = []
	for entry in [["Bridge","Bridge",31,2],["SiegeEngine:Ballista","SiegeEngine",255,1],["Rollers","Rollers",15,2],["TradeDepot","TradeDepot",1,1],["Construction:Wall","Construction",1,3]]:
		var definition := {"key":entry[0],"name":entry[0],"family":entry[1],"supported":true,"reason":"","width":1,"height":1,"orientations":entry[2],"area_mode":entry[3],"max_width":31,"max_height":31,"max_depth":1,"footprints":[]}
		for direction in 8:
			if int(entry[2]) & (1 << direction): definition.footprints.append({"direction":direction,"width":1,"height":1,"center_x":0,"center_y":0})
		definitions.append(definition)
	controller.open_panel(); service.poll()
	definitions.append({"key":"Trap:TrackStop","name":"Track stop","family":"Trap","subtype_key":"TrackStop","supported":true,"reason":"","width":1,"height":1,"orientations":1,"area_mode":1,"max_width":1,"max_height":1,"max_depth":1,"footprints":[{"direction":0,"width":1,"height":1,"center_x":0,"center_y":0}]})
	definitions.append({"key":"Trap:PressurePlate","name":"Pressure plate","family":"Trap","subtype_key":"PressurePlate","supported":true,"reason":"","width":1,"height":1,"orientations":1,"area_mode":1,"max_width":1,"max_height":1,"max_depth":1,"footprints":[{"direction":0,"width":1,"height":1,"center_x":0,"center_y":0}]})
	world.result = {"world_epoch":1,"revision":1,"request_seq":world.calls.size(),"status":2,"action":0,"catalog":definitions,"construction":{"list_revision":1}}
	service.poll()
	for pair in [["Bridge","controller_bridge"],["SiegeEngine:Ballista","controller_ballista"],["Rollers","controller_rollers"]]:
		controller.choose_definition(pair[0])
		if not await capture(pair[1]): quit(1); return
	controller.choose_definition("Rollers")
	for speed in [10000,20000,30000,40000,50000]:
		var target: TextureButton
		for child in controller.orientation.get_children():
			if child.get_meta("roller_speed",0) == speed: target = child
		if target == null or target.disabled: push_error("Roller speed target missing"); quit(1); return
		for pressed in [true,false]:
			var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
			event.position=target.get_global_rect().get_center(); root.push_input(event,true)
			await process_frame
		if controller.draft.roller_speed != speed: push_error("Pointer did not select Roller speed"); quit(1); return
		if not await capture("controller_rollers_%d" % speed): quit(1); return
	controller.choose_definition("Trap:TrackStop")
	for dump in 5:
		for friction in [10,50,500,10000,50000]:
			for option in [["dump_direction",dump],["friction",friction]]:
				var target: TextureButton
				for child in controller.orientation.get_children():
					if child.get_meta("track_option","") == option[0] and child.get_meta("track_value",-1) == option[1]: target=child
				if target == null or target.disabled: push_error("TrackStop option target missing"); quit(1); return
				for pressed in [true,false]:
					var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
					event.position=target.get_global_rect().get_center(); root.push_input(event,true); await process_frame
			if controller.draft.request(2).track_stop != {"friction":friction,"dump_direction":dump}: push_error("TrackStop pointer choice lost"); quit(1); return
			if not await capture("controller_track_stop_%d_%d" % [dump,friction]): quit(1); return
	var pressure_fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../fixtures/construction/pressure_plate.json")))
	controller.pressure_creatures.clear()
	for row in pressure_fixture.creature_choices: controller.pressure_creatures.append({"size":int(row.size),"race_id":int(row.race_id),"name":str(row.get("name",""))})
	controller.choose_definition("Trap:PressurePlate")
	if not await capture("controller_pressure_default"): quit(1); return
	for option in [["water",1],["magma",1],["track",1],["units",1],["citizens",1],["resets",0],["water_depth",3],["magma_depth",0],["track_min",1],["creature",6000]]:
		if not await pressure_pointer(controller,option[0],option[1]): quit(1); return
	var pressure: Dictionary = controller.draft.request(2).pressure_plate
	if not pressure.water or not pressure.magma or not pressure.track or not pressure.units or not pressure.citizens or pressure.resets or pressure.water_min != 3 or pressure.water_max != 3 or pressure.track_min != 50 or pressure.unit_min != 6000 or pressure.unit_max != 6999:
		push_error("Pressure pointer choices did not reach profile"); quit(1); return
	if not await capture("controller_pressure_enabled"): quit(1); return
	if not await pressure_pointer(controller,"resets",0): quit(1); return
	if controller.draft.pressure_plate.resets: push_error("Repeated One use only changed mode"); quit(1); return
	for on_bar in [false,true]:
		for wheel in [[MOUSE_BUTTON_WHEEL_DOWN,false,1],[MOUSE_BUTTON_WHEEL_DOWN,true,16],[MOUSE_BUTTON_WHEEL_UP,false,15],[MOUSE_BUTTON_WHEEL_UP,true,0]]:
			var event := InputEventMouseButton.new(); event.button_index = wheel[0]; event.shift_pressed = wheel[1]; event.pressed = true
			event.position = controller.pressure_view.scrollbar.global_position + Vector2(8,90) if on_bar else controller.pressure_view.rows.global_position + Vector2(40,90)
			root.push_input(event,true); await process_frame
			event.pressed = false; root.push_input(event,true); await process_frame
			if controller.pressure_first != wheel[2]: push_error("Pressure wheel/page result differs from native capture"); quit(1); return
	var drag_bar = controller.pressure_view.scrollbar
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = drag_bar.global_position + Vector2(8,18)
	root.push_input(down,true); await process_frame
	for motion in [[90,85],[150,156],[174,185],[6,0]]:
		var event := InputEventMouseMotion.new(); event.button_mask = MOUSE_BUTTON_MASK_LEFT; event.position = drag_bar.global_position + Vector2(8,motion[0])
		root.push_input(event,true); await process_frame
		if controller.pressure_first != motion[1]: push_error("Pressure drag result differs from native capture"); quit(1); return
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = drag_bar.global_position + Vector2(8,6)
	root.push_input(up,true); await process_frame
	if drag_bar.dragging: push_error("Pressure scrollbar kept dragging after release"); quit(1); return
	for i in 200:
		var bar = controller.pressure_view.scrollbar
		var point: Vector2 = bar.global_position + Vector2(8,bar.size.y-6)
		for pressed in [true,false]:
			var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.position = point
			root.push_input(event,true); await process_frame
	if controller.pressure_first != 185: push_error("Pressure arrow scroll did not reach bottom"); quit(1); return
	if not await pressure_pointer(controller,"creature",200000): quit(1); return
	if controller.draft.pressure_plate.unit_max != 200999: push_error("Pressure final selected band widened incorrectly"); quit(1); return
	if not await capture("controller_pressure_final"): quit(1); return
	for i in 2:
		if not await pressure_pointer(controller,"creature",186000): quit(1); return
	if controller.draft.pressure_plate.unit_min != 186000 or controller.draft.pressure_plate.unit_max != 186999: push_error("Unnamed band pointer selection differs"); quit(1); return
	if not await capture("controller_pressure_unnamed"): quit(1); return
	print("PRESSURE_CONTROLS_POINTER_PASS")
	controller.choose_definition("TradeDepot"); controller.target_tile(Vector3i(10,10,1),true); service.poll()

	world.result = {"world_epoch":1,"revision":2,"request_seq":world.calls.size(),"status":2,"action":1,"placement_valid":true,"construction":{"filters":[{"index":0,"quantity":3}],"valid_mask":[1],"pieces":[0]}}
	service.poll()
	world.result = {"world_epoch":1,"revision":3,"request_seq":world.calls.size(),"status":2,"action":63,"next_cursor":0,"construction":{"filter":0,"build_phase":0,"list_revision":8,"total":2,"materials":[
		{"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":1,"name":"talc","caption":"","count":81},
		{"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":2,"name":"chert","caption":"","count":4}]}}
	service.poll(); controller.select_material(0,0,1)
	if not await capture("controller_materials"): quit(1); return
	controller.handle_back(); controller.choose_definition("Construction:Wall")
	controller.target_tile(Vector3i(10,10,1),true); controller.target_tile(Vector3i(10,10,1),true); service.poll()
	world.result = {"world_epoch":1,"revision":4,"request_seq":world.calls.size(),"status":2,"action":1,"placement_valid":true,"construction":{"filters":[{"index":0,"quantity":1}],"valid_mask":[1],"pieces":[0]}}
	service.poll()
	world.result = {"world_epoch":1,"revision":5,"request_seq":world.calls.size(),"status":2,"action":63,"construction":{"filter":0,"build_phase":0,"list_revision":9,"total":1,"materials":[{"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":1,"name":"talc","caption":"","count":81}]}}
	service.poll(); controller.keep_building.button_pressed = true; controller.select_material(0,0,1); service.poll()
	world.result = {"world_epoch":1,"revision":6,"request_seq":world.calls.size(),"status":2,"action":2,"construction":{"first_building":22,"placed":1,"skipped":0}}
	service.poll(); controller.set_material_strategy("last")
	if not await capture("controller_last_material"): quit(1); return
	controller.close_panel(); controller.free(); host.free(); service.free(); world.free(); interaction.free(); assets.free()
	await process_frame
	# Preview the candidate launcher in the composed fixture HUD. Its product
	# registry remains hidden until protected live acceptance is complete.
	OS.set_environment("DF3D_FIXTURE",ProjectSettings.globalize_path("res://../../../fixtures/synthetic/demo_fort.df3dfix"))
	var preferences = preload("res://scripts/presentation_settings.gd")
	preferences.loaded = true; preferences.ui_scale = 1.0
	var scene = load("res://scenes/main.tscn").instantiate(); root.add_child(scene)
	for frame in 12: await process_frame
	scene.set_process(false)
	var hud = scene._fortress_hud
	var editor = scene._ui.controller("construction")
	editor.set_process(false)
	hud.update_state(true,true,{"fort_name":"Fixture fortress","paused":true})
	hud.navigation["Build / construction"].pressed.emit()
	editor.menu.set_catalog(rows)
	for resolution in [Vector2i(1200,800),Vector2i(1920,1080)]:
		root.size = resolution
		for factor in [1.0,1.25]:
			preferences.ui_scale = factor
			hud.update_state(true,true,{"fort_name":"Fixture fortress","paused":true})
			hud.navigation["Build / construction"].show()
			for frame in 4:
				hud.layout(hud.logical_view_size()); await process_frame
			editor._process(0)
			editor.menu.open(); editor.menu.activate(0,0); editor.menu.activate(1,1)
			if not await capture("hud_build_%d_%d" % [resolution.x,roundi(factor*100)]): quit(1); return
			var launcher: Rect2 = hud.navigation["Build / construction"].get_global_rect()
			assert(editor.menu.get_rect().end.y <= launcher.position.y,"menu stays above native toolbar")
			assert(editor.menu.get_rect().end.x <= hud.logical_view_size().x,"cascading menu fits scaled HUD")
			assert(editor.canvas.scale == hud.scale,"construction uses the HUD scale")
			# Use the same fixture definitions as the connected widget capture;
			# route and all controls remain the real composed implementation.
			editor.catalog = definitions.duplicate(true); editor.request_ticket = 0
			editor.choose_definition("Bridge")
			for frame in 3: editor._process(0); await process_frame
			if not await capture("hud_bridge_%d_%d" % [resolution.x,roundi(factor*100)]): quit(1); return
			var bounds := Rect2(Vector2.ZERO,hud.logical_view_size())
			assert(bounds.encloses(editor.orientation_panel.get_rect()),"orientation stays within the logical viewport")
			assert(not editor.orientation_panel.get_rect().intersects(editor.footer.get_rect()),"placement panels do not overlap")
			assert(not editor.footer.get_rect().intersects(hud.status_panel.get_rect()),"placement clears fortress header")
			if hud.minimap.visible:
				assert(not editor.orientation_panel.get_rect().intersects(hud.minimap_panel.get_rect()),"orientation preserves minimap")
			editor.handle_back(); editor.menu.open(); editor.mode = "menu"
	scene.queue_free(); await process_frame
	print("BUILD_MENU_CAPTURE_PASS connected controls and fixture HUD at two sizes/scales; protected live acceptance remains separate")
	quit(0)
