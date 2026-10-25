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

func reply(values: Array) -> void:
	state.accept({"settings":values,"list_revision":123,"next_cursor":0},state.pending.duplicate(true))

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
	var directory := ProjectSettings.globalize_path("res://../../../build/qa/stockpile-scroll-render")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join("scrolled.png"))
	state.clear(); await settle()
	check(view.scrolls[2].scroll_vertical == 0,"closing clears scroll")
	view.free(); assets.free(); await process_frame
	print("AREA_SETTINGS_SCROLL_CAPTURE_PASS" if failures == 0 else "AREA_SETTINGS_SCROLL_CAPTURE_FAIL")
	quit(failures)

func _initialize() -> void:
	call_deferred("run")
