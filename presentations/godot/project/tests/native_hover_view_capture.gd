extends SceneTree
const View=preload("res://scripts/native_hover_view.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=View.new();root.add_child(view);view.configure(assets);view.layout(Vector2(1200,800));view.set_process(false)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_hover.json"))
	var owner: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_assignment.json")).owner_tooltips
	data.panels.append(owner.recenter)
	var frame: Image=assets.ui_texture("HOVER_RECTANGLE").get_image()
	var font:=Image.load_from_file(assets.ui_font_path())
	var mapping={119352:Vector2i(0,12),119353:Vector2i(8,12),119416:Vector2i(0,24),119417:Vector2i(8,24)}
	var modes=["LOCATION_DETAILS_VISITORS_ALLOWED","LOCATION_DETAILS_RESIDENTS_ALLOWED","LOCATION_DETAILS_CITIZENS_ONLY","LOCATION_DETAILS_MEMBERS_ONLY","OWNER_RECENTER"]
	var animals: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_animals.json")).animal_containment_hover_reference
	for sample in animals.samples:
		var relation: int=int(sample.instruction)-366
		var key: String="CONTAINMENT_"+str(relation)
		modes.append(key)
		var cells: Array=[]
		for y in sample.text_lines.size():
			var text: String=sample.text_lines[y]
			for x in text.length(): cells.append({"x":126+x,"y":y,"ch":text.unicode_at(x),"fg":7,"bg":0,"bold":true})
		data.panels.append({"key":key,"lines":sample.text_lines,"text_cells":cells,"frame_cells":owner.recenter.frame_cells,"relation":relation})
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/native-hover-render")
	var specialization: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json")).specialization_reference.display_reference
	for sample in specialization.tooltips:
		var value: int=1 if int(sample.hover)==259 else 0
		var key: String="SPECIALIZATION_"+str(value)
		modes.append(key)
		var cells: Array=[]
		for y in sample.lines.size():
			var text: String=sample.lines[y]
			for x in text.length():cells.append({"x":126+x,"y":y,"ch":text.unicode_at(x),"fg":7,"bg":0,"bold":true})
		data.panels.append({"key":key,"lines":sample.lines,"text_cells":cells,"frame_cells":owner.recenter.frame_cells,"specialization":value})
	var staff: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json")).staff_indicator_reference.help_reference
	var help_keys={261:"tavern_keeper",262:"performer",263:"scholar",264:"scribe",265:"mercenary",266:"monster_slayer",267:"doctor",268:"workshop"}
	for sample in staff.cases:
		if int(sample.hover)<0:continue
		var key: String="STAFF_"+sample.name
		modes.append(key)
		var cells: Array=[]
		for y in sample.help_lines.size():
			var text: String=sample.help_lines[y]
			for x in text.length():cells.append({"x":126+x,"y":y,"ch":text.unicode_at(x),"fg":sample.text_style.fg,"bg":sample.text_style.bg,"bold":sample.text_style.bold})
		data.panels.append({"key":key,"lines":sample.help_lines,"text_cells":cells,"frame_cells":owner.recenter.frame_cells,"staff":help_keys[int(sample.hover)]})
	DirAccess.make_dir_recursive_absolute(directory)
	for panel in data.panels:
		var mode:=modes.find(str(panel.key))
		var expected_lines: Array=View.STAFF_HELP[panel.staff] if panel.has("staff") else View.SPECIALIZATION_HELP[int(panel.specialization)] if panel.has("specialization") else View.CONTAINMENT_HELP[int(panel.relation)-1] if panel.has("relation") else (View.OWNER_RECENTER_HELP if mode==4 else View.ACCESS_HELP[mode])
		if mode<0 or expected_lines!=panel.lines:push_error("Native help wording/wrapping differs");quit(1);return
		var letters: Dictionary={}
		for cell in panel.text_cells:
			letters[Vector2i(int(cell.x),int(cell.y))]=cell
		var hover_key: String="staff_"+panel.staff if panel.has("staff") else "specialization_"+str(panel.specialization) if panel.has("specialization") else "containment_"+str(panel.relation) if panel.has("relation") else ("owner_recenter" if mode==4 else str(mode))
		view.state.enter(1,hover_key,Time.get_ticks_msec()-500);view._process(0)
		for i in 3: await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for cell in panel.frame_cells:
			var point:=Vector2i(int(cell.x),int(cell.y));var tile:=int(cell.tile)
			if not mapping.has(tile):push_error("Unmapped native help frame tile");quit(1);return
			var origin: Vector2i=mapping[tile]
			var letter: Dictionary=letters.get(point,{})
			var ch:=int(letter.get("ch",0))
			var foreground: Color=view.palette[int(letter.get("fg",7))+(8 if bool(letter.get("bold",true)) else 0)]
			for y in 12:
				for x in 8:
					var expected:=frame.get_pixel(origin.x+x,origin.y+y)
					if ch>0:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						var alpha:=0.0 if ink.r>0.99 and ink.b>0.99 and ink.g<0.01 else maxf(ink.r,maxf(ink.g,ink.b))*ink.a
						expected=expected.lerp(foreground,alpha)
					var actual:=image.get_pixel(point.x*8+x,point.y*12+4+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						push_error("Native help pixel mismatch at "+str(point)+" pixel "+str(Vector2i(x,y)));quit(1);return
		if image.save_png(directory.path_join("access_%d.png"%mode))!=OK:quit(1);return
	view.reset();view.enter_owner_filter(42)
	if not view.visible:push_error("Native filter help is not immediate");quit(1);return
	for i in 3:await process_frame;await RenderingServer.frame_post_draw
	var filter_image:=root.get_texture().get_image();filter_image.convert(Image.FORMAT_RGB8)
	filter_image.save_png(directory.path_join("owner_filter.png"))
	var crop:=filter_image.get_region(Rect2i(1000,4,200,216))
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(crop.get_data())
	if digest.finish().hex_encode()!=str(owner.filter.rgb_sha256):push_error("Native owner filter help pixels differ");quit(1);return
	view.leave(41)
	if not view.visible:push_error("Unrelated control dismissed widget help");quit(1);return
	view.leave(42)
	if view.visible:push_error("Filter help remained after pointer leave");quit(1);return
	view.enter_owner_recenter(43)
	if view.visible:push_error("Widget tooltip incorrectly warmed recenter instructions");quit(1);return
	view.queue_free();assets.queue_free();await process_frame
	print("NATIVE_HOVER_VIEW_CAPTURE_PASS");quit(0)
