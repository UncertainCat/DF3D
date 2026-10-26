extends SceneTree
# Recorded native leaf rows exercise layout across asynchronous reply gaps.
# Root/sublist rows are test scaffolding, not full-panel parity evidence.
const State = preload("res://scripts/area_settings_state.gd")
var state = State.new()
var view
var failures := 0

func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func settle() -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw

func reply(values: Array, total := -1, next_cursor := 0) -> void:
	state.accept({"list_key":state.pending.list_key,"query":state.pending.query,
		"settings":values,"list_revision":123,"next_cursor":next_cursor,"settings_count":total},state.pending.duplicate(true))

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(77); return
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_scroll.json"))
	var lists := {}
	for key in fixture.lists:
		var rows: Array = []
		for row in fixture.lists[key].rows:
			rows.append({"key":key+"/"+str(rows.size()),"label":row.label,"kind":4,"state":2 if row.enabled else 1})
		lists[key] = rows
	root.size = Vector2i(1200,800)
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	view = preload("res://scripts/area_settings_view.gd").new()
	root.add_child(view); view.position = Vector2(40,64); view.configure(assets,state)
	state.open({"id":39,"revision":1,"categories":131071})
	reply([{"key":"food","label":"Food","kind":1,"state":1}])
	reply([{"key":"food/meat","label":"Meat","kind":2,"state":1},{"key":"food/fish","label":"Fish","kind":2,"state":1}])
	reply(lists["food-top"]); await settle()
	check(view.search.get_global_rect() == Rect2(736,64,224,36),"native search rectangle: "+str(view.search.get_global_rect()))
	view.scrolls[2].scroll_vertical = 30 * 36; await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"native row30 is reachable")
	state.select(1,state.rows[1][1]); await settle()
	reply(lists["different-leaf"]); await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"different leaf preserves native scroll across delayed reply")
	state.select(0,state.rows[0][0]); await settle()
	reply([{"key":"food/meat","label":"Meat","kind":2,"state":1},{"key":"food/fish","label":"Fish","kind":2,"state":1}])
	reply(lists["food-top"]); await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"same category preserves native scroll across delayed reply")
	state.search("a"); await settle()
	reply(lists["search-a"]); await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"search preserves native scroll across delayed reply")
	state.open({"id":39,"revision":2,"categories":131071},true); await settle()
	reply([{"key":"food","label":"Food","kind":1,"state":1}])
	reply([{"key":"food/meat","label":"Meat","kind":2,"state":1}])
	reply(lists["search-a"]); await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"refresh preserves scroll")
	state.search("zzzznomatch"); await settle(); reply([]); await settle()
	check(view.rendered_rows[2].is_empty(),"unmatched search renders no rows")
	state.search("a"); await settle(); reply(lists["search-a"]); await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"empty result retains native offset for later results")
	state.search("alpaca"); await settle(); reply(lists["short"]); await settle()
	check(view.scrolls[2].scroll_vertical == 0 and view.rendered_rows[2].size() == 12,"short result displays all twelve native rows from the top")
	state.search("a"); await settle(); reply(lists["search-a"]); await settle()
	check(view.scrolls[2].scroll_vertical == 1080,"short result retains native offset for later results")
	var directory := ProjectSettings.globalize_path("res://../../../build/qa/stockpile-scroll-render")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join("scrolled.png"))
	# Synthetic distant window tests transport/layout; recorded rows above remain
	# the visual source. These repeated labels are not native ordering evidence.
	state.open({"id":39,"revision":3,"categories":131071})
	reply([{"key":"food","label":"Food","kind":1,"state":1}])
	reply([{"key":"food/meat","label":"Meat","kind":2,"state":1}])
	reply(lists["food-top"],12000,128); await settle()
	check(view.native_scrolls[2].count == 12000 and view.native_scrolls[2].thumb().y == 2,"native thumb uses full filtered count instead of loaded page")
	check(view.native_scrolls[2].get_global_rect() == Rect2(944,108,16,576),"native leaf scrollbar occupies recorded screen rectangle")
	view.native_scrolls[2].move_to(11984); await settle()
	check(state.pending.get("cursor",-1) == 11984,"scrollbar jump requests distant native range")
	reply(lists["food-top"].slice(0,16),12000); await settle()
	check(state.row_starts[2] == 11984 and view.rendered_rows[2].size() == 16,"distant range renders only fetched buttons")
	check(view.scrolls[2].scroll_vertical == 11984*36 and state.pending.is_empty(),"distant replacement preserves viewport without fetching an unwanted prefix")
	check(is_equal_approx(view.rendered_rows[2][0].global_position.y,112),"top spacer places distant first row at native list origin")
	view.native_scrolls[2].move_to(0); await settle()
	check(state.pending.get("cursor",-1) == 0,"scrollbar return requests first native range")
	reply(lists["food-top"],12000,128); await settle()
	check(state.row_starts[2] == 0 and view.scrolls[2].scroll_vertical == 0,"backward replacement preserves top viewport")
	var layout_fixture = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_layout.json"))
	for sample in layout_fixture.cases:
		view.layout(Vector2(sample.logical_view[0],sample.logical_view[1])); await settle()
		check(view.page_rows == int(sample.page_rows),"native resize page count: "+str(sample.name))
		check(view.scrolls[2].size.x == int(sample.leaf_width)-16,"native resize leaf width with scrollbar: "+str(sample.name))
		check(view.native_scrolls[2].size.y == int(sample.page_rows)*36,"native resize scrollbar height: "+str(sample.name))
		check(state.viewport_rows == int(sample.page_rows),"refresh uses current visible range: "+str(sample.name))
		view.native_scrolls[2].move_to(1); await settle()
		check(view.scrolls[2].scroll_vertical == 36,"resized list remains scrollable: "+str(sample.name))
		view.native_scrolls[2].move_to(0); await settle()
	view.layout(Vector2(960,640),503.2); await settle()
	check(view.page_rows == 12,"HUD clearance retains recorded native page when it fits")
	view.layout(Vector2(960,640),503.2,668); await settle()
	check(view.column_widths[2] == 56 and view.custom_minimum_size.x+12 <= 668,"settings width clears larger viewer HUD")
	view.layout(Vector2(1024,823),643); await settle()
	check(view.page_rows == 16 and view.scrolls[2].position.y+view.scrolls[2].size.y <= view.custom_minimum_size.y,"small viewer window keeps every visible row inside its panel")
	view.layout(Vector2(1200,800)); await settle()
	view.row_cache[2] = {}; view.render()
	check(view.layout_pending[2],"page rebuild must leave restoration pending")
	var wheel := InputEventMouseButton.new()
	wheel.position = view.get_global_transform_with_canvas() * (view.scrolls[2].position + Vector2(40,20))
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
	view._input(wheel); await settle()
	check(view.native_scrolls[2].first == 1 and view.scrolls[2].scroll_vertical == 36,"explicit wheel supersedes pending page restoration")
	state.clear(); await settle()
	check(view.scrolls[2].scroll_vertical == 0,"closing clears scroll")
	var caption_fixture = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_search.json"))
	var captions: Array = []
	for label in caption_fixture.rendered_captions.labels:
		captions.append({"key":"ammo/type/"+str(captions.size()),"label":label,"kind":4,"state":1})
	state.open({"id":39,"revision":4,"categories":131071})
	reply([{"key":"ammo","label":"Ammo","kind":1,"state":1}])
	reply([{"key":"ammo/type","label":"Type","kind":2,"state":1}])
	reply(captions); await settle()
	for index in captions.size():
		check(view.rendered_rows[2][index].get_child(0).text == captions[index].label,"native-provided caption was recased at row "+str(index))
	root.get_texture().get_image().save_png(directory.path_join("native-captions.png"))
	for sample in caption_fixture.caption_truncation.cases:
		state.clear(); await settle()
		view.layout(Vector2(int(sample.grid[0])*8,int(sample.grid[1])*12))
		state.open({"id":39,"revision":5,"categories":131071})
		reply([{"key":"ammo","label":"Ammo","kind":1,"state":1}])
		reply([{"key":"ammo/type","label":"Type","kind":2,"state":1}])
		var rows: Array = []
		for row in sample.rows: rows.append({"key":"ammo/type/"+str(rows.size()),"label":row.label,"kind":4,"state":1})
		reply(rows,int(sample.total)); await settle()
		for index in rows.size():
			var expected: String = sample.rows[index].label if sample.native_overflow else sample.rows[index].display
			check(view.rendered_rows[2][index].get_child(0).text == expected,"native truncation differs at "+str(sample.layout)+" "+str(sample.kind)+" row "+str(index))
		if sample.native_overflow:
			check(view.scrolls[2].clip_contents,"narrow item column must clip its contents")
			for button in view.rendered_rows[2]:
				var label: Label = button.get_child(0)
				check(label.visible and label.clip_text,"narrow item caption must remain visible and clipped")
				check(label.position.x + label.size.x <= view.scrolls[2].size.x,"narrow item caption exceeds column")
			root.get_texture().get_image().save_png(directory.path_join("clipped-"+str(sample.layout)+".png"))
		if sample.layout=="960x600-0": root.get_texture().get_image().save_png(directory.path_join("truncated-"+str(sample.kind)+".png"))
	view.free(); assets.free(); await process_frame
	print("AREA_SETTINGS_SCROLL_CAPTURE_PASS" if failures == 0 else "AREA_SETTINGS_SCROLL_CAPTURE_FAIL")
	quit(failures)

func _initialize() -> void:
	call_deferred("run")
