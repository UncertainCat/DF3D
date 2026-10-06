extends SceneTree
const Menu = preload("res://scripts/build_menu_view.gd")
var failures := 0
var picked: Array[String] = []
var closed := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func labels(rows: Array) -> Array:
	var result: Array = []
	for row in rows: result.append(row.label)
	return result

func definitions(rows: Array, result: Array) -> void:
	for row in rows:
		check(str(row.evidence).begins_with("build/evidence/native/e2/build_menu"), "menu row retains native evidence: " + row.label)
		if row.has("children"): definitions(row.children, result)
		else: result.append({"key":row.catalog_key, "supported":row.catalog_key != "Windmill", "reason":"Windmill placement rule not captured" if row.catalog_key == "Windmill" else ""})

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var assets := Df3dWorld.new(); root.add_child(assets)
	check(assets.load_assets(OS.get_environment("DF3D_DF_PATH")), "installed assets load")
	var menu := Menu.new(); root.add_child(menu); menu.configure(assets)
	menu.leaf_selected.connect(func(key): picked.append(key))
	menu.close_requested.connect(func(): closed += 1)
	check(labels(menu.entries) == ["Workshops", "Furniture", "Doors/hatches", "Constructions", "Machines/fluids", "Cages/restraints", "Traps", "Military", "Trade depot"], "native top-level order")
	var expected := {
		"Workshops":["Clothing and leather", "Farming", "Furnaces", "Ashery", "Bowyer", "Carpenter", "Crafts", "Jeweler", "Magma forge", "Mechanic", "Metalsmith", "Screw Press", "Siege", "Soap Maker's Workshop", "Stoneworker"],
		"Furniture":["Bed", "Chair", "Table", "Chest", "Cabinet", "Burial", "Slab", "Statue", "Traction bench", "Bookcase", "Display", "Offering place", "Instrument"],
		"Doors/hatches":["Door", "Hatch"],
		"Constructions":["Wall", "Reinforced Wall", "Floor", "Ramp", "Stairs", "Bridge", "Paved road", "Dirt road", "Fortification", "Wall grate", "Floor grate", "Vertical bars", "Floor bars", "Glass window", "Gem window", "Support", "Track", "Track stop"],
		"Machines/fluids":["Lever", "Well", "Floodgate", "Screw pump", "Water wheel", "Windmill", "Gear assembly", "Horizontal axle", "Vertical axle", "Millstone", "Rollers"],
		"Cages/restraints":["Rope/chain", "Cage", "Animal trap"],
		"Traps":["Pressure plate", "Stone-fall", "Weapon", "Cage", "Upright weapon/spike"],
		"Military":["Archery target", "Weapon rack", "Armor stand", "Ballista", "Catapult", "Bolt thrower"]}
	for row in menu.entries:
		if row.has("children"): check(labels(row.children) == expected[row.label], "native leaf order: " + row.label)
	var workshop: Array = menu.entries[0].children
	check(labels(workshop[0].children) == ["Leather", "Loom", "Clothes", "Dyer"], "clothing submenu order")
	check(labels(workshop[1].children) == ["Farm plot", "Still", "Butcher", "Tanner", "Fishery", "Kitchen", "Farmer", "Quern", "Vermin Catcher's Shop", "Nest box", "Hive"], "farming submenu order")
	check(labels(workshop[2].children) == ["Glass furnace", "Kiln", "Magma glass furnace", "Magma kiln", "Magma smelter", "Smelter", "Wood furnace"], "furnaces submenu order")
	var rows: Array = []; definitions(menu.entries, rows)
	check(rows.size() == 93, "every native leaf has a semantic target")
	check(menu.row_controls[0][8].disabled, "missing catalog leaf stays disabled")
	menu.activate(0, 8); check(picked.is_empty(), "missing leaf never dispatches")
	menu.set_catalog(rows)
	check(menu.row_count == 7 and menu.row_controls[0][7].position.y == 0 and menu.row_controls[0][7].position.x > menu.row_controls[0][6].position.x, "native seven-row column-major wrap")
	check(menu.row_controls[0][7].position.x == 176, "native root column width at 1200x800")
	check(menu.row_controls[0][0].get_node("Icon").texture == assets.ui_texture("BUILDING_ICON_WORKSHOPS"), "icons resolve through installed art")
	check(menu.row_controls[0][0].get_node("Frame").texture == assets.ui_texture("BUTTON_PICTURE_BOX"), "icon frame uses installed native art")
	check(menu.row_controls[0][0].get_theme_stylebox("normal").texture == assets.ui_texture("BUTTON_RECTANGLE_LIGHT"), "row hatching uses installed native art")
	for code in ["SCREW_PRESS", "SOAP_MAKER"]:
		check(assets.ui_texture("CUSTOM_WORKSHOP_LIST_ICON:" + code) != null, "raw-defined workshop list icon resolves: " + code)
	menu.activate(0, 0); menu.activate(1, 1)
	check(menu.levels().size() == 3 and menu.path == [0, 1], "workshop subgroup cascades")
	check(menu.compact_levels[0], "oldest ancestor compacts at native narrow cascade")
	menu.activate(2, 0); check(picked == ["FarmPlot"], "supported native leaf emits its stable catalog key")
	menu.activate(0, 4)
	check(menu.path == [4] and menu.levels().size() == 2, "sibling selection replaces descendants")
	check(menu.row_controls[1][5].disabled and menu.row_controls[1][5].tooltip_text == "Windmill", "unsupported option keeps adapter diagnostics out of visible copy")
	menu.activate(1, 5); check(picked.size() == 1, "unsupported leaf never dispatches")
	var right := InputEventMouseButton.new(); right.button_index = MOUSE_BUTTON_RIGHT; right.pressed = true
	menu.row_controls[1][0].gui_input.emit(right)
	check(menu.path.is_empty(), "right-click on a row backs out one level")
	menu.back(); check(closed == 1, "back at root requests closure")
	menu.activate(0, 0); menu.activate(1, 1)
	menu.layout(Vector2(1920, 900), Vector2(960, 860))
	check(menu.row_count == 8 and not menu.compact_levels[0], "tall/wide layout restores ancestor captions")
	check(menu.position.y + menu.size.y == 860, "menu remains anchored directly above toolbar")
	menu.clear_catalog()
	check(menu.path.is_empty() and menu.row_controls[0][8].disabled, "session reset removes old hierarchy and targets")
	menu.free(); assets.free()
	await process_frame
	print("BUILD_MENU_PASS" if failures == 0 else "BUILD_MENU_FAIL")
	quit(failures)
