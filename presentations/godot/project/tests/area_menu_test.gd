extends SceneTree
const Data = preload("res://scripts/area_menu_data.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func values(rows: Array, key: String) -> Array:
	var result: Array = []
	for row in rows:
		# JSON numbers are floats; IDs/bits are integral semantic values.
		result.append(int(row[key]) if key in ["bit", "preset", "id"] else row[key])
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := Data.read()
	check(values(data.categories, "key") == ["ammo","animals","armor","bars_blocks","cloth","coins","finished_goods","food","furniture","gems","leather","corpses","refuse","sheet","stone","weapons","wood"], "native category display order")
	check(values(data.categories, "bit") == [6,0,15,8,12,7,10,1,2,9,11,3,4,16,5,14,13], "display order maps to wire bits")
	check(values(data.presets, "preset") == [1,8,2,17,10,14,9,5,12,3,4,11,13,6,18,7,16,15,19,0], "native preset grid maps to semantic preset IDs; Custom is local")
	check(values(data.presets, "label") == ["All","Ammo","Animals","Armor","Bars and Blocks","Cloth","Coins","Corpses","Finished Goods","Food","Furniture","Gem","Leather","Refuse","Sheets","Stone","Weapons","Wood","None","Custom"], "native preset captions and column-major order")
	check(values(data.zones, "name") == ["MeetingHall","Bedroom","DiningHall","Pen","Pond","WaterSource","Dungeon","FishingArea","SandCollection","Office","Dormitory","Barracks","ArcheryRange","Dump","AnimalTraining","Tomb","PlantGathering","ClayCollection"], "native zone grid order")
	var observed := Data.observed_zones(data, [{"id":97,"name":"Office","label":"Office"},{"id":0,"name":"Bedroom"},{"id":3,"name":"UnknownFutureZone"}])
	check(values(observed, "id") == [0,97] and values(observed, "label") == ["Bedroom","Office"], "catalog IDs are observed, including zero; unknown routes remain hidden")
	check(Data.observed_zones(data, []).is_empty(), "no fabricated zone IDs before catalog")
	check(Data.category_labels_by_bit(data)[13] == "Wood", "legacy controls retain wire category identity")
	var assets := Df3dWorld.new(); root.add_child(assets)
	check(assets.load_assets(OS.get_environment("DF3D_DF_PATH")), "installed assets available")
	for group in ["categories","presets","zones","paint_tools","stockpile_controls"]:
		for row in data[group]:
			check(str(row.evidence).begins_with("build/evidence/native/"), "menu entry retains evidence reference")
			check(assets.ui_texture(str(row.icon)) != null, "installed icon resolves: " + str(row.icon))
	var view := preload("res://scripts/area_stockpile_view.gd").new()
	root.add_child(view); view.configure(assets)
	check(view.controls.rename.get_node("Icon").texture != null, "native feather artwork resolves")
	view.display({"name":"Wood Stockpile #39","categories":8192,"links_only":true}, true)
	check(view.preset_buttons.size() == 20 and view.preset_buttons[10].position == Vector2(112,36), "second native preset column begins with Furniture")
	check(view.preset_buttons[19].position == Vector2(112,360), "Custom occupies last row of second column")
	check(not view.warning.visible and view.heading.text == "Wood Stockpile #39", "native name and nonempty flag state rendered")
	check(view.preset_buttons[17].get_node("Caption").get_theme_color("font_color") == Color("00ff00"), "observed Wood category highlighted")
	view.display({"name":"Stockpile #39","categories":0}, false)
	check(view.warning.visible and view.preset_buttons[0].disabled and view.controls.remove.disabled, "empty warning and busy gating")
	view.free()
	var zones := preload("res://scripts/area_zone_menu_view.gd").new()
	root.add_child(zones); zones.configure(assets)
	var chosen: Array = []; zones.type_selected.connect(func(id): chosen.append(id))
	zones.display(observed,true)
	check(zones.buttons.Office.position == Vector2(158,214), "partial catalog preserves native Office slot")
	check(not zones.buttons.MeetingHall.visible, "unobserved zone type stays hidden")
	zones.buttons.Bedroom.pressed.emit()
	check(chosen == [0], "zone menu forwards observed zero ID")
	zones.display(observed,false); zones.buttons.Office.pressed.emit()
	check(chosen == [0], "busy zone menu cannot submit a selection")
	zones.free()
	var state := preload("res://scripts/area_settings_state.gd").new()
	var settings := preload("res://scripts/area_settings_view.gd").new()
	root.add_child(settings); settings.configure(assets,state)
	state.area = {"id":39,"revision":11}; state.category = "wood"; state.leaf = "wood"
	state.rows = [[{"key":"wood","label":"Wood","kind":1,"state":1}],[],[{"key":"wood/0","label":"Oak","kind":4,"state":1}]]
	state.changed.emit()
	var original_button: Button = settings.rendered_rows[2][0]
	state.queue_search("oak")
	check(settings.rendered_rows[2][0] == original_button and original_button.disabled, "search busy state preserves row widgets and disables edits")
	check(settings.search.editable, "pending search leaves native search field editable")
	check(settings.search.position.y + settings.search.size.y <= 48, "search field cannot overlap first leaf row")
	check(settings.scrolls[0].get_v_scroll_bar().get_theme_stylebox("scroll").texture != null, "native scrollbar texture resolves")
	settings.free()
	var storage := preload("res://scripts/area_storage_view.gd").new()
	root.add_child(storage); storage.configure(assets)
	var edits: Array = []; storage.value_requested.connect(func(key,value): edits.append([key,value]))
	storage.display({"id":39,"revision":11,"tile_count":4,"barrels":4,"bins":1,"wheelbarrows":3},true)
	check(storage.controls.barrels[1].disabled and storage.controls.wheelbarrows[1].disabled,"storage limits use occupied tile count, wheelbarrows leave one tile")
	storage.controls.bins[1].pressed.emit()
	check(edits == [["bins",2]] and storage.labels.bins.text == "1","storage emits chosen value without optimistic count")
	storage.activate("bins",0); storage.submit_entry("5")
	check(edits.size() == 1 and storage.editing == "bins","over-cap numeric entry stays local")
	storage.submit_entry("3")
	check(edits[-1] == ["bins",3] and storage.editing.is_empty(),"native hash field accepts a valid exact value")
	storage.activate("barrels",0); storage.cancel_edit()
	check(edits.size() == 2 and not storage.entry.visible,"cancel numeric entry does not submit")
	storage.display({"id":39,"revision":12,"tile_count":4,"barrels":4,"bins":3,"wheelbarrows":3},false)
	check(storage.controls.bins[0].disabled and storage.labels.bins.text == "3","busy controls display authoritative new count")
	storage.free(); assets.free()
	await process_frame
	print("AREA_MENU PASS" if failures == 0 else "AREA_MENU FAIL")
	quit(failures)
