extends SceneTree
# Incremental 04-U visual evidence; captures implemented surfaces only.
const Test = preload("res://tests/areas_test.gd")
class CaptureWorld extends Test.FakeWorld:
	var assets
	func ui_texture(token: String, index := -1): return assets.ui_texture(token,index)
	func ui_font_path(): return assets.ui_font_path()

func settings_reply(controller, world, service, rows: Array) -> void:
	service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,
		"action":9,"status":2,"area":{"list_key":controller.settings_state.pending.list_key,
		"settings":rows,"list_revision":9007199254740993,"build_phase":3,"build_done":100,"build_total":100,"next_cursor":0}}
	service.poll()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(77); return
	var directory := ProjectSettings.globalize_path("res://../../../build/qa/04-U")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: quit(1); return
	root.size = Vector2i(1200,800)
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	var art = preload("res://scripts/original_ui.gd").new(); art.configure(assets)
	var panel := PanelContainer.new(); panel.theme = art.theme
	panel.position = Vector2(34,54); root.add_child(panel)
	var view := preload("res://scripts/area_stockpile_view.gd").new()
	panel.add_child(view); view.configure(assets)
	panel.add_theme_stylebox_override("panel",view.panel_style())
	for row in [{"file":"stockpile_none","name":"Stockpile #39","categories":0},
		{"file":"stockpile_wood","name":"Wood Stockpile #39","categories":8192,"links_only":true}]:
		view.display(row, true)
		await process_frame; await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join(str(row.file) + ".png")) != OK: quit(1); return
	panel.free()
	var world := CaptureWorld.new(); world.assets = assets
	var interaction := Test.FakeInteraction.new(); root.add_child(interaction)
	var service = preload("res://scripts/semantic_action_service.gd").new()
	service.configure(world); root.add_child(service); service.set_process(false)
	var host = preload("res://scripts/ui_host.gd").new()
	host.interaction = interaction; root.add_child(host)
	var controller = preload("res://scripts/areas.gd").new()
	controller.world = world; controller.interaction = interaction
	controller.action_service = service; controller.ui_host = host
	root.add_child(controller); host.register(controller); controller.set_process(false)
	# This is a layout capture, not viewport input acceptance. Desktop mouse
	# events must not invoke map picking on this camera-free fixture.
	controller.set_process_unhandled_input(false)
	host.activate(controller); controller.panel.show(); controller.available = true
	controller.use_area({"id":39,"revision":123,"kind":0,"name":"Wood Stockpile #39",
		"origin":Vector3i(3,4,2),"width":2,"height":2,"extents":PackedByteArray([1,1,1,1]),
		"tile_count":4,"categories":8192,"barrels":0,"bins":0,"wheelbarrows":0,"links_only":false,
		"active":true,"owner_id":-1,"owner_name":"","owner_allowed":false,"gives":[],"takes":[]})
	controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if controller.stockpile_view.get_global_rect().size.y < 432 or controller.panel.size.y < 452:
		push_error("Connected stockpile panel collapsed or clipped its preset grid")
		quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_stockpile.png")) != OK: quit(1); return
	controller.stockpile_control("containers"); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.storage_view.visible or controller.storage_view.position.x < controller.panel.get_global_rect().end.x:
		push_error("Storage popup overlaps or replaces stockpile panel"); quit(1); return
	if controller.storage_view.size != Vector2(324,176):
		push_error("Storage popup retained an oversized generic frame"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_storage.png")) != OK: quit(1); return
	controller.storage_view.controls.barrels[0].pressed.emit()
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_storage_entry.png")) != OK: quit(1); return
	controller.handle_back(); controller.handle_back()
	controller.stockpile_control("repaint"); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if controller.panel.size != Vector2(324,68):
		push_error("Repaint prompt retained generic frame dimensions"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_repaint.png")) != OK: quit(1); return
	controller.paint_pointer(Vector3i(5,4,2),true); controller.paint_pointer(Vector3i(5,4,2),false)
	controller.paint_pointer(Vector3i(5,4,2),true); controller.paint_pointer(Vector3i(5,4,2),false)
	controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_repaint_ready.png")) != OK: quit(1); return
	controller.handle_back()
	var retained_area: Dictionary = controller.selected.duplicate(true)
	controller.new_area(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.paint_view.visible or not controller.paint_view.buttons.remove.disabled:
		push_error("New stockpile did not open native painter"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_stockpile_new.png")) != OK: quit(1); return
	controller.paint_pointer(Vector3i(5,4,2),true); controller.paint_pointer(Vector3i(8,7,2),false); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if controller.paint_view.accept_button.disabled:
		push_error("New painted stockpile cannot be accepted"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_stockpile_new_ready.png")) != OK: quit(1); return
	controller.kind_picker.select(1)
	controller.zone_types = []
	for definition in controller.menu_data.zones:
		var row: Dictionary = definition.duplicate(true)
		row.id = controller.zone_types.size()
		controller.zone_types.append(row)
	controller.new_area(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_menu.png")) != OK: quit(1); return
	var bedroom: Dictionary = retained_area.duplicate(true)
	bedroom.kind = 1; bedroom.zone_type = 1; bedroom.zone_label = "Bedroom"
	bedroom.name = "Unnamed bedroom"; bedroom.owner_allowed = true
	controller.use_area(bedroom); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_bedroom.png")) != OK: quit(1); return
	controller.begin_paint(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_repaint.png")) != OK: quit(1); return
	controller.handle_back()
	# Native repaint Escape closes the zone UI. Reopen this layout fixture
	# explicitly before preparing the next independent capture.
	host.activate(controller); controller.panel.show(); controller.available = true
	controller.new_area()
	controller.zone_menu.buttons.Bedroom.pressed.emit(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_new.png")) != OK: quit(1); return
	controller.use_area(bedroom); controller._process(0)
	controller.zone_menu.controls.owner.pressed.emit(); service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
		"area":{"list_revision":95,"build_phase":3,"candidates":[
			{"id":21,"name":"Urist","profession":"Miner","sex":1,"mood":3},
			{"id":22,"name":"Domas","profession":"Carpenter","sex":0,"mood":7},
			{"id":23,"name":"Atir","profession":"Manager","sex":-1,"mood":0}]}}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_owner.png")) != OK: quit(1); return
	controller.handle_back()
	# Capture each observed zone type, including panels with no extra controls.
	for definition in controller.zone_types:
		var type_name: String = definition.name
		var typed: Dictionary = bedroom.duplicate(true)
		typed.zone_type = definition.id; typed.zone_label = definition.label
		typed.name = "Unnamed " + str(typed.zone_label).to_lower()
		typed.owner_allowed = type_name in ["Bedroom","DiningHall","Office","Tomb"]
		typed.zone_settings = {"pond_mode":1,"facing":2,"tomb_citizens":1,"tomb_pets":0,"gather_trees":1,"gather_shrubs":1}
		controller.use_area(typed); controller._process(0)
		await process_frame; await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join("controller_zone_"+type_name.to_lower()+".png")) != OK: quit(1); return
	var pen: Dictionary = bedroom.duplicate(true); pen.zone_type = 3; pen.zone_label = "Pen/Pasture"; pen.name = "Unnamed pen/pasture"; pen.owner_allowed = false
	controller.use_area(pen); controller.zone_menu.controls.animals.pressed.emit(); service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
		"area":{"list_revision":96,"candidates":[{"id":24,"name":"Stray Goat","profession":"Goat","sex":0,"grazer":true,"assigned":false},
			{"id":25,"name":"Dog","profession":"Dog","sex":1,"grazer":false,"assigned":true}]}}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_animals.png")) != OK: quit(1); return
	controller.handle_back()
	for type_name in ["Barracks","ArcheryRange"]:
		var squad_zone: Dictionary = bedroom.duplicate(true); squad_zone.owner_allowed = false
		for definition in controller.zone_types:
			if definition.name == type_name:
				squad_zone.zone_type = definition.id; squad_zone.zone_label = definition.label
		squad_zone.name = "Unnamed " + str(squad_zone.zone_label).to_lower()
		controller.use_area(squad_zone); controller.zone_menu.controls.squads.pressed.emit(); service.poll()
		world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
			"area":{"list_revision":97,"candidates":[{"id":8,"name":"The Golden Beaks","squad_use":2},
				{"id":9,"name":"The Blockaded Lovers","squad_use":0}]}}
		service.poll(); controller._process(0)
		await process_frame; await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join("controller_squads_"+type_name.to_lower()+".png")) != OK: quit(1); return
		controller.handle_back()
	controller.use_area(bedroom); controller.zone_menu.controls.location.pressed.emit(); service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":9,"status":2,
		"area":{"list_revision":98,"locations":[{"id":0,"name":"The Golden Shrine","location_kind":2,"religion":"The Bejeweled Creed"},
			{"id":1,"name":"The Oily Meal","location_kind":1,"religion":""},{"id":2,"name":"The Blockaded Sanctuary","location_kind":5,"religion":""},
			{"id":3,"name":"The White Temple","location_kind":2,"religion":"The Scintillating Bejeweled Faith"},
			{"id":4,"name":"The Constructive Bastion","location_kind":3,"religion":""},
			{"id":5,"name":"The Pears of Hide","location_kind":4,"religion":"","guild_profession":41,"location_tier":0}]}}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_locations.png")) != OK: quit(1); return
	for choice in controller.locations_view.choices:
		if choice.get_node("Details").position.x != choice.size.x-40:
			push_error("Location details must follow native row right inset"); quit(1); return
		for key in ["Name","Subtitle"]:
			var label: Label = choice.get_node(key)
			if label.position.x+label.size.x > choice.get_node("Details").position.x:
				push_error("Location text overlaps details control: "+str(label.size)); quit(1); return
	if controller.locations_view.remove.visible or controller.locations_view.scroll.size.y != 216:
		push_error("Unassigned location selector must expose six native rows"); quit(1); return
	controller.locations_state.area.location_id = 0
	controller.locations_view.refresh()
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.locations_view.remove.visible or controller.locations_view.scroll.size.y != 180:
		push_error("Assigned location selector must reserve the removal row"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_locations_assigned.png")) != OK: quit(1); return
	controller.handle_back()
	for type_name in ["MeetingHall","Office"]:
		var typed: Dictionary = bedroom.duplicate(true)
		for definition in controller.zone_types:
			if definition.name == type_name:
				typed.zone_type = definition.id; typed.zone_label = definition.label
		typed.name = "Unnamed memorial hall" if type_name == "MeetingHall" else "Unnamed office"
		typed.owner_allowed = type_name == "Office"
		if type_name == "MeetingHall":
			typed.location_id = 0; typed.location_name = "The Golden Shrine"; typed.religion = "The Bejeweled Creed"
			typed.location_kind = 2
		else:
			typed.owner_id = 21; typed.owner_name = "Ihhi Kadpar"; typed.owner_profession = "Manager"; typed.owner_sex = 1
		controller.use_area(typed); controller._process(0)
		await process_frame; await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join("controller_zone_"+type_name.to_lower()+".png")) != OK: quit(1); return
	controller.choose_zone_type(1); controller._process(0)
	# Native overlapping-zone name row: arrows flank the shifted name/rename.
	controller.zone_overlaps = [bedroom.duplicate(true),bedroom.duplicate(true)]
	controller.zone_overlaps[1].id = int(bedroom.id)+1
	controller.use_area(bedroom,false); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.zone_menu.controls.previous.visible or controller.zone_menu.controls.rename.position.x != 254:
		push_error("Native overlap header navigation missing"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_overlap.png")) != OK: quit(1); return
	controller.choose_zone_type(1); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if controller.panel.size != Vector2(324,188):
		push_error("Zone paint prompt has wrong dimensions: "+str(controller.panel.size)); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_paint.png")) != OK: quit(1); return
	controller.use_area(retained_area)
	controller.stockpile_control("links"); service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,
		"action":9,"status":2,"area":{"list_revision":92,"build_phase":3,"build_done":4,"build_total":4,
		"next_cursor":0,"links":[{"id":40,"kind":0,"direction":1,"name":"Wood Stockpile #40"},
		{"id":41,"kind":0,"direction":2,"name":"All Stockpile #41"},
		{"id":50,"kind":2,"direction":1,"name":"Carpenter's Workshop"},
		{"id":51,"kind":2,"direction":2,"name":"Craftsdwarf's Workshop"}]}}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.links_view.visible or controller.links_view.size != Vector2(324,416):
		push_error("Links panel is missing or retained generic dimensions"); quit(1); return
	for line in controller.links_view.rows_box.get_children():
		if not line.get_global_rect().encloses(line.get_child(2).get_global_rect()):
			push_error("Links remove control is outside its row"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_links.png")) != OK: quit(1); return
	for give in [true,false]:
		controller.begin_link_pick(give); controller._process(0)
		await process_frame; await RenderingServer.frame_post_draw
		if controller.links_view.size != Vector2(324,116):
			push_error("Links pick prompt did not shrink to native height"); quit(1); return
		if root.get_texture().get_image().save_png(directory.path_join("controller_links_give.png" if give else "controller_links_take.png")) != OK: quit(1); return
		controller.handle_back()
	controller.handle_back()
	# Synthetic observed states exercise the native hierarchy and three colors;
	# these screenshots are presentation evidence, not native effect evidence.
	# Start with Ammo and Food enabled so opening Custom reads immediately.
	# Category activation effects are covered by the connected/live suites.
	var settings_area: Dictionary = retained_area.duplicate(true)
	settings_area.categories = int(settings_area.categories) | 64 | 2
	controller.use_area(settings_area,false)
	controller.choose_preset(0)
	controller.settings_state.category = "food"
	var categories: Array = []
	for row in controller.menu_data.categories:
		categories.append({"key":row.key,"label":row.label,"kind":1,"state":3 if row.key == "food" else 1})
	categories.append({"key":"organic","label":"Organic","kind":3,"state":2})
	categories.append({"key":"inorganic","label":"Inorganic","kind":3,"state":1})
	settings_reply(controller,world,service,categories)
	settings_reply(controller,world,service,[{"key":"food/prepared_meals","label":"Prepared meals","kind":3,"state":1},
		{"key":"food/meat","label":"Meat","kind":2,"state":3},{"key":"food/fish","label":"Fish","kind":2,"state":2}])
	settings_reply(controller,world,service,[{"key":"food/meat/0","label":"Fixture meat A","kind":4,"state":1},
		{"key":"food/meat/1","label":"Fixture meat B","kind":4,"state":2}])
	controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.settings_view.visible or controller.settings_view.rendered_rows[2].size() != 2:
		push_error("Connected settings replies did not populate the native columns"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_settings_food.png")) != OK: quit(1); return
	controller.settings_view.rendered_rows[2][0].pressed.emit(); service.poll()
	if world.calls[-1].operation != 2 or world.calls[-1].row_key != "food/meat/0":
		push_error("Connected leaf button did not issue a semantic settings edit"); quit(1); return
	var changed_area: Dictionary = controller.selected.duplicate(true); changed_area.revision = 124
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,
		"action":11,"status":2,"areas":[changed_area]}
	service.poll()
	if controller.stockpile_page != "settings" or controller.settings_state.pending.expected_revision != 124 or controller.settings_state.category != "food":
		push_error("Settings mutation did not refresh against new area revision while preserving navigation"); quit(1); return
	controller.close_panel(); controller.free(); host.free(); service.free(); interaction.free()
	assets.free(); await process_frame
	print("AREA_MENUS_CAPTURE_PASS")
	quit()
