extends Control
# Native two-panel chooser; catalog identity stays separate from display position.
signal type_selected(id: int)
signal control_selected(key: String)
signal rename_requested(value: String)
signal setting_requested(key: String, value: int)
const Data = preload("res://scripts/area_menu_data.gd")
var art = preload("res://scripts/original_ui.gd").new()
var buttons: Dictionary = {}
var catalog: Dictionary = {}
var prompts: Array[Label] = []
var selected_panel: Control
var heading: Label
var type_label: Label
var type_icon: TextureRect
var owner_label: Label
var owner_portrait: TextureRect
var religion_label: Label
var world
var controls: Dictionary = {}
var name_entry: LineEdit
var settings: Dictionary = {}
var setting_buttons: Array[Button] = []
# Type, semantic field, fixed value (or -1 to toggle), installed icon, position.
const SETTINGS = [
	["Pond","pond_mode",1,"ZONE_PIT",Vector2(222,82)],
	["Pond","pond_mode",2,"ZONE_POND",Vector2(254,82)],
	["Tomb","tomb_citizens",-1,"ZONE_TOMB_CITIZEN_BURIAL",Vector2(222,82)],
	["Tomb","tomb_pets",-1,"ZONE_TOMB_PET_BURIAL",Vector2(254,82)],
	["PlantGathering","gather_trees",-1,"ZONE_GATHER_TREE",Vector2(222,82)],
	["PlantGathering","gather_shrubs",-1,"ZONE_GATHER_SHRUB",Vector2(254,82)],
	["PlantGathering","gather_fallen",-1,"ZONE_GATHER_FALLEN",Vector2(286,82)],
	["ArcheryRange","facing",1,"ZONE_SHOOT_LEFT",Vector2(6,82)],
	["ArcheryRange","facing",2,"ZONE_SHOOT_RIGHT",Vector2(38,82)],
	["ArcheryRange","facing",3,"ZONE_SHOOT_UP",Vector2(70,82)],
	["ArcheryRange","facing",4,"ZONE_SHOOT_DOWN",Vector2(102,82)]
]

func configure(source) -> void:
	world = source
	art.configure(source); theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(324,584)
	for rect in [Rect2(0,0,324,164),Rect2(0,168,324,416)]:
		var frame := Panel.new(); frame.position = rect.position; frame.size = rect.size
		var style := art.make_style("HOVER_RECTANGLE",8)
		style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
		frame.add_theme_stylebox_override("panel",style); add_child(frame)
	caption("Click an existing zone to select it.",Vector2(14,20))
	caption("Select a type below to add a zone.",Vector2(14,44))
	caption("Click an icon to add a new zone.",Vector2(14,188))
	selected_panel = Control.new(); selected_panel.size = Vector2(324,164); add_child(selected_panel)
	var name_frame := Panel.new(); name_frame.position = Vector2(6,10); name_frame.size = Vector2(312,36)
	var inset := StyleBoxFlat.new(); inset.bg_color = Color.TRANSPARENT; inset.border_color = Color("aaaaaa")
	inset.set_border_width_all(2); name_frame.add_theme_stylebox_override("panel",inset)
	name_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; selected_panel.add_child(name_frame)
	heading = Label.new(); heading.position = Vector2(14,10); heading.size = Vector2(272,36)
	heading.add_theme_font_size_override("font_size",12); heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_panel.add_child(heading)
	name_entry = LineEdit.new(); name_entry.position = Vector2(6,10); name_entry.size = Vector2(280,36)
	name_entry.max_length = 128; name_entry.add_theme_font_size_override("font_size",12)
	name_entry.hide(); selected_panel.add_child(name_entry)
	name_entry.text_submitted.connect(func(value): rename_requested.emit(value))
	var type_border := TextureRect.new(); type_border.position = Vector2(6,46); type_border.size = Vector2(32,36)
	type_border.texture = art.texture("ZONE_TYPE_INACTIVE"); selected_panel.add_child(type_border)
	type_icon = TextureRect.new(); type_icon.position = Vector2(6,46); type_icon.size = Vector2(32,36)
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; selected_panel.add_child(type_icon)
	type_label = Label.new(); type_label.position = Vector2(46,46); type_label.size = Vector2(168,36)
	type_label.add_theme_font_size_override("font_size",12); type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_panel.add_child(type_label)
	religion_label = Label.new(); religion_label.position = Vector2(46,70); religion_label.size = Vector2(168,12)
	religion_label.add_theme_font_size_override("font_size",12)
	religion_label.add_theme_color_override("font_color",Color.YELLOW)
	religion_label.clip_text = true; selected_panel.add_child(religion_label)
	owner_portrait = TextureRect.new(); owner_portrait.position = Vector2(6,82); owner_portrait.size = Vector2(32,36)
	owner_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	owner_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	owner_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; selected_panel.add_child(owner_portrait)
	owner_label = Label.new(); owner_label.position = Vector2(54,82); owner_label.size = Vector2(224,36)
	owner_label.clip_text = true
	owner_label.add_theme_font_size_override("font_size",12); owner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_panel.add_child(owner_label)
	for entry in [["rename","UNIT_SHEET_CUSTOMIZE",Vector2(286,10)],
		["previous","ZONE_PREVIOUS",Vector2(6,10)],["next","ZONE_NEXT",Vector2(286,10)],
		["repaint","ZONE_REPAINT",Vector2(222,46)],["suspend","ZONE_SUSPEND",Vector2(254,46)],
		["remove","BUTTON_ZONE_REMOVE",Vector2(286,46)],["owner","ZONE_ASSIGN_UNIT",Vector2(286,82)],
		["location","ZONE_LOCATION_ASSIGN",Vector2(286,118)],
		["location_details","ZONE_LOCATION_DETAILS",Vector2(286,118)],
		["animals","ZONE_PICK_ANIMALS",Vector2(286,82)],
		["squads","ZONE_SQUAD_LIST",Vector2(286,82)]]:
		var key: String = entry[0]
		var button := Button.new(); button.position = entry[2]; button.size = Vector2(32,36)
		for state in ["normal","hover","pressed","disabled","focus"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var icon := TextureRect.new(); icon.name = "Icon"; icon.texture = art.texture(entry[1])
		icon.size = Vector2(32,36); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
		button.pressed.connect(func(): if not button.disabled: control_selected.emit(key))
		selected_panel.add_child(button); controls[key] = button
	for entry in SETTINGS:
		var button := Button.new(); button.position = entry[4]; button.size = Vector2(32,36)
		for state in ["normal","hover","pressed","disabled","focus"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var icon := TextureRect.new(); icon.name = "Icon"; icon.size = Vector2(32,36)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
		button.pressed.connect(func():
			if button.disabled: return
			var key: String = entry[1]
			var value := int(entry[2]) if int(entry[2]) >= 0 else 1-int(settings.get(key,0))
			setting_requested.emit(key,value))
		selected_panel.add_child(button); setting_buttons.append(button)
	var definitions: Array = Data.read().zones
	for index in definitions.size():
		var row: Dictionary = definitions[index]
		var key := str(row.name)
		var button := Button.new(); button.position = Vector2(6+(index/9)*152,214+(index%9)*36)
		button.size = Vector2(152,36); button.tooltip_text = str(row.label)
		for state in ["normal","hover","pressed","disabled","focus"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var border := TextureRect.new(); border.texture = art.texture("ZONE_TYPE_INACTIVE")
		border.size = Vector2(32,36); border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(border)
		var icon := TextureRect.new(); icon.texture = art.texture(str(row.icon))
		icon.size = Vector2(32,36); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
		var label := Label.new(); label.text = str(row.label); label.position = Vector2(40,0)
		label.size = Vector2(112,36); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(label)
		button.pressed.connect(func():
			if catalog.has(key) and not button.disabled: type_selected.emit(int(catalog[key])))
		add_child(button); buttons[key] = button
	display([],false)

func caption(value: String, point: Vector2) -> void:
	var label := Label.new(); label.text = value; label.position = point
	label.add_theme_font_size_override("font_size",12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label)
	prompts.append(label)

func display(rows: Array, editable: bool, area: Dictionary = {}) -> void:
	selected_panel.visible = not area.is_empty()
	for index in 2: prompts[index].visible = area.is_empty()
	if not area.is_empty():
		heading.text = str(area.get("name",""))
		type_label.text = str(area.get("zone_label",""))
		type_label.clip_text = true
		var has_location := int(area.get("location_id",-1)) >= 0
		if has_location and not str(area.get("location_name","")).is_empty(): type_label.text = str(area.location_name)
		religion_label.text = str(area.get("religion","")) if has_location else ""
		type_label.position.y = 46 if religion_label.text.is_empty() else 58
		type_label.size.y = 36 if religion_label.text.is_empty() else 12
		type_label.tooltip_text = type_label.text
		religion_label.tooltip_text = religion_label.text
		type_icon.texture = null
		var type_name := ""
		for row in rows:
			if int(row.id) == int(area.get("zone_type",-1)):
				type_icon.texture = art.texture(str(row.icon))
				type_name = str(row.name)
		if has_location:
			var location_kind := int(area.get("location_kind",0))
			var location_icons := ["","ZONE_TAVERN","ZONE_TEMPLE","ZONE_LIBRARY","ZONE_GUILDHALL","ZONE_HOSPITAL"]
			type_icon.texture = art.texture(location_icons[location_kind]) if location_kind in range(1,6) else null
		owner_label.text = str(area.get("owner_name",""))
		if not str(area.get("owner_profession","")).is_empty(): owner_label.text += ", " + str(area.owner_profession)
		if int(area.get("owner_sex",-1)) in [0,1]: owner_label.text += ", " + ("♀" if int(area.owner_sex) == 0 else "♂")
		owner_label.tooltip_text = owner_label.text
		owner_portrait.texture = null
		if int(area.get("owner_id",-1)) >= 0 and world.has_method("creature_portrait"):
			owner_portrait.texture = world.creature_portrait(int(area.owner_id))
		for key in controls:
			controls[key].disabled = not editable
		controls.owner.visible = bool(area.get("owner_allowed",false))
		controls.location_details.visible = has_location
		controls.location_details.disabled = not editable or int(area.get("location_site_id",-1))<0
		controls.location.position.x = 254 if has_location else 286
		controls.animals.visible = type_name in ["Pen","Pond"]
		controls.squads.visible = type_name in ["Barracks","ArcheryRange"]
		settings = area.get("zone_settings",{}).duplicate(true)
		for index in SETTINGS.size():
			var entry: Array = SETTINGS[index]
			var button := setting_buttons[index]
			button.visible = type_name == str(entry[0])
			var value := int(settings.get(str(entry[1]),-1))
			button.disabled = not editable or value < 0
			var enabled := value == int(entry[2]) if int(entry[2]) >= 0 else value == 1
			button.get_node("Icon").texture = art.texture(str(entry[3])+("_ACTIVE" if enabled else "_INACTIVE"))
			button.get_node("Icon").modulate = Color(0.5,0.5,0.5) if button.disabled else Color.WHITE
		controls.suspend.get_node("Icon").texture = art.texture("ZONE_SUSPEND_INACTIVE" if bool(area.get("active",false)) else "ZONE_SUSPEND")
		for button in controls.values():
			button.get_node("Icon").modulate = Color(0.5,0.5,0.5) if button.disabled else Color.WHITE
		name_entry.editable = editable
	catalog.clear()
	for row in rows: catalog[str(row.name)] = int(row.id)
	for key in buttons:
		# Preserve native slots when a catalog omits a type; never invent its ID.
		buttons[key].visible = catalog.has(key)
		buttons[key].disabled = not editable or not catalog.has(key)

func begin_rename() -> void:
	name_entry.text = heading.text; name_entry.show(); name_entry.grab_focus(); name_entry.select_all()

func set_overlap_navigation(multiple: bool, enabled: bool) -> void:
	for key in ["previous","next"]:
		controls[key].visible = multiple
		controls[key].disabled = not enabled
		controls[key].get_node("Icon").modulate = Color.WHITE if enabled else Color(0.5,0.5,0.5)
	heading.clip_text = true
	heading.position.x = 46 if multiple else 14
	heading.size.x = 208 if multiple else 272
	controls.rename.position.x = 254 if multiple else 286
	name_entry.position.x = 38 if multiple else 6
	name_entry.size.x = 216 if multiple else 280

func cancel_edit() -> bool:
	if not name_entry.visible: return false
	name_entry.hide(); name_entry.release_focus(); return true
