extends SceneTree
# Incremental 04-U visual evidence; captures implemented surfaces only.
const Test = preload("res://tests/areas_test.gd")
class CaptureWorld extends Test.FakeWorld:
	var assets
	var portrait_requests: Array = []
	func creature_portrait(id: int):
		portrait_requests.append(id); return null
	func ui_texture(token: String, index := -1): return assets.ui_texture(token,index)
	func ui_font_path(): return assets.ui_font_path()
	func assets_root(): return assets.assets_root()
	func candidate_icon(recipe): return assets.candidate_icon(recipe)
	func animal_container_icon(facts): return assets.animal_container_icon(facts)
	func animal_restraint_icon(facts): return assets.animal_restraint_icon(facts)

func settings_reply(controller, world, service, rows: Array) -> void:
	service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,
		"action":9,"status":2,"area":{"list_key":controller.settings_state.pending.list_key,
		"settings":rows,"list_revision":9007199254740993,"build_phase":3,"build_done":100,"build_total":100,"next_cursor":0}}
	service.poll()

func owner_header_pixels(reference: Dictionary, state_name: String) -> bool:
	var image := root.get_texture().get_image(); image.convert(Image.FORMAT_RGB8)
	var evidence: Dictionary = reference.owner_header_order.header_pixels
	for index in evidence.boxes.size():
		var b: Array = evidence.boxes[index]
		var region := image.get_region(Rect2i(int(b[0]),int(b[1]),int(b[2])-int(b[0]),int(b[3])-int(b[1])))
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(region.get_data())
		if digest.finish().hex_encode() != str(evidence.reference_hashes[state_name][index]):
			push_error("Native owner header pixels differ: "+state_name+" "+str(index)); return false
	return true

func owner_frame_pixels(view, reference: Dictionary, selected: bool) -> bool:
	var image := root.get_texture().get_image(); image.convert(Image.FORMAT_RGB8)
	var frame: Panel = view.owner_frames[0]
	if frame.size != Vector2(40,36): push_error("Owner picture frame dimensions differ"); return false
	var slot: Dictionary = view.portrait_slots[0]
	if not slot.snapshot or slot.view.position != Vector2(2,2) or slot.view.size != Vector2(32,32):
		push_error("Owner full-body anchor differs"); return false
	var bytes := PackedByteArray()
	for y in 36:
		for x in 40:
			if x not in [0,1,38,39] and y not in [0,1,34,35]: continue
			var color := image.get_pixel(int(frame.global_position.x)+x,int(frame.global_position.y)+y)
			bytes.append(color.r8); bytes.append(color.g8); bytes.append(color.b8)
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(bytes)
	var sample: Dictionary = reference.owner_picture_frame.samples[0 if selected else 1]
	if digest.finish().hex_encode() != str(sample.rgb_sha256):
		push_error("Native owner picture frame differs: "+str(sample.state)); return false
	return true

func owner_filter_pixels(view, reference: Dictionary, sample_index: int) -> bool:
	var sample: Dictionary = reference.owner_textbox_input.rendered_editor.samples[sample_index]
	var image := root.get_texture().get_image(); image.convert(Image.FORMAT_RGB8)
	var crop := image.get_region(Rect2i(Vector2i(view.owner_search.global_position)+Vector2i(16,12),Vector2i(int(sample.width),12)))
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(crop.get_data())
	if digest.finish().hex_encode() != str(sample.sha256):
		push_error("Native owner filter byte glyphs differ"); return false
	return true

func _initialize() -> void:
	call_deferred("run")

func paint_reply(world, service, observed: Dictionary) -> void:
	service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,
		"action":world.calls[-1].action,"status":2,"areas":[observed]}
	service.poll()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(77); return
	var directory := ProjectSettings.globalize_path("res://../../../build/qa/04-U")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: quit(1); return
	root.size = Vector2i(1200,800)
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	var native_images: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_assignment.json")).owner_candidate_imagery
	for sample in native_images.samples:
		var recipe: Dictionary = sample.recipe.duplicate(true)
		for layer in recipe.layers:
			for index in layer.size(): layer[index] = int(layer[index])
		var icon: Texture2D = assets.candidate_icon(recipe)
		if icon == null: push_error("Owner candidate image unavailable: "+str(sample.unit.id)); quit(1); return
		var image := icon.get_image(); image.convert(Image.FORMAT_RGBA8); image.clear_mipmaps()
		image.save_png(directory.path_join("owner_body_%d.png" % int(sample.unit.id)))
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(image.get_data())
		if image.get_size() != Vector2i(32,32) or digest.finish().hex_encode() != str(sample.rgba_sha256):
			push_error("Native owner candidate image pixels differ: "+str(sample.unit.id)); quit(1); return
	for invalid in [{},{"tile_pages":[],"palettes":[],"layers":[[0,0,0,1,1,65535,-1,-1,0,0]]}]:
		if assets.candidate_icon(invalid) != null: push_error("Unknown owner image was fabricated"); quit(1); return
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
		"tile_count":4,"storage_limit":4,"categories":8192,"barrels":0,"bins":0,"wheelbarrows":0,"links_only":false,
		"active":true,"owner_id":-1,"owner_name":"","owner_allowed":false,"gives":[],"takes":[]})
	controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if controller.stockpile_view.get_global_rect().size.y < 432 or controller.panel.size.y < 452:
		push_error("Connected stockpile panel collapsed or clipped its preset grid")
		quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_stockpile.png")) != OK: quit(1); return
	controller.stockpile_control("containers"); service.poll()
	world.state = {"world_epoch":42,"revision":2,"request_seq":world.seq,"action":9,"status":2,"areas":[controller.selected.duplicate(true)]}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.storage_view.visible or controller.storage_view.position.x < controller.panel.get_global_rect().end.x:
		push_error("Storage popup overlaps or replaces stockpile panel"); quit(1); return
	if controller.storage_view.size != Vector2(324,176):
		push_error("Storage popup retained an oversized generic frame"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_storage.png")) != OK: quit(1); return
	controller.storage_view.controls.barrels[0].pressed.emit()
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_storage_entry.png")) != OK: quit(1); return
	controller.handle_back()
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
	var repainted: Dictionary = controller.selected.duplicate(true)
	repainted.width = 3; repainted.extents = PackedByteArray([1,1,1,1,1,0]); repainted.tile_count = 5; repainted.revision += 1
	paint_reply(world,service,repainted)
	controller.handle_back()
	var retained_area: Dictionary = controller.selected.duplicate(true)
	host.activate(controller); controller.panel.show()
	controller.new_area(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.paint_view.visible or not controller.paint_view.buttons.remove.disabled:
		push_error("New stockpile did not open native painter"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_stockpile_new.png")) != OK: quit(1); return
	controller.paint_pointer(Vector3i(5,4,2),true); controller.paint_pointer(Vector3i(8,7,2),false)
	controller.paint_pointer(Vector3i(8,7,2),true); controller.paint_pointer(Vector3i(8,7,2),false); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if controller.paint_view.accept_button.disabled:
		push_error("New painted stockpile cannot be accepted"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_stockpile_new_ready.png")) != OK: quit(1); return
	var created: Dictionary = repainted.duplicate(true)
	created.id = 40; created.origin = Vector3i(5,4,2); created.width = 4; created.height = 4
	created.extents = PackedByteArray(); created.extents.resize(16); created.extents.fill(1); created.tile_count = 16
	paint_reply(world,service,created)
	controller.kind_picker.select(1)
	controller.zone_types = []
	for definition in controller.menu_data.zones:
		var row: Dictionary = definition.duplicate(true)
		row.id = {"MeetingHall":87,"Bedroom":92,"DiningHall":80,"Pen":88,"Pond":86,"WaterSource":82,"Dungeon":96,"FishingArea":85,"SandCollection":84,"Office":93,"Dormitory":81,"Barracks":95,"ArcheryRange":94,"Dump":83,"AnimalTraining":90,"PlantGathering":91,"Tomb":97,"ClayCollection":89}[str(row.name)]
		controller.zone_types.append(row)
	controller.new_area(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_menu.png")) != OK: quit(1); return
	var bedroom: Dictionary = retained_area.duplicate(true)
	bedroom.kind = 1; bedroom.zone_type = 92; bedroom.zone_label = "Bedroom"
	bedroom.name = "Unnamed bedroom"; bedroom.owner_allowed = true
	controller.use_area(bedroom); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_bedroom.png")) != OK: quit(1); return
	for viewport_size in [Vector2i(960,600),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=viewport_size
		for frame in 4:controller._process(0);await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join("controller_zone_palette_%d.png"%viewport_size.y))!=OK:quit(1);return
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
	var name_pixels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_assignment.json")).owner_name_color.pixels
	# JSON numbers are floats; the real extension emits integer palette components.
	for key in ["color","alternate"]:
		for index in 3: name_pixels.color[key][index] = int(name_pixels.color[key][index])
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
		"area":{"list_revision":95,"build_phase":3,"candidates":[
			{"id":21,"name":"Legacy name must not render","profession":"Legacy profession","sex":1,"mood":3,
				"owner_display":{"columns":45,"first_line":str(name_pixels.first_line),"second_line":"","status":"Has Quarters","room_value":343,"name_color":name_pixels.color}},
			{"id":22,"name":"Legacy name","profession":"Legacy profession","sex":0,"mood":7,
				"owner_display":{"columns":45,"first_line":"Domas","second_line":"Carpenter, ♀","status":"","room_value":0,"name_color":{"color":[3,3,1],"alternate":[0,3,0],"effect":1}}},
			{"id":23,"name":"Atir","profession":"Manager","sex":-1,"mood":0}]}}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_owner.png")) != OK: quit(1); return
	for index in 2:
		var button: Button = controller.candidates_view.choices[index]
		var display: Dictionary = controller.candidates_state.rows[index].owner_display
		if not button.text.is_empty(): push_error("Owner row assembled legacy text"); quit(1); return
		for line_index in 3:
			var line: Label = button.get_node(["OwnerStatus","OwnerFirst","OwnerSecond"][line_index])
			if line.text != display[["status","first_line","second_line"][line_index]] or line.position != Vector2(40,line_index*12) or line.size != Vector2(360,12):
				push_error("Owner native line text or geometry differs: %s %s %s" % [line.name,line.position,line.size]); quit(1); return
	var native_name: Label = controller.candidates_view.choices[0].get_node("OwnerFirst")
	var name_image := root.get_texture().get_image(); name_image.convert(Image.FORMAT_RGB8)
	var name_crop := name_image.get_region(Rect2i(Vector2i(native_name.global_position),Vector2i(native_name.text.length()*8,12)))
	var name_digest := HashingContext.new(); name_digest.start(HashingContext.HASH_SHA256); name_digest.update(name_crop.get_data())
	if name_digest.finish().hex_encode() != str(name_pixels.rgb_sha256):
		push_error("Native owner name foreground/background pixels differ"); quit(1); return
	for time in [0,332,333,999,1000]:
		controller.candidates_view.apply_owner_colors(time,0)
		for line_name in ["OwnerFirst","OwnerSecond"]:
			var flashing: Label = controller.candidates_view.choices[1].get_node(line_name)
			var expected_color: Color = controller.candidates_view.native_colors[0 if time%1000 < 333 else 11]
			if flashing.get_theme_color("font_color") != expected_color or flashing.get_node("GlyphBackground").color != controller.candidates_view.native_colors[3]:
				push_error("Owner row flash phase or background differs"); quit(1); return
	if controller.candidates_view.choices[2].has_node("OwnerFirst") or not controller.candidates_view.choices[2].text.is_empty():
		push_error("Absent owner display was invented"); quit(1); return
	var header_reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_assignment.json"))
	# Bedroom starts on Remove assignment; owner rows use the unselected artwork.
	for sample in header_reference.owner_row_background.samples:
		var target: Button = controller.candidates_view.remove if sample.state == "selected" else controller.candidates_view.choices[0]
		var box: Array = sample.relative_box
		var image := root.get_texture().get_image(); image.convert(Image.FORMAT_RGB8)
		var crop := image.get_region(Rect2i(Vector2i(target.global_position)+Vector2i(int(box[0]),int(box[1])),Vector2i(int(box[2]),int(box[3]))))
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(crop.get_data())
		if digest.finish().hex_encode() != str(sample.rgb_sha256):
			push_error("Native owner row background differs: "+str(sample.state)); quit(1); return
	if not owner_frame_pixels(controller.candidates_view,header_reference,false): quit(1); return
	var status_reference: Dictionary = header_reference.owner_colors.status_pixels
	var status_box: Array = status_reference.box
	var status_rgb: Array = status_reference.foreground_rgb
	var status_image := root.get_texture().get_image(); status_image.convert(Image.FORMAT_RGB8)
	var status_region := status_image.get_region(Rect2i(int(status_box[0]),int(status_box[1]),int(status_box[2])-int(status_box[0]),int(status_box[3])-int(status_box[1])))
	var status_bytes := status_region.get_data(); var glyph_mask := PackedByteArray()
	for pixel in int(status_bytes.size()/3):
		glyph_mask.append(1 if status_bytes[pixel*3] == int(status_rgb[0]) and status_bytes[pixel*3+1] == int(status_rgb[1]) and status_bytes[pixel*3+2] == int(status_rgb[2]) else 0)
	var status_digest := HashingContext.new(); status_digest.start(HashingContext.HASH_SHA256); status_digest.update(glyph_mask)
	if status_digest.finish().hex_encode() != str(status_reference.glyph_mask_sha256):
		push_error("Native owner status glyph positions or colors differ"); quit(1); return
	if not owner_header_pixels(header_reference,"default"): quit(1); return
	var header_rows: Array = controller.candidates_state.rows.duplicate(true)
	# Exercise actual main-controller key routing and native selected artwork.
	var navigation_rows: Array = header_rows.duplicate(true)
	while navigation_rows.size() < 24:
		var row: Dictionary = header_rows[0].duplicate(true); row.id = 10000+navigation_rows.size()
		navigation_rows.append(row)
	controller.candidates_state.rows = navigation_rows
	controller.candidates_state.receipt = 101; controller.candidates_state.changed.emit()
	await process_frame; await RenderingServer.frame_post_draw
	for probe in [[KEY_DOWN,1],[KEY_UP,0],[KEY_PAGEDOWN,16],[KEY_PAGEUP,0],[KEY_UP,0]]:
		var key := InputEventKey.new(); key.keycode = probe[0]; key.pressed = true
		root.push_input(key,true)
		await process_frame; await RenderingServer.frame_post_draw
		if controller.candidates_view.owner_selected != probe[1]:
			push_error("Owner keyboard selection differs from native"); quit(1); return
		if probe[1] == 1 and not owner_frame_pixels(controller.candidates_view,header_reference,true): quit(1); return
		if probe[1] == 16:
			if controller.candidates_view.scroll.scroll_vertical != 36:
				push_error("Owner page navigation did not advance one whole row"); quit(1); return
			var selected_button: Button = controller.candidates_view.choices[15]
			if not controller.candidates_view.scroll.get_global_rect().encloses(selected_button.get_global_rect()):
				push_error("Owner keyboard selection is outside viewport"); quit(1); return
	# Native resize references retain independent frame and list minimum widths.
	for sample in header_reference.picker_resize_reference.observations:
		root.size=Vector2i(int(sample.pixel_width),int(sample.pixel_height))
		controller.candidates_view.layout(Vector2(root.size))
		await process_frame;await RenderingServer.frame_post_draw
		controller.candidates_view.layout(Vector2(root.size))
		await process_frame;await RenderingServer.frame_post_draw
		var resized_view=controller.candidates_view
		var expected_y:float=int(sample.filter_rect[1])*12+fposmod(float(sample.pixel_height),12)*0.5
		var expected_scroll_width:float=(int(sample.scroll_rect[2])-int(sample.scroll_rect[0])+1)*8
		var expected_panel_width:float=(int(sample.widgets[0].x2)-int(sample.widgets[0].x)+1)*8+12
		if not is_equal_approx(resized_view.size.x,expected_panel_width) or not is_equal_approx(resized_view.scroll.size.x,expected_scroll_width) or not is_equal_approx(resized_view.owner_scrollbar.position.x,expected_scroll_width):
			push_error("Resized owner widths differ from native: "+str(sample.size)+" panel="+str(resized_view.size.x)+" scroll="+str(resized_view.scroll.size.x)+" bar="+str(resized_view.owner_scrollbar.position.x));quit(1);return
		for button in resized_view.choices:
			if not is_equal_approx(button.size.x,maxf(456,expected_scroll_width-8)):
				push_error("Resized owner row background width differs");quit(1);return
		root.get_texture().get_image().save_png(directory.path_join("owner_resize_"+str(sample.size)+".png"))
		if resized_view.owner_scrollbar.page!=int(sample.num_visible) or not is_equal_approx(resized_view.owner_search.global_position.y,expected_y):
			push_error("Resized owner geometry differs from native: "+str(sample.size)+" filter="+str(resized_view.owner_search.global_position)+" expected_y="+str(expected_y));quit(1);return
		resized_view.owner_selected=0;resized_view.owner_scrollbar.move_to(0)
		var down:=InputEventKey.new();down.pressed=true;down.keycode=KEY_PAGEDOWN
		resized_view.feed_owner_key(down)
		if resized_view.owner_selected!=int(sample.num_visible):push_error("Resized owner Page Down differs");quit(1);return
		var up:=InputEventKey.new();up.pressed=true;up.keycode=KEY_PAGEUP
		resized_view.feed_owner_key(up)
		if resized_view.owner_selected!=0:push_error("Resized owner Page Up differs");quit(1);return
	root.size=Vector2i(1200,800);controller.candidates_view.layout(Vector2(root.size))
	await process_frame;await RenderingServer.frame_post_draw
	# Compare the full owner scrollbar against native top/tail captures, including
	# its installed artwork, thumb proportions and the 24px blank below the rows.
	var saved_owner_area: Dictionary = controller.candidates_state.area
	controller.candidates_state.area = saved_owner_area.duplicate(true)
	controller.candidates_state.area.zone_type = 97
	var full_owner_rows: Array = navigation_rows.duplicate(true)
	while full_owner_rows.size() < 172:
		var row: Dictionary = header_rows[0].duplicate(true); row.id = 20000+full_owner_rows.size()
		full_owner_rows.append(row)
	controller.candidates_state.rows = full_owner_rows
	controller.candidates_state.receipt = 102; controller.candidates_state.changed.emit()
	await process_frame; await RenderingServer.frame_post_draw
	var owner_bar = controller.candidates_view.owner_scrollbar
	for sample in header_reference.owner_scroll.rendered_bar.samples:
		owner_bar.move_to(int(sample.first))
		await process_frame; await RenderingServer.frame_post_draw
		var clip: Rect2 = controller.candidates_view.scroll.get_global_rect()
		var full := 0
		for button in controller.candidates_view.choices:
			if clip.encloses(button.get_global_rect()): full += 1
			elif clip.intersects(button.get_global_rect()):
				push_error("Owner viewport exposes a partial row"); quit(1); return
		if full != 16 or controller.candidates_view.scroll.scroll_vertical != int(sample.first)*36:
			push_error("Owner complete-row viewport differs from native"); quit(1); return
		var bar_image := root.get_texture().get_image(); bar_image.convert(Image.FORMAT_RGB8)
		var bar_crop := bar_image.get_region(Rect2i(Vector2i(owner_bar.global_position),Vector2i(16,600)))
		bar_crop.save_png(directory.path_join("owner_bar_%d.png" % int(sample.first)))
		var bar_hash := HashingContext.new(); bar_hash.start(HashingContext.HASH_SHA256); bar_hash.update(bar_crop.get_data())
		if bar_hash.finish().hex_encode() != str(sample.rgb_sha256):
			push_error("Native owner scrollbar pixels differ at "+str(sample.first)); quit(1); return
	for sample in header_reference.picker_resize_scroll_reference.observations:
		var resized=controller.candidates_view
		var label:String=str(sample.label)
		if label=="tail-default" and resized.owner_selected!=171:
			resized.owner_selected=171;owner_bar.move_to(156)
		elif label=="selection-default" and resized.owner_selected!=16:
			resized.owner_selected=16;owner_bar.move_to(1)
		var dimensions:=Vector2i(960,600) if label.ends_with("small") else Vector2i(1600,900) if label.ends_with("wide") else Vector2i(1200,800)
		root.size=dimensions;resized.layout(Vector2(dimensions))
		await process_frame;await RenderingServer.frame_post_draw
		resized.layout(Vector2(dimensions))
		await process_frame;await RenderingServer.frame_post_draw
		if owner_bar.first!=int(sample.scroll) or owner_bar.page!=int(sample.num_visible) or resized.owner_selected!=int(sample.cursor) or resized.scroll.scroll_vertical!=int(sample.scroll)*36:
			push_error("Owner resize retained scroll differs: "+label+" first="+str(owner_bar.first)+" page="+str(owner_bar.page)+" cursor="+str(resized.owner_selected)+" pixels="+str(resized.scroll.scroll_vertical));quit(1);return
	controller.candidates_state.area = saved_owner_area; controller.candidates_state.rows = navigation_rows
	controller.candidates_state.receipt = 101; controller.candidates_state.changed.emit()
	await process_frame; await RenderingServer.frame_post_draw
	var filter_shortcut := InputEventKey.new(); filter_shortcut.keycode = KEY_F; filter_shortcut.ctrl_pressed = true; filter_shortcut.pressed = true
	root.push_input(filter_shortcut,true)
	if not controller.candidates_view.owner_search.has_focus(): push_error("Ctrl+F did not focus owner filter"); quit(1); return
	var preserved_button: Button = controller.candidates_view.choices[0]
	if not is_same(controller.candidates_view.cached_rows[0],controller.candidates_state.rows[0]):
		push_error("Owner view duplicated the immutable recipe snapshot"); quit(1); return
	for connection in preserved_button.get_signal_connection_list("pressed"):
		if connection.callable.get_bound_arguments() != [int(controller.candidates_state.rows[0].id)]:
			push_error("Owner assignment callback retains data beyond unit identity"); quit(1); return
	var preserved_scroll: int = controller.candidates_view.scroll.scroll_vertical
	var preserved_selection: int = controller.candidates_view.owner_selected
	var refreshed: Array = controller.candidates_state.rows.duplicate(true)
	refreshed[0].owner_display.first_line = "Updated name"
	refreshed[0].mood = 7
	controller.candidates_state.accept_owner_facts({"operation":14,"candidate_kind":1,"query":"","sort":2,"sort_descending":false,"list_revision":101,"candidates":refreshed},
		{"id":int(controller.candidates_state.area.id),"query":"","sort":2,"sort_descending":false,"candidate_kind":1,"expected_list_revision":101,"cursor":0})
	await process_frame; await RenderingServer.frame_post_draw
	if controller.candidates_view.choices[0] != preserved_button or preserved_button.get_node("OwnerFirst").text != "Updated name":
		push_error("Owner facts rebuilt controls or failed to update text"); quit(1); return
	if controller.candidates_view.scroll.scroll_vertical != preserved_scroll or controller.candidates_view.owner_selected != preserved_selection or not controller.candidates_view.owner_search.has_focus():
		push_error("Owner facts changed scroll, selection or filter focus"); quit(1); return
	var leave_filter := InputEventMouseButton.new(); leave_filter.button_index=MOUSE_BUTTON_RIGHT;leave_filter.pressed=true;leave_filter.position=Vector2(800,700)
	root.push_input(leave_filter,true);leave_filter.pressed=false;root.push_input(leave_filter,true)
	if controller.candidates_view.owner_search.has_focus() or controller.stockpile_page != "owner":
		push_error("First owner right-click must only leave textbox focus");quit(1);return
	root.push_input(filter_shortcut,true)
	var focused_recenter := InputEventKey.new();focused_recenter.pressed=true;focused_recenter.ctrl_pressed=true;focused_recenter.keycode=KEY_C
	var focused_recenter_calls: int=world.calls.size()
	root.push_input(focused_recenter,true)
	if not controller.panel.visible or controller.stockpile_page!="owner" or not controller.candidates_view.owner_search.has_focus() or world.calls.size()!=focused_recenter_calls:
		push_error("Focused Ctrl+C must remain in the owner filter");quit(1);return
	var before_focus_calls: int = world.calls.size()
	for code in [KEY_DOWN,KEY_ENTER]:
		var focused_key := InputEventKey.new(); focused_key.keycode = code; focused_key.pressed = true
		root.push_input(focused_key,true)
		await process_frame
	if controller.candidates_view.owner_search.has_focus() or controller.candidates_view.owner_selected != 0 or world.calls.size() != before_focus_calls:
		push_error("Owner textbox Enter assigned or retained focus"); quit(1); return
	controller.candidates_state.mutating = true
	var blocked := InputEventKey.new(); blocked.keycode = KEY_DOWN; blocked.pressed = true
	root.push_input(blocked,true)
	if controller.candidates_view.owner_selected != 0:
		push_error("Pending assignment moved keyboard selection"); quit(1); return
	controller.candidates_state.mutating = false
	controller.set_process(false)
	controller.candidates_view.owner_search.grab_focus()
	controller.candidates_view.owner_search.ticks_override = 750
	var owner_typed := InputEventKey.new(); owner_typed.pressed = true; owner_typed.unicode = 233
	root.push_input(owner_typed,true)
	if controller.candidates_state.query_bytes != PackedByteArray([195,169]):
		push_error("Owner editor converted native bytes to Unicode"); quit(1); return
	await process_frame; await RenderingServer.frame_post_draw
	if not owner_filter_pixels(controller.candidates_view,header_reference,0): quit(1); return
	var owner_filter_box: Rect2 = controller.candidates_view.owner_search.get_global_rect()
	if root.get_texture().get_image().get_region(Rect2i(owner_filter_box)).save_png(directory.path_join("owner_filter_nonascii.png")) != OK: quit(1); return
	var owner_erase := InputEventKey.new(); owner_erase.pressed = true; owner_erase.keycode = KEY_BACKSPACE
	root.push_input(owner_erase,true)
	if controller.candidates_state.query_bytes != PackedByteArray([195]):
		push_error("Owner Backspace removed a character instead of a byte"); quit(1); return
	await process_frame; await RenderingServer.frame_post_draw
	if not owner_filter_pixels(controller.candidates_view,header_reference,1): quit(1); return
	if root.get_texture().get_image().get_region(Rect2i(owner_filter_box)).save_png(directory.path_join("owner_filter_partial.png")) != OK: quit(1); return
	controller.candidates_state.queue_owner_search("x".repeat(32).to_utf8_buffer())
	root.push_input(owner_typed,true)
	if controller.candidates_state.query_bytes != "x".repeat(32).to_utf8_buffer()+PackedByteArray([195]):
		push_error("Owner limit did not truncate at byte33"); quit(1); return
	root.push_input(owner_typed,true)
	if controller.candidates_state.query_bytes.size() != 33: push_error("Owner filter exceeded33 bytes"); quit(1); return
	var owner_point: Vector2 = controller.candidates_view.headers[0].get_global_rect().get_center()
	var owner_click := InputEventMouseButton.new(); owner_click.position=owner_point; owner_click.global_position=owner_point; owner_click.button_index=MOUSE_BUTTON_LEFT; owner_click.pressed=true
	root.push_input(owner_click,true); owner_click.pressed=false; root.push_input(owner_click,true)
	if not controller.candidates_view.owner_search.has_focus(): push_error("Owner header lost textbox focus"); quit(1); return
	owner_point = controller.candidates_view.global_position+Vector2(400,636)
	owner_click.position=owner_point; owner_click.global_position=owner_point; owner_click.pressed=true; root.push_input(owner_click,true);owner_click.pressed=false;root.push_input(owner_click,true)
	if controller.candidates_view.owner_search.has_focus(): push_error("Owner blank owner_click retained focus"); quit(1); return
	controller.candidates_state.query_bytes = null; controller.candidates_state.query = ""
	controller.candidates_state.search_delay = -1; controller.candidates_state.pending = {}
	controller.candidates_state.sort = 2; controller.candidates_state.descending = false
	controller.candidates_state.sort_directions = [false,false,false,false,false]
	controller.set_process(true)
	controller.candidates_state.rows = header_rows; controller.candidates_state.receipt = 95
	controller.candidates_state.changed.emit()
	await process_frame; await RenderingServer.frame_post_draw
	for sample in header_reference.owner_header_order.sequences:
		var sort: int = {"Name":1,"Cat":2,"Prof":3,"Stress":4}[sample.header]
		var button: Button = controller.candidates_view.headers[sort-1]
		var point: Vector2 = button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; root.push_input(motion,true)
		var event := InputEventMouseButton.new(); event.position=point; event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; root.push_input(event,true)
		event.pressed=false; root.push_input(event,true)
		controller._process(0); service.poll()
		if int(world.calls[-1].get("sort",-1)) != sort or bool(world.calls[-1].get("sort_descending",false)) != bool(sample.descending):
			push_error("Native owner header sequence differs: "+str(sample.name)); quit(1); return
		world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
			"area":{"list_revision":95,"build_phase":3,"sort":sort,"sort_descending":bool(sample.descending),"candidates":header_rows}}
		service.poll(); controller._process(0)
		await process_frame; await RenderingServer.frame_post_draw
		if str(sample.header)=="Stress" and not bool(sample.descending):
			if not owner_header_pixels(header_reference,"stress"): quit(1); return
			if root.get_texture().get_image().save_png(directory.path_join("controller_zone_owner_stress.png")) != OK: quit(1); return
	controller.handle_back()
	# Native clear availability and receipt lifecycle through viewport clicks.
	for type_name in ["Bedroom","DiningHall","Office","Tomb"]:
		for owner in [-1,17]:
			var room: Dictionary = bedroom.duplicate(true)
			for definition in controller.zone_types:
				if definition.name == type_name:
					room.zone_type = definition.id; room.zone_label = definition.label
			room.owner_id = owner
			controller.use_area(room); controller._process(0)
			controller.zone_menu.controls.owner.pressed.emit(); service.poll()
			world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
				"area":{"list_revision":95,"build_phase":3,"candidates":header_rows}}
			service.poll(); controller._process(0)
			await process_frame; await RenderingServer.frame_post_draw
			var clear_expected: bool = type_name != "Tomb"
			if controller.candidates_view.remove.visible != clear_expected or (clear_expected and controller.candidates_view.remove.disabled):
				push_error("Native owner clear availability differs: "+type_name); quit(1); return
			if type_name == "Tomb" and owner == -1:
				if not owner_frame_pixels(controller.candidates_view,header_reference,true): quit(1); return
				if root.get_texture().get_image().save_png(directory.path_join("controller_zone_tomb_owner.png")) != OK: quit(1); return
			var button: Button = controller.candidates_view.remove if clear_expected else controller.candidates_view.choices[0]
			var point: Vector2 = button.get_global_rect().get_center()
			var before: int = world.calls.size()
			for repeat_click in 2:
				if owner == -1:
					var activation := InputEventKey.new(); activation.keycode = KEY_ENTER; activation.pressed = true
					root.push_input(activation,true); service.poll()
				else:
					var event := InputEventMouseButton.new(); event.position=point; event.global_position=point
					event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; root.push_input(event,true)
					event.pressed=false; root.push_input(event,true); service.poll()
			var target: int = -1 if clear_expected else int(header_rows[0].id)
			if world.calls.size() != before+1 or int(world.calls[-1].get("owner_id",-2)) != target or controller.stockpile_page != "owner":
				push_error("Owner pointer action duplicated, wrong, or closed before native receipt"); quit(1); return
			if type_name == "Tomb" and owner == -1:
				var pending_owner_ticket: int = controller.request_ticket
				world.top_z += 1; controller._process(0)
				if controller.request_ticket != pending_owner_ticket or not controller.candidates_state.mutating:
					push_error("Recenter discarded pending owner assignment");quit(1);return
			room.owner_id = target
			world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":11,"status":2,"areas":[room]}
			service.poll(); controller._process(0)
			if controller.stockpile_page != "types" or controller.candidates_view.visible:
				push_error("Owner picker did not close after successful native receipt"); quit(1); return
	var options_events := [0]
	controller.options_requested.connect(func(): options_events[0] += 1)
	for focus_filter in [false,true]:
		controller.use_area(bedroom); controller.zone_menu.controls.owner.pressed.emit()
		if focus_filter: controller.candidates_view.owner_search.grab_focus()
		var before_escape_calls: int = world.calls.size()
		var escape_owner := InputEventKey.new(); escape_owner.pressed=true; escape_owner.keycode=KEY_ESCAPE
		root.push_input(escape_owner,true)
		if controller.panel.visible or host.active != null or options_events[0] != (2 if focus_filter else 1) or world.calls.size()!=before_escape_calls:
			push_error("Owner Escape state: "+str([focus_filter,controller.panel.visible,host.active,options_events,world.calls.size(),before_escape_calls,controller.stockpile_page,controller.request_ticket]));quit(1);return
		host.activate(controller); controller.panel.show(); controller.available=true
	var recentered_tiles: Array = []
	controller.focus_requested.connect(func(tile): recentered_tiles.append(tile))
	controller.use_area(bedroom); controller.zone_menu.controls.owner.pressed.emit(); service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
		"area":{"list_revision":101,"candidates":header_rows}}
	service.poll();controller._process(0)
	var recenter_key := InputEventKey.new();recenter_key.pressed=true;recenter_key.keycode=KEY_C;recenter_key.ctrl_pressed=true
	root.push_input(recenter_key,true)
	if not controller.panel.visible or not recentered_tiles.is_empty():push_error("Remove row must not recenter");quit(1);return
	controller.candidates_view.owner_selected=1
	root.push_input(recenter_key,true)
	if not controller.panel.visible or not recentered_tiles.is_empty():push_error("Missing unit position must not close Zones");quit(1);return
	world.unit_tiles[int(header_rows[0].id)]=Vector3i(8,9,3)
	var recenter_before_calls: int=world.calls.size()
	root.push_input(recenter_key,true)
	if controller.panel.visible or host.active!=null or recentered_tiles!=[Vector3i(8,9,3)] or world.calls.size()!=recenter_before_calls:
		push_error("Ctrl+C must leave Zones and recenter without a mutation");quit(1);return
	host.activate(controller);controller.panel.show();controller.available=true
	# Capture each observed zone type, including panels with no extra controls.
	for definition in controller.zone_types:
		var type_name: String = definition.name
		var typed: Dictionary = bedroom.duplicate(true)
		typed.zone_type = definition.id; typed.zone_label = definition.label
		typed.name = "Unnamed " + str(typed.zone_label).to_lower()
		typed.owner_allowed = type_name in ["Bedroom","DiningHall","Office","Tomb"]
		typed.zone_settings = {"pond_mode":1,"facing":2,"tomb_citizens":1,"tomb_pets":0,"gather_trees":1,"gather_shrubs":1,"gather_fallen":1}
		controller.use_area(typed); controller._process(0)
		await process_frame; await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join("controller_zone_"+type_name.to_lower()+".png")) != OK: quit(1); return
	var pen: Dictionary = bedroom.duplicate(true); pen.zone_type = 88; pen.zone_label = "Pen/Pasture"; pen.name = "Unnamed pen/pasture"; pen.owner_allowed = false
	controller.use_area(pen); controller.zone_menu.controls.animals.pressed.emit(); service.poll()
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":14,"status":2,
		"area":{"list_revision":96,"candidates":[{"id":24,"name":"Stray Goat","profession":"Goat","sex":0,"grazer":true,"assigned":false},
			{"id":25,"name":"Dog","profession":"Dog","sex":1,"grazer":false,"assigned":true}]}}
	service.poll(); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_animals.png")) != OK: quit(1); return
	controller.handle_back()
	var squad_help=preload("res://scripts/native_hover_view.gd").new()
	root.add_child(squad_help);squad_help.configure(world);squad_help.layout(Vector2(root.size));squad_help.set_process(false)
	controller.candidates_view.native_help=squad_help
	var squad_hover_reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_squads.json")).hover_reference
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
		var symbol_reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_squads.json")).symbol_reference
		for sample in symbol_reference.observations:
			if not str(sample.capture).begins_with(type_name+"-"): continue
			var facts := {"index":int(sample.index),"foreground":[],"background":[]}
			for key in ["foreground","background"]:
				for value in sample[key]: facts[key].append(int(value))
			controller.candidates_state.rows=[{"id":int(sample.id),"entity":3,"name":"The Golden Beaks","squad_use":2,"squad_symbol":facts}]
			controller.candidates_state.changed.emit()
			var icon = controller.candidates_view.choices[0].get_node_or_null("SquadSymbol")
			if icon==null or icon.texture==null:push_error("Squad symbol absent");quit(1);return
			var pixels: Image=icon.texture.get_image();pixels.convert(Image.FORMAT_RGBA8)
			var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(pixels.get_data())
			if digest.finish().hex_encode()!=str(sample.solid_sha256):push_error("Squad texture differs from native");quit(1);return
			await process_frame;await RenderingServer.frame_post_draw
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
			var crop:=rendered.get_region(Rect2i(Vector2i(icon.global_position),Vector2i(32,32)))
			digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
			if digest.finish().hex_encode()!=str(sample.rgb_sha256):push_error("Rendered squad symbol differs from native");quit(1);return
			crop.save_png(directory.path_join("squad-symbol-"+str(sample.capture)+"-"+str(sample.id)+".png"))
			if str(sample.capture)==type_name+"-picker" and int(sample.id)==120:
				root.get_texture().get_image().save_png(directory.path_join("controller_squad_symbol_"+type_name.to_lower()+".png"))
		var name_reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_squads.json")).name_render_reference
		for sample in name_reference.observations:
			if not str(sample.capture).begins_with(type_name+"-"):continue
			var facts:Dictionary={"index":int(sample.symbol[0]),"foreground":[],"background":[]}
			for n in 3:
				facts.foreground.append(int(sample.symbol[n+1]));facts.background.append(int(sample.symbol[n+4]))
			controller.candidates_state.rows=[{"id":int(sample.id),"entity":3,"name":str(sample.caption),"squad_use":int(sample.squad_use),"squad_symbol":facts}]
			controller.candidates_state.changed.emit()
			await process_frame;await RenderingServer.frame_post_draw
			var button:Button=controller.candidates_view.choices[0]
			if not button.tooltip_text.is_empty():push_error("Squad name exposes absent native tooltip");quit(1);return
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
			var crop:=rendered.get_region(Rect2i(Vector2i(button.global_position)+Vector2i(56,12),Vector2i(int(sample.width),12)))
			crop.save_png(directory.path_join("squad-name-"+str(sample.capture)+".png"))
			var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
			if digest.finish().hex_encode()!=str(sample.rgb_sha256):push_error("Rendered squad name differs from native: "+str(sample.capture));quit(1);return
		for sample in squad_hover_reference.observations:
			if not str(sample.capture).begins_with(type_name+"-"):continue
			var target:Button
			for control in controller.candidates_view.squad_buttons:
				if int(control.get_meta("squad_use"))==int(sample.use):target=control;break
			if target==null or target.focus_mode!=Control.FOCUS_NONE or not target.tooltip_text.is_empty() or squad_help.SQUAD_HELP[int(sample.use)]!=sample.lines:
				push_error("Squad native help mapping/text differs");quit(1);return
			squad_help.reset()
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(4,400);motion.global_position=motion.position;root.push_input(motion,true)
			motion=InputEventMouseMotion.new();motion.position=target.get_global_rect().get_center();motion.global_position=motion.position;root.push_input(motion,true)
			if squad_help.state.key!="squad_"+str(int(sample.use)) or squad_help.visible:
				push_error("Squad hover hitbox/delay differs");quit(1);return
			squad_help.state.started=Time.get_ticks_msec()-500;squad_help._process(0)
			if not squad_help.visible:push_error("Squad help absent after dwell");quit(1);return
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("squad-"+str(sample.capture)+".png"))
			motion=InputEventMouseMotion.new();motion.position=Vector2(4,400);motion.global_position=motion.position;root.push_input(motion,true)
			if squad_help.visible:push_error("Squad hover survived pointer leave");quit(1);return
			target.mouse_entered.emit();controller.candidates_state.mutating=true;controller.candidates_view.refresh()
			if squad_help.visible:push_error("Busy squad retained hover");quit(1);return
			controller.candidates_state.mutating=false;controller.candidates_view.refresh()
			target.mouse_entered.emit();controller.candidates_view.hide()
			if squad_help.visible:push_error("Hidden squad retained hover");quit(1);return
			controller.candidates_view.show()
		var scroll_reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_squads.json")).scroll_reference
		var long_rows:Array=[]
		for id in scroll_reference.ids:
			var row:Dictionary={"id":int(id),"entity":3,"name":"","squad_use":0}
			for observed in scroll_reference.rows:
				if int(observed.id)==int(id):row.name=str(observed.name);break
			long_rows.append(row)
		controller.candidates_state.rows=long_rows;controller.candidates_state.changed.emit()
		await process_frame
		if controller.candidates_view.squad_buttons[0].position.x!=(504 if type_name=="ArcheryRange" else 408):
			push_error("Squad controls failed to reserve native scrollbar space");quit(1);return
		for sample in scroll_reference.observations:
			if not str(sample.capture).begins_with(type_name+"-"):continue
			var action:=str(sample.capture).split("-longlist-")[1]
			var wheel:=0;var page:=false
			if action.begins_with("CONTEXT_SCROLL_"):
				wheel=MOUSE_BUTTON_WHEEL_DOWN if action.ends_with("DOWN") else MOUSE_BUTTON_WHEEL_UP
				page="PAGE" in action
			if action=="bottom":
				for step in 30:
					var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;event.position=Vector2(500,150);event.global_position=event.position;root.push_input(event,true)
			elif wheel!=0:
				var event:=InputEventMouseButton.new();event.button_index=wheel;event.pressed=true;event.shift_pressed=page;event.position=Vector2(500,150);event.global_position=event.position;root.push_input(event,true)
			elif action.begins_with("arrow-") or action.begins_with("track-"):
				var y:int={"arrow-down":452,"arrow-up":106,"track-down":420,"track-up":120}[action]
				var motion:=InputEventMouseMotion.new();motion.position=Vector2(928,y);motion.global_position=motion.position;root.push_input(motion,true)
				for pressed in [true,false]:
					var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=Vector2(928,y);event.global_position=event.position;root.push_input(event,true)
			elif action.begins_with("STANDARDSCROLL_"):
				var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_DOWN
				if controller.candidates_view.feed_owner_key(event):push_error("Squad picker consumed unsupported keyboard scroll");quit(1);return
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(4,400);motion.global_position=motion.position;root.push_input(motion,true)
			await process_frame;await RenderingServer.frame_post_draw
			var bar=controller.candidates_view.owner_scrollbar
			if bar.first!=int(sample.first) or controller.candidates_view.scroll.scroll_vertical!=bar.first*36:
				push_error("Squad scroll differs: "+action);quit(1);return
			if controller.candidates_view.choices[bar.first].global_position.y!=controller.candidates_view.scroll.global_position.y:
				push_error("Squad visible content did not follow scrollbar: "+action);quit(1);return
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
			var crop:=rendered.get_region(Rect2i(Vector2i(bar.global_position),Vector2i(16,360)))
			crop.save_png(directory.path_join("squad-scroll-"+str(sample.capture)+".png"))
			var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
			if digest.finish().hex_encode()!=str(sample.bar_rgb_sha256):push_error("Squad scrollbar pixels differ: "+action);quit(1);return
		controller.candidates_state.rows=[];controller.candidates_state.changed.emit()
		await process_frame
		controller.candidates_state.receipt+=1;controller.candidates_state.rows=long_rows;controller.candidates_state.changed.emit()
		for frame in 4:await process_frame
		if controller.candidates_view.owner_scrollbar.first!=15 or controller.candidates_view.choices[15].global_position.y!=controller.candidates_view.scroll.global_position.y:
			push_error("Squad receipt rebuild lost visible scroll position");quit(1);return
		var drag_reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_squads.json")).drag_reference
		for sample in drag_reference.observations:
			if not str(sample.capture).begins_with(type_name+"-"):continue
			var bar=controller.candidates_view.owner_scrollbar;bar.move_to(0)
			await process_frame
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(932,128);motion.global_position=motion.position;root.push_input(motion,true)
			var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.position=motion.position;press.global_position=press.position;root.push_input(press,true)
			motion=InputEventMouseMotion.new();motion.position=Vector2(932,int(sample.destination)*12+8);motion.global_position=motion.position;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
			if not bar.dragging or bar.first!=int(sample.first):push_error("Squad drag differs: "+str(sample.capture));quit(1);return
			var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=motion.position;release.global_position=release.position;root.push_input(release,true)
			motion=InputEventMouseMotion.new();motion.position=Vector2(4,400);motion.global_position=motion.position;root.push_input(motion,true)
			await process_frame;await RenderingServer.frame_post_draw
			if bar.dragging:push_error("Squad drag survived release");quit(1);return
			var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
			var crop:=rendered.get_region(Rect2i(Vector2i(bar.global_position),Vector2i(16,360)))
			var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
			if digest.finish().hex_encode()!=str(sample.bar_rgb_sha256):push_error("Squad drag pixels differ: "+str(sample.capture));quit(1);return
		controller.handle_back()
		if squad_help.visible or not squad_help.state.key.is_empty():push_error("Closed squad picker retained hover");quit(1);return
	controller.candidates_view.native_help=null;squad_help.free()
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
	controller.choose_zone_type(92); controller._process(0)
	# Native overlapping-zone name row: arrows flank the shifted name/rename.
	controller.zone_overlaps = [bedroom.duplicate(true),bedroom.duplicate(true)]
	controller.zone_overlaps[1].id = int(bedroom.id)+1
	controller.use_area(bedroom,false); controller._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	if not controller.zone_menu.controls.previous.visible or controller.zone_menu.controls.rename.position.x != 254:
		push_error("Native overlap header navigation missing"); quit(1); return
	if root.get_texture().get_image().save_png(directory.path_join("controller_zone_overlap.png")) != OK: quit(1); return
	controller.choose_zone_type(92); controller._process(0)
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
	var status_icon = controller.settings_view.rendered_rows[0][0].get_node("Status")
	if controller.settings_view.rendered_rows[0][0].get_global_rect() != Rect2(48,112,264,36) or status_icon.get_global_rect() != Rect2(272,112,32,36):
		push_error("Settings category rows overlap the native scrollbar strip or misplace status artwork"); quit(1); return
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
	controller.use_area(saved_owner_area)
	controller.stockpile_page="animals";controller.candidates_state.area=saved_owner_area
	controller.candidates_state.kind=2;controller.candidates_state.pending={};controller.candidates_state.mutating=false
	controller.update_controls();controller.candidates_state.changed.emit();await process_frame
	root.push_input(filter_shortcut,true)
	if not controller.candidates_view.owner_search.has_focus():push_error("Animal controller Ctrl+F failed");quit(1);return
	leave_filter.pressed=true;root.push_input(leave_filter,true);leave_filter.pressed=false;root.push_input(leave_filter,true)
	if controller.candidates_view.owner_search.has_focus() or controller.stockpile_page!="animals":push_error("Animal right-click closed focused selector");quit(1);return
	leave_filter.pressed=true;root.push_input(leave_filter,true);leave_filter.pressed=false;root.push_input(leave_filter,true)
	if controller.stockpile_page=="animals" or not controller.panel.visible:push_error("Animal second right-click must return to Zones");quit(1);return
	controller.stockpile_page="animals";controller.candidates_state.area=saved_owner_area;controller.candidates_state.kind=2
	controller.update_controls();controller.candidates_state.changed.emit();root.push_input(filter_shortcut,true)
	var animal_options_before: int=options_events[0]
	var animal_escape:=InputEventKey.new();animal_escape.keycode=KEY_ESCAPE;animal_escape.pressed=true;root.push_input(animal_escape,true)
	if controller.panel.visible or options_events[0]!=animal_options_before+1:push_error("Animal focused Escape must close Zones and open Options");quit(1);return
	controller.close_panel(); controller.free(); host.free(); service.free(); interaction.free()
	# Exercise actual view callbacks with colliding typed identities. This is
	# input/identity coverage, not acceptance of the unfinished animal layout.
	var animal_state = preload("res://scripts/area_candidates_state.gd").new()
	var animal_view = preload("res://scripts/area_candidates_view.gd").new()
	var animal_requests: Array = []
	animal_state.request_ready.connect(func(request): animal_requests.append(request))
	root.add_child(animal_view); animal_view.configure(world,animal_state)
	world.portrait_requests.clear()
	animal_state.open({"id":82,"kind":1,"revision":14},2)
	animal_state.accept({"list_revision":1,"candidates":[
		{"id":24,"entity":2,"name":"Fixture item","assigned":true},
		{"id":24,"entity":1,"name":"Fixture unit","assigned":false}]},animal_requests[-1])
	await process_frame; await RenderingServer.frame_post_draw
	if animal_view.choices.size() != 2 or not world.portrait_requests.is_empty() or animal_view.portrait_slots.size() != 2:
		push_error("Animal view confused typed portrait identities"); quit(1); return
	for index in 2:
		var expected: Array = [2 if index == 0 else 1,24]
		if animal_view.choices[index].pressed.get_connections()[0].callable.get_bound_arguments() != expected:
			push_error("Animal view lost typed button identity"); quit(1); return
	var animal_headers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_headers
	if animal_state.sort != 2 or animal_state.descending:
		push_error("Animal header default is not Category ascending"); quit(1); return
	for sample in animal_headers.samples:
		animal_state.sort = int(sample.sort); animal_state.descending = bool(sample.descending)
		animal_state.sort_directions = sample.directions.duplicate(); animal_state.changed.emit()
		await process_frame; await RenderingServer.frame_post_draw
		var header_image := root.get_texture().get_image(); header_image.convert(Image.FORMAT_RGB8)
		var header_crop := header_image.get_region(Rect2i(Vector2i(animal_view.headers[0].global_position),Vector2i(232,12)))
		var header_hash := HashingContext.new(); header_hash.start(HashingContext.HASH_SHA256); header_hash.update(header_crop.get_data())
		header_crop.save_png(directory.path_join(str(sample.name)+"-df3d-header.png"))
		if header_hash.finish().hex_encode() != str(sample.rgb_sha256):
			push_error("Native animal header pixels differ: "+str(sample.name)); quit(1); return
	animal_view.choices[0].pressed.emit()
	if animal_requests[-1].get("item_id",-1) != 24 or animal_requests[-1].has("unit_id") or animal_requests[-1].assign != 0:
		push_error("Rendered item button dispatched a unit request"); quit(1); return
	animal_state.pending = {}; animal_state.mutating = false
	var animal_text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_text_pixels
	for sample in animal_text.samples:
		for key in ["color","alternate"]:
			for component in 3: sample.display.name_color[key][component] = int(sample.display.name_color[key][component])
		animal_state.rows = [{"id":int(sample.id),"entity":1,"animal_display":sample.display,"assigned":false}]
		animal_state.changed.emit()
		await process_frame; await RenderingServer.frame_post_draw
		var text_image := root.get_texture().get_image(); text_image.convert(Image.FORMAT_RGB8)
		var text_crop := text_image.get_region(Rect2i(Vector2i(animal_view.choices[0].global_position)+Vector2i(40,0),Vector2i(200,36)))
		# Text-only comparison: native selection/background artwork is a separate unfinished surface.
		var glyph_bytes := text_crop.get_data()
		for pixel in 200*36:
			var offset := pixel*3
			var foreground := false
			for rgb in sample.foreground_rgb:
				if glyph_bytes[offset]==int(rgb[0]) and glyph_bytes[offset+1]==int(rgb[1]) and glyph_bytes[offset+2]==int(rgb[2]): foreground=true
			if not foreground:
				glyph_bytes[offset]=0; glyph_bytes[offset+1]=0; glyph_bytes[offset+2]=0
		var text_hash := HashingContext.new(); text_hash.start(HashingContext.HASH_SHA256); text_hash.update(glyph_bytes)
		text_crop.save_png(directory.path_join("animal-"+str(sample.picker)+"-"+str(sample.id)+".png"))
		if text_hash.finish().hex_encode() != str(sample.glyph_rgb_sha256):
			push_error("Native animal text pixels differ: "+str(sample.picker)+"/"+str(sample.id)); quit(1); return
	var animal_navigation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_navigation
	animal_state.rows = []
	for index in 2:
		var sample: Dictionary = animal_text.samples[index]
		animal_state.rows.append({"id":int(sample.id),"entity":1,"animal_display":sample.display,"assigned":false})
	animal_state.receipt += 1; animal_state.changed.emit()
	for sample in animal_navigation.row_samples:
		if int(sample.selected) == 1:
			var key := InputEventKey.new(); key.pressed=true; key.keycode=KEY_DOWN
			if not animal_view.feed_owner_key(key) or animal_view.owner_selected != 1:
				push_error("Animal down navigation failed"); quit(1); return
		await process_frame; await RenderingServer.frame_post_draw
		var selection_image := root.get_texture().get_image(); selection_image.convert(Image.FORMAT_RGB8)
		for index in 2:
			var crop := selection_image.get_region(Rect2i(Vector2i(animal_view.choices[index].global_position)+Vector2i(40,0),Vector2i(216,36)))
			crop.save_png(directory.path_join(str(sample.name)+"-row-"+str(index)+".png"))
			var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(crop.get_data())
			if digest.finish().hex_encode() != str(sample.row_rgb_sha256[index]):
				push_error("Animal selection row pixels differ: "+str(sample.name)+"/"+str(index)); quit(1); return
	for keycode in [KEY_PAGEUP,KEY_PAGEDOWN,KEY_UP]:
		var key := InputEventKey.new(); key.pressed=true; key.keycode=keycode
		animal_view.feed_owner_key(key)
		if animal_view.owner_selected != (1 if keycode==KEY_PAGEDOWN else 0):
			push_error("Animal navigation clamp differs"); quit(1); return
	for entity in [1,2]:
		animal_state.pending={}; animal_state.mutating=false
		animal_state.rows=[{"id":24,"entity":entity,"assigned":false}]
		animal_state.receipt+=1; animal_state.changed.emit()
		var enter := InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER
		var before := animal_requests.size()
		if not animal_view.feed_owner_key(enter): push_error("Animal Enter not handled");quit(1);return
		enter.echo=true; animal_view.feed_owner_key(enter)
		var identity := "unit_id" if entity==1 else "item_id"
		if animal_requests.size()!=before+1 or int(animal_requests[-1].get(identity,-1))!=24 or animal_requests[-1].assign!=1:
			push_error("Animal keyboard assignment lost identity or repeated");quit(1);return
	var animal_portraits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_portrait_pixels
	for sample in animal_portraits.samples:
		var row: Dictionary = sample.row
		if row.has("animal_display"):
			for key in ["color","alternate"]:
				for component in 3: row.animal_display.name_color[key][component]=int(row.animal_display.name_color[key][component])
		for layer in row.sheet_icon.layers:
			for component in layer.size(): layer[component]=int(layer[component])
		animal_state.pending={}; animal_state.mutating=false
		animal_state.rows=[row,{"id":-1,"entity":0}]
		animal_view.owner_selected=0 if bool(sample.selected) else 1
		animal_state.changed.emit()
		var slot: Dictionary = animal_view.portrait_slots[0]
		slot.view.texture=world.candidate_icon(slot.recipe);slot.loaded=true
		if slot.view.texture==null: push_error("Animal selector recipe did not render");quit(1);return
		await process_frame; await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var crop := image.get_region(Rect2i(Vector2i(animal_view.choices[0].global_position),Vector2i(40,36)))
		crop.save_png(directory.path_join("animal-portrait-"+str(sample.picker)+"-"+str(row.id)+".png"))
		var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if digest.finish().hex_encode()!=str(sample.rgb_sha256):
			push_error("Native animal portrait pixels differ: "+str(sample.picker)+"/"+str(row.id));quit(1);return
	var animal_badges: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_zone_badge_pixels
	for sample in animal_badges.samples:
		var row: Dictionary = sample.row
		for key in ["color","alternate"]:
			for component in 3: row.animal_display.name_color[key][component]=int(row.animal_display.name_color[key][component])
		animal_state.pending={}; animal_state.mutating=false; animal_state.rows=[row]
		animal_view.owner_selected=0; animal_state.changed.emit()
		if animal_view.choices[0].get_node_or_null("AnimalStatus")==null:
			push_error("Native animal zone badge absent");quit(1);return
		await process_frame; await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var origin := Vector2i(animal_view.choices[0].global_position)+Vector2i(240,0)
		var crop := image.get_region(Rect2i(origin,Vector2i(40,36)))
		crop.save_png(directory.path_join("animal-status-"+str(sample.capture)+".png"))
		var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if digest.finish().hex_encode()!=str(sample.rgb_sha256):
			push_error("Native animal status pixels differ: "+str(sample.capture));quit(1);return
	var animal_containers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_container_pixels
	for sample in animal_containers.samples:
		var row: Dictionary = sample.row
		for key in ["material_family","occupant_entity","occupant_id"]: row.animal_container[key]=int(row.animal_container[key])
		if row.animal_container.has("occupant"):
			for layer in row.animal_container.occupant.layers:
				for index in layer.size(): layer[index]=int(layer[index])
		for key in ["color","alternate"]:
			for component in 3: row.animal_display.name_color[key][component]=int(row.animal_display.name_color[key][component])
		animal_state.pending={};animal_state.mutating=false;animal_state.rows=[row,{"id":-1,"entity":0}]
		animal_view.owner_selected=1;animal_state.changed.emit()
		var indicator = animal_view.choices[0].get_node_or_null("AnimalStatus")
		if indicator==null or indicator.texture==null: push_error("Owned cage image absent");quit(1);return
		var pixels: Image = indicator.texture.get_image();pixels.convert(Image.FORMAT_RGBA8)
		var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(pixels.get_data())
		if digest.finish().hex_encode()!=str(sample.rgba_sha256): push_error("Owned cage RGBA differs: "+str(sample.capture));quit(1);return
		await process_frame;await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var crop := image.get_region(Rect2i(Vector2i(animal_view.choices[0].global_position)+Vector2i(240,0),Vector2i(40,36)))
		crop.save_png(directory.path_join("animal-container-"+str(sample.capture)+".png"))
		digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if digest.finish().hex_encode()!=str(sample.rgb_sha256): push_error("Native cage row pixels differ: "+str(sample.capture));quit(1);return
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_fallback_pixels.sample
	for key in ["color","alternate"]:
		for component in 3: fallback.row.animal_display.name_color[key][component]=int(fallback.row.animal_display.name_color[key][component])
	animal_state.rows=[fallback.row,{"id":-1,"entity":0}];animal_view.owner_selected=1;animal_state.changed.emit()
	var fallback_indicator = animal_view.choices[0].get_node_or_null("AnimalStatus")
	if fallback_indicator==null or fallback_indicator.texture==null:push_error("Native missing container artwork absent");quit(1);return
	await process_frame;await RenderingServer.frame_post_draw
	var fallback_image := root.get_texture().get_image();fallback_image.convert(Image.FORMAT_RGB8)
	var fallback_crop := fallback_image.get_region(Rect2i(Vector2i(animal_view.choices[0].global_position)+Vector2i(240,0),Vector2i(40,36)))
	fallback_crop.save_png(directory.path_join("animal-container-fallback.png"))
	var fallback_digest := HashingContext.new();fallback_digest.start(HashingContext.HASH_SHA256);fallback_digest.update(fallback_crop.get_data())
	if fallback_digest.finish().hex_encode()!=str(fallback.rgb_sha256):push_error("Native missing container pixels differ");quit(1);return
	for invalid in [{},{"rope":1,"solid_color":"GRAY"},{"rope":true,"solid_color":"UNKNOWN_COLOR"},{"rope":false,"solid_color":"x".repeat(129)}]:
		if world.animal_restraint_icon(invalid)!=null:push_error("Malformed restraint image accepted");quit(1);return
	var restraints: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_restraint_pixels
	for sample in restraints.samples:
		var row: Dictionary = sample.row
		for key in ["color","alternate"]:
			for component in 3:row.animal_display.name_color[key][component]=int(row.animal_display.name_color[key][component])
		animal_state.rows=[row,{"id":-1,"entity":0}];animal_view.owner_selected=1;animal_state.changed.emit()
		var indicator=animal_view.choices[0].get_node_or_null("AnimalStatus")
		if indicator==null or indicator.texture==null:push_error("Native restraint image absent");quit(1);return
		var pixels: Image=indicator.texture.get_image();pixels.convert(Image.FORMAT_RGBA8)
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(pixels.get_data())
		if digest.finish().hex_encode()!=str(sample.rgba_sha256):push_error("Native restraint RGBA differs: "+str(sample.capture));quit(1);return
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var crop:=image.get_region(Rect2i(Vector2i(animal_view.choices[0].global_position)+Vector2i(240,0),Vector2i(40,36)))
		crop.save_png(directory.path_join("animal-restraint-"+str(sample.capture)+".png"))
		digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if digest.finish().hex_encode()!=str(sample.rgb_sha256):push_error("Native restraint row pixels differ: "+str(sample.capture));quit(1);return
	var item_text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_item_text_pixels
	for sample in item_text.samples:
		animal_state.rows=[sample.row,{"id":-1,"entity":0}];animal_view.owner_selected=0 if sample.selected else 1;animal_state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var crop:=image.get_region(Rect2i(Vector2i(animal_view.choices[0].global_position)+Vector2i(40,0),Vector2i(200,36)))
		crop.save_png(directory.path_join("animal-item-text-"+str(sample.capture)+".png"))
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if digest.finish().hex_encode()!=str(sample.rgb_sha256):push_error("Native item text pixels differ: "+str(sample.capture));quit(1);return
	var containment_help=preload("res://scripts/native_hover_view.gd").new()
	root.add_child(containment_help);containment_help.configure(world);containment_help.layout(Vector2(root.size));containment_help.set_process(false)
	animal_view.native_help=containment_help
	for relation in [1,2,3,4]:
		var row: Dictionary=restraints.samples[0].row.duplicate(true);row.animal_status.containment=relation
		animal_state.pending={};animal_state.mutating=false;animal_state.rows=[row];animal_state.changed.emit()
		await process_frame
		var target=animal_view.choices[0].get_node_or_null("AnimalContainmentHover")
		if target==null or target.position!=Vector2(240,0) or target.size!=Vector2(32,36):push_error("Containment hitbox differs");quit(1);return
		containment_help.reset()
		var outside: Vector2=target.global_position-Vector2(8,0)
		var motion:=InputEventMouseMotion.new();motion.position=outside;motion.global_position=outside;root.push_input(motion,true)
		motion=InputEventMouseMotion.new();motion.position=target.get_global_rect().get_center();motion.global_position=motion.position;root.push_input(motion,true)
		if containment_help.state.key!="containment_"+str(relation) or containment_help.visible:push_error("Containment hover target/delay differs");quit(1);return
		containment_help.state.started=Time.get_ticks_msec()-500;containment_help._process(0)
		if not containment_help.visible:push_error("Containment hover failed after dwell");quit(1);return
		motion=InputEventMouseMotion.new();motion.position=outside;motion.global_position=outside;root.push_input(motion,true)
		if containment_help.visible:push_error("Containment hover survived pointer leave");quit(1);return
		target.mouse_entered.emit();containment_help._process(0)
		animal_state.mutating=true;animal_state.changed.emit()
		if containment_help.visible:push_error("Busy row retained containment hover");quit(1);return
		animal_state.mutating=false;animal_state.changed.emit();target.mouse_entered.emit()
		animal_view.hide()
		if containment_help.visible:push_error("Hidden row retained containment hover");quit(1);return
		animal_view.show();target.mouse_entered.emit()
		animal_state.rows=[];animal_state.changed.emit();await process_frame
		if containment_help.visible or not containment_help.state.key.is_empty():push_error("Retired row retained containment hover");quit(1);return
	animal_state.pending={};animal_state.mutating=false;animal_state.rows=[restraints.samples[0].row];animal_state.changed.emit();await process_frame
	var click_target=animal_view.choices[0].get_node("AnimalContainmentHover")
	var before_click:=animal_requests.size()
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed
		click.position=click_target.get_global_rect().get_center();click.global_position=click.position;root.push_input(click,true)
	if animal_requests.size()!=before_click+1 or int(animal_requests[-1].get("unit_id",-1))!=int(restraints.samples[0].row.id):push_error("Containment hover swallowed animal assignment");quit(1);return
	animal_state.pending={};animal_state.mutating=false;animal_state.query="";animal_state.query_bytes=null;animal_state.rows=[];animal_state.changed.emit()
	var animal_focus:=InputEventKey.new();animal_focus.keycode=KEY_F;animal_focus.ctrl_pressed=true;animal_focus.pressed=true
	if not animal_view.feed_animal_key(animal_focus) or not animal_view.owner_search.has_focus():push_error("Animal Ctrl+F did not focus byte editor");quit(1);return
	var typed:=InputEventKey.new();typed.unicode=233;typed.pressed=true
	animal_view.feed_animal_key(typed)
	if animal_state.query_bytes!=PackedByteArray([195,169]):push_error("Animal editor converted native UTF-8 bytes");quit(1);return
	var backspace:=InputEventKey.new();backspace.keycode=KEY_BACKSPACE;backspace.pressed=true;animal_view.feed_animal_key(backspace)
	if animal_state.query_bytes!=PackedByteArray([195]):push_error("Animal Backspace did not remove one byte");quit(1);return
	animal_view.owner_search.ticks_override=250
	await process_frame;await RenderingServer.frame_post_draw
	var search_image:=root.get_texture().get_image();search_image.convert(Image.FORMAT_RGB8)
	var search_crop:=search_image.get_region(Rect2i(Vector2i(animal_view.owner_search.global_position),Vector2i(312,36)))
	search_crop.save_png(directory.path_join("animal-search-partial-utf8.png"))
	var search_hash:=HashingContext.new();search_hash.start(HashingContext.HASH_SHA256);search_hash.update(search_crop.get_data())
	var native_search: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_search_input
	if search_hash.finish().hex_encode()!=str(native_search.visual.filter_rgb_sha256):push_error("Animal native byte editor pixels differ");quit(1);return
	typed.unicode=120
	for i in 40:animal_view.feed_animal_key(typed)
	if animal_state.query_bytes.size()!=33:push_error("Animal editor byte limit differs");quit(1);return
	var enter:=InputEventKey.new();enter.pressed=true;enter.keycode=KEY_ENTER
	var calls_before:=animal_requests.size();animal_view.feed_animal_key(enter)
	if animal_view.owner_search.has_focus() or animal_requests.size()!=calls_before:push_error("Focused animal Enter assigned instead of leaving focus");quit(1);return
	# Native forty-row Pond reference: whole-row viewport, arrows/track and drag.
	animal_state.query_bytes=null;animal_state.query="";animal_state.search_delay=-1
	animal_state.pending={};animal_state.mutating=false;animal_state.cursor=0
	animal_state.rows=[]
	for i in 40:
		var row:Dictionary=restraints.samples[0].row.duplicate(true);row.id=30000+i
		animal_state.rows.append(row)
	animal_state.receipt=501;animal_state.changed.emit()
	await process_frame;await RenderingServer.frame_post_draw
	var animal_bar=animal_view.owner_scrollbar
	var scrolling:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_scroll
	for sample in scrolling.rendered_bar.samples:
		animal_bar.move_to(int(sample.first))
		await process_frame;await RenderingServer.frame_post_draw
		var clip:Rect2=animal_view.scroll.get_global_rect();var full:=0
		for button in animal_view.choices:
			if clip.encloses(button.get_global_rect()):full+=1
			elif clip.intersects(button.get_global_rect()):push_error("Animal viewport exposes partial row");quit(1);return
		if full!=16 or animal_view.scroll.scroll_vertical!=int(sample.first)*36:push_error("Animal viewport differs");quit(1);return
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var crop:=image.get_region(Rect2i(Vector2i(animal_bar.global_position),Vector2i(16,600)))
		crop.save_png(directory.path_join("animal_bar_%d.png"%int(sample.first)))
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
		if digest.finish().hex_encode()!=str(sample.rgb_sha256):push_error("Animal scrollbar pixels differ");quit(1);return
	for sample in scrolling.records:
		if str(sample.label).begins_with("drag-"):
			animal_bar.move_to(0);animal_bar.drag_to((int(str(sample.label).trim_prefix("drag-"))-7)*12+6)
			if animal_bar.first!=int(sample.scroll):push_error("Animal scrollbar drag differs");quit(1);return
	animal_bar.move_to(0)
	var animal_wheel:=InputEventMouseButton.new();animal_wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;animal_wheel.pressed=true
	animal_wheel.position=animal_view.scroll.global_position+Vector2(80,80)
	root.push_input(animal_wheel,true)
	if animal_bar.first!=1 or animal_view.owner_selected!=0:push_error("Animal wheel changed selection or step");quit(1);return
	animal_wheel.shift_pressed=true;root.push_input(animal_wheel,true)
	if animal_bar.first!=17:push_error("Animal shifted wheel page differs");quit(1);return
	animal_wheel.position=Vector2(2,2);root.push_input(animal_wheel,true)
	if animal_bar.first!=17:push_error("Outside animal wheel scrolled list");quit(1);return
	animal_bar.move_to(0);animal_view.owner_selected=0
	var page_down:=InputEventKey.new();page_down.keycode=KEY_PAGEDOWN;page_down.pressed=true
	for expected in [[16,1],[32,17],[39,24]]:
		animal_view.feed_animal_key(page_down)
		if animal_view.owner_selected!=expected[0] or animal_bar.first!=expected[1]:push_error("Animal keyboard scrolling differs");quit(1);return
	# Background facts replace presentation data without replacing interaction nodes.
	animal_state.rows=[restraints.samples[0].row.duplicate(true),{"id":-1,"entity":0}]
	animal_state.receipt=502;animal_state.changed.emit();animal_view.owner_selected=1;animal_view.refresh()
	await process_frame;await RenderingServer.frame_post_draw
	var stable_button:Button=animal_view.choices[0]
	var stable_hover=stable_button.get_node("AnimalContainmentHover")
	stable_button.grab_focus();stable_hover.mouse_entered.emit()
	containment_help.state.started=Time.get_ticks_msec()-500;containment_help._process(0)
	var old_hover_owner=containment_help.state.owner
	var refreshed_row:Dictionary=restraints.samples[1].row.duplicate(true)
	refreshed_row.id=animal_state.rows[0].id
	animal_state.rows[0]=refreshed_row;animal_state.facts_changed.emit()
	await process_frame;await RenderingServer.frame_post_draw
	if animal_view.choices[0]!=stable_button or not stable_button.has_focus() or animal_view.owner_selected!=1 or animal_view.owner_scrollbar.first!=0:
		push_error("Animal background refresh disrupted interaction");quit(1);return
	if stable_button.get_node("AnimalContainmentHover")!=stable_hover or containment_help.state.owner!=old_hover_owner or not containment_help.visible:
		push_error("Animal artwork refresh reset unchanged containment hover");quit(1);return
	var refreshed_image:=root.get_texture().get_image();refreshed_image.convert(Image.FORMAT_RGB8)
	var refreshed_crop:=refreshed_image.get_region(Rect2i(Vector2i(stable_button.global_position)+Vector2i(240,0),Vector2i(40,36)))
	var refreshed_digest:=HashingContext.new();refreshed_digest.start(HashingContext.HASH_SHA256);refreshed_digest.update(refreshed_crop.get_data())
	if refreshed_digest.finish().hex_encode()!=str(restraints.samples[1].rgb_sha256):push_error("Refreshed animal restraint differs from native pixels");quit(1);return
	var evicted:Dictionary=refreshed_row.duplicate();evicted.erase("sheet_icon")
	animal_state.rows[0]=evicted;animal_state.facts_changed.emit()
	if not animal_view.portrait_slots[0].recipe.is_empty() or animal_view.portrait_slots[0].view.texture!=null:push_error("Animal view retained evicted portrait");quit(1);return
	var no_status:Dictionary=evicted.duplicate(true);no_status.animal_status={"kind":0,"containment":0,"item_id":-1};no_status.erase("animal_restraint")
	animal_state.rows[0]=no_status;animal_state.facts_changed.emit()
	if stable_button.has_node("AnimalContainmentHover") or containment_help.visible:push_error("Changed containment retained old hover");quit(1);return
	animal_view.free();containment_help.free()
	assets.free(); await process_frame
	print("AREA_MENUS_CAPTURE_PASS")
	quit()
