extends Node3D
const Contract = preload("res://scripts/management_contract.gd")
const Action = Contract.ManagementAction
const Status = Contract.ManagementStatus
var world
var pause_guard
var camera: Camera3D
var interaction
var action_service
var ui_host
var hud
var canvas: CanvasLayer
var modal_input := true
var launcher_destination := "Build / construction"
var play_enabled := true
var panel: Control
var menu
var material_view
var footer: PanelContainer
var heading: Label
var message: Label
var shortage_panel: PanelContainer
var shortage_text: Label
var keep_building: CheckBox
var material_options: VBoxContainer
var select_after: Button
var use_closest: Button
var material_picker_right := true
var use_last: Button
var material_strategy := "after"
var last_material: Dictionary = {}
var remove_button: Button
var inspection_tools: HBoxContainer
var orientation: Control
var orientation_panel: PanelContainer
var orientation_hint: Label
var draft = preload("res://scripts/construction_draft.gd").new()
var catalog: Array = []
var pressure_creatures: Array = []
var pressure_first := 0
var pressure_view
var catalog_revision := 0
var catalog_cursors: Array[int] = []
var request_ticket := 0
var draft_generation := 0
var mode := "menu"
var selected_label := ""
var current_z := -1
var corner := Vector3i(-1,-1,-1)
var hover := Vector3i(-1,-1,-1)
var preview_delay := -1.0
var pending_read: Dictionary = {}
var read_delay := 0.0
var material_elapsed := 0.0
var inspect_delay := 1.0
var filter_position := 0
var inspected_id := -1
var inspected_key := ""
var inspected_terrain := Vector3i(-1,-1,-1)
var placed_sites: Dictionary = {}
var outline: MeshInstance3D
var art = preload("res://scripts/original_ui.gd").new()

func _ready() -> void:
	pause_guard = preload("res://scripts/construction_pause_guard.gd").new()
	interaction.add_child(pause_guard)
	pause_guard.configure(world,interaction,action_service)
	tree_exiting.connect(func(): pause_guard.release())
	action_service.session_changed.connect(_session_changed)
	tree_exiting.connect(_detach_draft)
	canvas = CanvasLayer.new(); canvas.layer = 2; add_child(canvas)
	panel = Control.new(); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.add_child(panel); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.hide()
	menu = preload("res://scripts/build_menu_view.gd").new(); panel.add_child(menu); menu.configure(world)
	menu.leaf_selected.connect(choose_definition); menu.close_requested.connect(close_panel)
	material_view = preload("res://scripts/construction_material_view.gd").new()
	panel.add_child(material_view); material_view.configure(world); material_view.hide()
	material_view.group_selected.connect(select_material)
	material_view.item_selected.connect(select_material_item)
	material_view.item_deselected.connect(deselect_material_item)
	material_view.filter_done.connect(finish_filter)
	material_view.cancel_requested.connect(handle_back)
	art.configure(world); panel.theme = art.theme; panel.theme.default_font_size = 12
	footer = PanelContainer.new(); footer.position = Vector2(32,52); footer.custom_minimum_size.x = 448
	footer.add_theme_stylebox_override("panel",placement_panel_style()); panel.add_child(footer)
	var controls := VBoxContainer.new(); footer.add_child(controls)
	heading = Label.new(); heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; heading.custom_minimum_size.x = 416; controls.add_child(heading)
	material_options = VBoxContainer.new(); material_options.add_theme_constant_override("separation",0); controls.add_child(material_options)
	select_after = strategy_button("Select material after placement","after")
	use_closest = strategy_button("Use closest material","closest")
	use_last = strategy_button("Use last material","last")
	keep_building = CheckBox.new(); keep_building.text = "Keep building after placement"; controls.add_child(keep_building)
	keep_building.add_theme_icon_override("checked",art.texture("UNIT_SELECTOR_ASSIGNED"))
	keep_building.add_theme_icon_override("unchecked",art.texture("UNIT_SELECTOR_UNASSIGNED"))
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		keep_building.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	keep_building.add_theme_constant_override("h_separation",16)
	orientation_panel = PanelContainer.new(); panel.add_child(orientation_panel)
	orientation_panel.position = Vector2(610,52); orientation_panel.custom_minimum_size = Vector2(366,154)
	orientation_panel.add_theme_stylebox_override("panel",placement_panel_style())
	var orientation_box := VBoxContainer.new(); orientation_panel.add_child(orientation_box)
	orientation_hint = Label.new(); orientation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orientation_hint.custom_minimum_size.x = 330; orientation_box.add_child(orientation_hint)
	orientation = Control.new(); orientation.custom_minimum_size = Vector2(330,84); orientation_box.add_child(orientation)
	orientation_panel.hide()
	# e4/bed_hover_valid: placement has material strategies and Keep building,
	# without the unfinished inspection actions in its footer.
	inspection_tools = HBoxContainer.new(); controls.add_child(inspection_tools)
	button(inspection_tools,"Inspect building",begin_inspect)
	remove_button = button(inspection_tools,"Remove this building",remove_building)
	button(inspection_tools,"Cancel",handle_back)
	message = Label.new(); message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.custom_minimum_size.x = 420
	message.add_theme_color_override("font_color",Color("ff9900")); controls.add_child(message)
	# These strings are transport/draft diagnostics, not sourced native UI copy.
	# Retain failure state for inspection while native error presentation is unfinished.
	message.hide()
	shortage_panel = PanelContainer.new(); panel.add_child(shortage_panel)
	shortage_panel.position = Vector2(32,52)
	shortage_panel.custom_minimum_size.x = 448
	var shortage_style: StyleBox = art.native_message_panel()
	shortage_style.set_content_margin(SIDE_LEFT,16); shortage_style.set_content_margin(SIDE_RIGHT,24)
	shortage_style.set_content_margin(SIDE_TOP,12); shortage_style.set_content_margin(SIDE_BOTTOM,12)
	shortage_panel.add_theme_stylebox_override("panel",shortage_style)
	shortage_text = Label.new(); shortage_panel.add_child(shortage_text)
	shortage_text.add_theme_constant_override("line_spacing",0)
	# Native shortage visual013136 uses the installed LRED palette entry.
	shortage_text.add_theme_color_override("font_color",world.ui_palette_color(12))
	shortage_panel.hide()
	footer.hide()
	outline = MeshInstance3D.new(); add_child(outline)
	update_buttons()

func button(parent: Node, text: String, callback: Callable) -> Button:
	var control := Button.new(); control.text = text; control.pressed.connect(callback); parent.add_child(control)
	return control

func strategy_button(text: String, strategy: String) -> Button:
	var control := button(material_options,text,set_material_strategy.bind(strategy))
	control.toggle_mode = true; control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.custom_minimum_size.y = 36
	for state in ["normal","hover","pressed","disabled"]:
		var style := art.make_style("BUTTON_CATEGORY_RECTANGLE_ON_SELECTED" if state in ["hover","pressed"] else "BUTTON_CATEGORY_RECTANGLE_ON",8)
		style.set_texture_margin(SIDE_TOP,12); style.set_texture_margin(SIDE_BOTTOM,12)
		style.set_content_margin(SIDE_LEFT,16); style.set_content_margin(SIDE_RIGHT,16)
		style.set_content_margin(SIDE_TOP,0); style.set_content_margin(SIDE_BOTTOM,0)
		if state == "disabled": style.modulate_color = Color(0.5,0.5,0.5)
		control.add_theme_stylebox_override(state,style)
	return control

func supports_closest_material() -> bool:
	return draft.is_connected_track() or draft.is_terrain_construction() or draft.is_magma_building() or draft.is_fixed_recipe() or draft.is_single_item_building() or draft.definition.get("key","") in ["Windmill","Bridge","RoadDirt"]

func material_history_class(key: String) -> String:
	# Native workshop_history_reference: equal material identities do not make
	# fire-safe and ordinary building-material searches interchangeable.
	if draft.FixedRecipes.RECIPES.has(key):
		if not draft.FixedRecipes.RECIPES[key].last: return ""
		return draft.FixedRecipes.RECIPES[key].history_class
	if key.begins_with("Construction:") or key=="Bridge": return "building material"
	if key in ["GrateWall","GrateFloor"]: return "grate"
	return key

func supports_last_material() -> bool:
	if last_material.is_empty() or str(last_material.get("name","")).is_empty(): return false
	var previous := str(last_material.get("definition",""))
	var current := str(draft.definition.get("key",""))
	if material_history_class(previous)!=material_history_class(current): return false
	if draft.is_fixed_recipe():
		return draft.FixedRecipes.RECIPES[draft.definition.key].last
	if draft.is_single_item_building():
		# single_item_options_reference also captures GrateWall -> GrateFloor.
		return previous==current or (previous in ["GrateWall","GrateFloor"] and current in ["GrateWall","GrateFloor"])
	# Pinned df.item_type: BAR, BLOCKS, BOULDER, WOOD. A remembered furnishing
	# cannot be offered as terrain/Bridge material after switching recipes.
	return (draft.is_connected_track() or draft.is_terrain_construction() or draft.definition.get("key","")=="Bridge") and int(last_material.get("item_type",-1)) in [0,2,4,5]

func set_material_strategy(value: String) -> void:
	if mode != "place" or request_ticket != 0: return
	if value == "after" or (value == "closest" and supports_closest_material()) or (value == "last" and supports_last_material()):
		material_strategy = value
	update_buttons()

func apply_last_material(filter_index: int) -> void:
	if draft.is_fixed_recipe():
		# Native checks every input before entering manual or automatic selection.
		for filter in draft.filters:
			var index := int(filter.index)
			var page: Dictionary = draft.snapshots.get(index,{})
			if page.is_empty(): load_materials(index); return
			if int(page.get("next_cursor",0))>0: load_materials(index,int(page.next_cursor)); return
		if not magma_shortages().is_empty(): return
	if material_strategy == "closest":
		apply_closest_material(filter_index); return
	if material_strategy != "last" or mode != "materials": return
	# Native pending-only overlaps still require a picker row click with Last set,
	# even when the previous construction used one available material group.
	if not draft.variable_count(filter_index) and draft.needed(filter_index) == 0: return
	var snapshot: Dictionary = draft.snapshots[filter_index]
	for index in snapshot.rows.size():
		var row: Dictionary = snapshot.rows[index]
		if draft.identity(row) != draft.identity(last_material): continue
		if draft.is_connected_track() or draft.is_terrain_construction() or draft.definition.get("key","")=="Bridge":
			select_material(filter_index,index,mini(int(row.count),draft.needed(filter_index))); return
		if int(row.count) >= draft.needed(filter_index):
			select_material(filter_index,index,draft.needed(filter_index)); return
		break
	if int(snapshot.next_cursor) > 0:
		load_materials(filter_index,int(snapshot.next_cursor)); return
	# Keep this read result available for an explicit replacement choice. Never
	# substitute a different group or replay a refused mutation automatically.
	if not draft.is_connected_track() and not draft.is_terrain_construction() and not draft.is_single_item_building() and not draft.is_fixed_recipe() and draft.definition.get("key","")!="Bridge": material_strategy = "after"
	# No native source establishes explanatory copy for this fallback.
	material_view.status.text = ""
	update_buttons()

func apply_closest_material(filter_index: int) -> void:
	if mode != "materials" or not supports_closest_material(): return
	if draft.is_magma_building() or draft.is_fixed_recipe():
		apply_magma_closest(); return
	var snapshot: Dictionary = draft.snapshots[filter_index]
	# Native Closest fills groups in displayed order, not a global item-distance sort.
	# Collect the immutable snapshot before committing any local selection.
	if int(snapshot.next_cursor) > 0:
		load_materials(filter_index,int(snapshot.next_cursor)); return
	for index in snapshot.rows.size():
		var remaining: int = draft.needed(filter_index) - draft.selected_count(filter_index)
		if remaining <= 0: break
		var row: Dictionary = snapshot.rows[index]
		if draft.is_connected_track() and not row.has("candidates"): return
		if not draft.select_group(filter_index,index,mini(remaining,int(row.count))): return
	material_view.refresh()
	if draft.covered(filter_index): finish_filter(filter_index)

func magma_materials_complete() -> bool:
	for filter in draft.filters:
		var snapshot: Dictionary = draft.snapshots.get(int(filter.index),{})
		if snapshot.is_empty() or int(snapshot.get("next_cursor",0)) > 0: return false
	return not draft.filters.is_empty()

func magma_shortages() -> Array[int]:
	var missing: Array[int] = []
	if not magma_materials_complete(): return missing
	for filter in draft.filters:
		var available := 0
		for row in draft.snapshots[int(filter.index)].rows: available += int(row.count)
		if available < draft.needed(int(filter.index)): missing.append(int(filter.index))
	return missing

func apply_magma_closest() -> void:
	# Native checks both forge inputs before reporting all missing requirements.
	# Collect complete pinned lists before selecting or submitting any construction.
	for filter in draft.filters:
		var index := int(filter.index)
		var snapshot: Dictionary = draft.snapshots.get(index,{})
		if snapshot.is_empty(): load_materials(index); return
		if int(snapshot.next_cursor)>0: load_materials(index,int(snapshot.next_cursor)); return
	if not magma_shortages().is_empty(): return
	if draft.definition.get("key","")=="Construction:ReinforcedWall":
		apply_reinforced_closest(); return
	for filter in draft.filters:
		var index := int(filter.index)
		var rows: Array = draft.snapshots[index].rows
		for row_index in rows.size():
			var remaining: int = (10 if draft.variable_count(index) else draft.needed(index))-draft.selected_count(index)
			if remaining<=0: break
			# Native variable weapons take one from each displayed group, up to ten.
			var count := mini(1 if draft.variable_count(index) else remaining,int(rows[row_index].count))
			if not draft.select_group(index,row_index,count): return
	if draft.can_place():
		# Native weapon_multigroup_reference: Closest keeps the explicit Done step.
		for position in draft.filters.size():
			var index := int(draft.filters[position].index)
			if draft.variable_count(index):
				filter_position=position;material_view.show_filter(draft,index,selected_label);return
		place()

func apply_reinforced_closest() -> void:
	# Native reinforced cursor captures: the group cursor continues across
	# recipe stages, wrapping only when it exceeds the new stage's row count.
	var cursor := 0
	for position in draft.filters.size():
		var index := int(draft.filters[position].index)
		var rows: Array = draft.snapshots[index].rows
		var indices: Array[int] = []
		for i in rows.size():
			if int(draft.available_row(index,rows[i]).count)>0: indices.append(i)
		if cursor>=indices.size(): cursor=0
		while not draft.covered(index) and cursor<indices.size():
			var row_index := indices[cursor]
			var row: Dictionary = draft.available_row(index,rows[row_index])
			var count := mini(draft.needed(index)-draft.selected_count(index),int(row.count))
			if not draft.select_group(index,row_index,count): return
			cursor+=1
		if not draft.covered(index):
			filter_position=position;material_view.show_filter(draft,index,selected_label);return
	if draft.can_place(): place()

func remember_material(request: Dictionary) -> void:
	if not str(request.get("definition","")).begins_with("Construction:") and request.get("definition","")!="Bridge" and not draft.is_single_item_building() and not draft.is_fixed_recipe(): return
	if draft.is_fixed_recipe() and not draft.FixedRecipes.RECIPES[draft.definition.key].last:
		# Native retains old material bytes but clears their validity after a
		# multi-input building. Reopening a compatible recipe must not revive Last.
		last_material.clear(); return
	last_material.clear()
	var selected: Array = request.get("selections",[])
	var choice: Dictionary = {}
	if request.get("definition","")=="Bridge" or draft.is_fixed_recipe():
		# Native Bridge history follows its first assigned item, unlike the
		# final tile of an area construction. Both assign IDs in ascending order.
		var first_id := -1
		for selection in selected:
			for id in selection.get("item_ids",[]):
				if first_id<0 or int(id)<first_id:first_id=int(id);choice=selection
	elif str(request.get("definition","")) == "Construction:Track" or draft.is_terrain_construction():
		# Native assigns exact items in ascending ID order; the final new job
		# supplies Last, even when manual group selection happened in reverse order.
		var final_id := -1
		for selection in selected:
			for id in selection.get("item_ids",[]):
				if int(id) > final_id: final_id = int(id); choice = selection
	if choice.is_empty() and selected.size() == 1:
		choice = selected[0]
	if choice.is_empty():
		if material_strategy != "closest": material_strategy = "after"
		return # A selection without exact identities cannot establish mixed history.
	for row in draft.snapshots.get(int(choice.filter),{}).get("rows",[]):
		if draft.identity(row) == draft.identity(choice):
			var name := str(row.get("last_name",""))
			if name.is_empty(): return # Missing history copy is not a display-name fallback.
			# Remember the semantic preference, never item IDs, counts or revisions.
			for field in ["item_type","item_subtype","mat_type","mat_index"]: last_material[field] = row[field]
			last_material.name=name;last_material.definition=request.get("definition","")
			return
	if material_strategy != "closest": material_strategy = "after"

func placement_panel_style() -> StyleBox:
	var style: StyleBox = art.compact_panel()
	if style is StyleBoxTexture and art.texture("INTERFACE_BACKGROUND") != null:
		var image: Image = style.texture.get_image()
		var color: Color = art.texture("INTERFACE_BACKGROUND").get_image().get_pixel(0,0)
		var x_margin := int(style.get_texture_margin(SIDE_LEFT)); var y_margin := int(style.get_texture_margin(SIDE_TOP))
		for y in range(y_margin,image.get_height()-y_margin):
			for x in range(x_margin,image.get_width()-x_margin): image.set_pixel(x,y,color)
		style.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,16)
	style.set_content_margin(SIDE_TOP,24)
	return style

func open_panel() -> void:
	if not play_enabled: return
	if panel.visible: close_panel(); return
	if not ui_host.activate(self): return
	panel.show(); current_z = int(world.get_top_z())
	cancel_site(); catalog.clear(); pressure_creatures.clear(); catalog_cursors.clear(); catalog_revision = 0
	menu.clear_catalog(); menu.open(); mode = "menu"
	send({"action":Action.Catalog,"cursor":0})

func set_play_enabled(value: bool) -> void:
	play_enabled = value
	if not value: close_panel()

func close_panel() -> void:
	panel.hide(); cancel_site(); pressure_creatures.clear(); ui_host.release(self)

func cancel_site() -> void:
	if pause_guard != null: pause_guard.release()
	if shortage_panel != null: shortage_panel.hide()
	_detach_draft(); draft.clear(); corner = Vector3i(-1,-1,-1); hover = corner
	preview_delay = -1; pending_read.clear(); inspected_id = -1; inspected_key = ""; inspected_terrain = corner
	material_view.hide(); draw_outline(); update_buttons()

func handle_back() -> void:
	if mode == "menu": menu.back(); return
	if mode == "materials" and (draft.is_connected_track() or draft.is_terrain_construction() or draft.is_single_item_building() or draft.is_fixed_recipe() or draft.definition.get("key","")=="Bridge" or (material_strategy == "closest" and supports_closest_material())):
		# Native manual, Last and shortage pickers all cancel to the map.
		close_panel(); return
	if draft.definition.get("key","") == "Trap:PressurePlate":
		close_panel(); return
	if mode in ["materials","checking","placing"] or corner.z >= 0 or draft.origin.z >= 0:
		var definition: Dictionary = draft.definition.duplicate(true)
		cancel_site()
		if not definition.is_empty(): draft.choose(definition)
		mode = "place"; footer.show(); update_prompt(); return
	cancel_site(); mode = "menu"; footer.hide(); menu.open()

func closest_material_shortage() -> bool:
	if mode != "materials" or not supports_closest_material(): return false
	if material_strategy != "closest" and not ((draft.is_terrain_construction() or draft.definition.get("key","")=="Bridge") and material_strategy == "after") and not ((draft.is_single_item_building() or draft.is_fixed_recipe()) and material_strategy in ["after","last"]): return false
	if draft.is_magma_building() or draft.is_fixed_recipe(): return not magma_shortages().is_empty()
	if filter_position >= draft.filters.size(): return false
	var filter_index := int(draft.filters[filter_position].index)
	var snapshot: Dictionary = draft.snapshots.get(filter_index,{})
	if snapshot.is_empty() or int(snapshot.get("next_cursor",0)) > 0: return false
	var available := 0
	for row in snapshot.rows: available += int(row.count)
	return available < draft.needed(filter_index)

func update_material_shortage() -> void:
	shortage_panel.hide()
	if not closest_material_shortage(): return
	var filter_index := int(draft.filters[filter_position].index)
	var available := 0
	for row in draft.snapshots[filter_index].rows: available += int(row.count)
	if draft.is_fixed_recipe():
		var needs: Array[String] = []
		var access: Array[String] = []
		for index in magma_shortages():
			var recipe: Dictionary = draft.FixedRecipes.RECIPES[draft.definition.key]
			var native: Array = recipe.needs[index]
			var supplied := 0
			for row in draft.snapshots[index].rows: supplied += int(row.count)
			if not recipe.get("omit_needs",false) and (supplied == 0 or not recipe.get("needs_only_if_empty",false)):
				needs.append("Needs "+native[0])
				if not str(native[1]).is_empty(): needs.append(native[1])
			access.append("No access to %d %s" % [draft.needed(index),recipe.access_plural[index]] if recipe.has("access_plural") and draft.needed(index)>1 else "No access to "+native[0])
		shortage_text.text="\n".join(needs+access)
	elif draft.is_magma_building():
		# Verbatim native_closest lines in magma_placement.json, in native order.
		var needs: Array[String] = []
		var access: Array[String] = []
		for index in magma_shortages():
			var anvil: bool = draft.definition.key=="Workshop:MagmaForge" and index==0
			var noun := "magma-safe anvil" if anvil else "magma-safe building material non-economic item"
			needs.append("Needs "+noun)
			needs.append(" - make at a workshop first" if anvil else " - mine rock or chop trees")
			access.append("No access to "+noun)
		shortage_text.text="\n".join(needs+access)
	elif draft.is_connected_track() or draft.is_terrain_construction() or draft.definition.get("key","")=="Bridge":
		# Terrain zero/partial/manual/Closest: stairs_placement.terrain_shortage_reference.
		# Native shortage012338/empty012634, not transport error prose.
		shortage_text.text = "" if available > 0 or draft.definition.get("key","")=="Construction:Stairs" else "Needs building material non-economic item\n - mine rock or chop trees\n"
		var required := draft.needed(filter_index)
		shortage_text.text += "No access to building material non-economic item" if required == 1 else "No access to %d building material non-economic items" % required
	elif draft.definition.get("key","") == "Windmill":
		# windmill.native_closest: identical for zero and two available logs.
		shortage_text.text = "Needs 4 logs\n - chop down trees\nNo access to 4 logs"
	else:
		# furniture_material_copy native_closest_shortage/common_closest_shortage: Chair's native
		# requirement is "throne" even when the candidate is a wooden chair.
		# single_item_options_reference: identical manual/Closest shortages.
		var noun: String = {"Bed":"bed","Chair":"throne","Table":"table","Coffin":"coffin","Cabinet":"cabinet","Box":"empty box","Statue":"statue","Slab":"slab", "TractionBench":"traction bench","Bookcase":"bookcase","DisplayFurniture":"display object","OfferingPlace":"offering placement","Instrument":"item","Door":"door","Hatch":"hatch cover","Cage":"cage","Chain":"chain","Armorstand":"armor stand","Weaponrack":"weapon rack","GrateWall":"grate","GrateFloor":"grate","Floodgate":"floodgate","NestBox":"nest box","Hive":"hive","Workshop:Quern":"quern","AnimalTrap":"empty animal trap","WindowGlass":"window","Trap:PressurePlate":"mechanisms"}[draft.definition.key]
		shortage_text.text = "Needs " + noun + ("\n" if draft.definition.key=="Instrument" else "\n - make at a workshop first\n") + "No access to " + noun
	material_view.hide(); footer.hide(); orientation_panel.hide()
	shortage_panel.reset_size(); shortage_panel.show()

func choose_definition(key: String) -> void:
	if request_ticket != 0: return
	for row in catalog:
		if str(row.key) != key: continue
		cancel_site()
		if not draft.choose(row): return
		pressure_first = 0
		selected_label = menu_label(menu.entries,key)
		if material_strategy == "last" and not supports_last_material(): material_strategy = "after"
		if material_strategy == "closest" and not supports_closest_material(): material_strategy = "after"
		menu.hide(); mode = "place"; footer.show(); rebuild_orientation(); update_prompt()
		return

func menu_label(rows: Array, key: String) -> String:
	for row in rows:
		if row.get("catalog_key","") == key: return str(row.label)
		if row.has("children"):
			var found := menu_label(row.children,key)
			if not found.is_empty(): return found
	return ""

func rebuild_orientation() -> void:
	for child in orientation.get_children(): orientation.remove_child(child); child.queue_free()
	pressure_view = null
	var track_stop: bool = draft.definition.get("key", "") == "Trap:TrackStop"
	var pressure: bool = draft.definition.get("key", "") == "Trap:PressurePlate"
	orientation_hint.visible = not pressure
	orientation_panel.custom_minimum_size = Vector2(400,0) if pressure else Vector2(366,154)
	orientation.custom_minimum_size.x = 384 if pressure else 330
	var style := placement_panel_style()
	if pressure:
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,8)
		style.set_content_margin(SIDE_TOP,12)
	orientation_panel.add_theme_stylebox_override("panel",style)
	orientation_panel.visible = int(draft.definition.get("orientations",1)) != 1 or track_stop or pressure
	if not orientation_panel.visible: return
	if pressure:
		orientation_panel.position = Vector2(576,48)
		pressure_view = preload("res://scripts/construction_pressure.gd").new()
		orientation.add_child(pressure_view)
		pressure_view.configure(art,draft.pressure_plate,pressure_creatures,pressure_first,request_ticket == 0 and mode == "place")
		pressure_view.choice.connect(set_pressure_option)
		pressure_view.scrolled.connect(func(value: int): pressure_first = value)
		orientation.custom_minimum_size.y = pressure_view.custom_minimum_size.y
		orientation_panel.set_deferred("size",Vector2.ZERO)
		return
	if track_stop:
		orientation_hint.text = "Set the friction and auto-dump direction.\nAuto-dumping is not required."
		for option in [[0,"BUILDING_PLACEMENT_TRACK_STOP_NO_DUMPING",Vector2(32,36)], [1,"BUILDING_PLACEMENT_N",Vector2(32,0)], [2,"BUILDING_PLACEMENT_E",Vector2(64,36)], [3,"BUILDING_PLACEMENT_S",Vector2(32,72)], [4,"BUILDING_PLACEMENT_W",Vector2(0,36)]]:
			track_stop_button("dump_direction",option[0],option[1],option[2],draft.track_dump_direction == option[0])
		var friction_tokens := ["LOWEST","LOW","MIDDLE","HIGH","HIGHEST"]
		var frictions := [10,50,500,10000,50000]
		for index in 5:
			track_stop_button("friction",frictions[index],"BUILDING_PLACEMENT_TRACK_STOP_FRICTION_"+friction_tokens[index],Vector2(136+index*40,36),draft.track_friction == frictions[index])
		orientation.custom_minimum_size.y = 108
		return
	orientation.custom_minimum_size.y = 84
	# Pinned semantic direction enums; no native widget state.
	var labels: Array = ["N","E","S","W"]
	var family := str(draft.definition.get("family",""))
	if family == "Bridge": labels = ["W","E","N","S","Retracting"]
	elif family == "SiegeEngine": labels = ["N","NE","E","SE","S","SW","W","NW"]
	elif family in ["WaterWheel","AxleHorizontal"]: labels = ["WE","NS"]
	elif family == "ScrewPump": labels = ["S","W","N","E"] # Native flow arrows; enums name the input side.
	elif family == "Rollers": labels = ["S","W","N","E"] # FromNorth flows south; quickfort roller_data.
	orientation_hint.text = ""
	if family == "Bridge": orientation_hint.text = "Set the draw direction below.\nThen select the corners of the bridge."
	elif family == "SiegeEngine" and selected_label in ["Ballista","Catapult"]:
		orientation_hint.text = "A %s's orientation cannot be changed once it is placed." % selected_label.to_lower()
	elif family == "Rollers": orientation_hint.text = "Minecart rollers can vary in length. Set the orientation and speed below."
	elif family == "ScrewPump": orientation_hint.text = "Set the liquid flow direction below.\nWater flows from the adjacent input tile\nand from the tile below the input tile."
	elif family == "WaterWheel": orientation_hint.text = "Water wheels are 1x3 or 3x1.\nThe long side should align\nwith the water's flow."
	elif family == "AxleHorizontal": orientation_hint.text = "Horizontal axles can vary in length.\nSet the orientation below."
	elif family == "SiegeEngine" and selected_label == "Bolt thrower": orientation_hint.text = "A bolt thrower can be freely turned by the\noperator.  Choose a resting orientation."
	var cross := {"N":Vector2(32,0),"E":Vector2(64,24),"S":Vector2(32,48),"W":Vector2(0,24),"Retracting":Vector2(144,24)}
	if family in ["ScrewPump","Rollers"]: cross["S"] = Vector2(32,36)
	for index in labels.size():
		if int(draft.definition.orientations) & (1 << index):
			var token := "BUILDING_PLACEMENT_" + str(labels[index])
			if family == "Bridge": token = "BUILDING_PLACEMENT_BRIDGE_" + ("RETRACT" if index == 4 else str(labels[index]))
			elif family == "ScrewPump": token = "BUILDING_PLACEMENT_SCREW_PUMP_" + ["N","E","S","W"][index] # Asset tokens also name the input side.
			var control := TextureButton.new(); control.texture_normal = art.texture("BUILDING_PLACEMENT_INACTIVE_BUTTON")
			control.texture_pressed = art.texture("BUILDING_PLACEMENT_ACTIVE_BUTTON"); control.texture_hover = control.texture_pressed
			control.toggle_mode = true; control.button_pressed = index == (4 if draft.retracting else draft.direction)
			control.position = cross.get(labels[index],Vector2(index*32,0)) if family not in ["SiegeEngine","WaterWheel","AxleHorizontal"] else Vector2(index*32,0)
			if family in ["WaterWheel","AxleHorizontal"]: control.position = Vector2((1-index)*32,0)
			control.tooltip_text = labels[index]; control.pressed.connect(set_orientation.bind(index)); orientation.add_child(control)
			var picture := TextureRect.new(); picture.texture = art.texture(token); picture.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(picture)
	if family == "Rollers":
		for speed in 5:
			var control := TextureButton.new(); control.position = Vector2(136+speed*40,24)
			control.texture_normal = art.texture("BUILDING_PLACEMENT_INACTIVE_BUTTON")
			control.texture_pressed = art.texture("BUILDING_PLACEMENT_ACTIVE_BUTTON"); control.texture_hover = control.texture_pressed
			control.toggle_mode = true; control.button_pressed = draft.roller_speed == (speed+1)*10000
			control.set_meta("roller_speed", (speed+1)*10000)
			control.pressed.connect(set_roller_speed.bind((speed+1)*10000))
			orientation.add_child(control)
			var picture := TextureRect.new(); picture.texture = art.texture("BUILDING_PLACEMENT_ROLLERS_SPEED_%d" % (speed+1)); picture.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(picture)

func set_roller_speed(value: int) -> void:
	if request_ticket != 0 or mode != "place" or draft.definition.get("family", "") != "Rollers": return
	if value < 10000 or value > 50000 or value % 10000 != 0: return
	_detach_draft(); draft.roller_speed = value; draft.invalidate()
	corner = Vector3i(-1,-1,-1); hover = corner; draft.origin = corner
	rebuild_orientation(); draw_outline(); update_prompt()

func set_pressure_option(kind: String, value: int) -> void:
	if request_ticket != 0 or mode != "place" or draft.definition.get("key","") != "Trap:PressurePlate": return
	var changed := false
	if kind in ["units","water","magma","citizens","resets","track"]: changed = draft.set_pressure_flag(kind,value != 0)
	elif kind in ["water_depth","magma_depth"]: changed = draft.choose_pressure_fluid(kind.trim_suffix("_depth"),value)
	elif kind in ["track_min","track_max"]: changed = draft.adjust_pressure_cart(kind.trim_prefix("track_"),value)
	elif kind == "creature": changed = draft.choose_pressure_creature(value)
	if not changed: return
	_detach_draft(); corner = Vector3i(-1,-1,-1); hover = corner; draft.origin = corner
	rebuild_orientation(); draw_outline(); update_prompt()

func track_stop_button(kind: String, value: int, token: String, at: Vector2, selected: bool) -> void:
	var control := TextureButton.new(); control.position = at
	control.texture_normal = art.texture("BUILDING_PLACEMENT_INACTIVE_BUTTON")
	control.texture_pressed = art.texture("BUILDING_PLACEMENT_ACTIVE_BUTTON"); control.texture_hover = control.texture_pressed
	control.toggle_mode = true; control.button_pressed = selected
	control.set_meta("track_option",kind); control.set_meta("track_value",value)
	control.pressed.connect(set_track_stop.bind(kind,value)); orientation.add_child(control)
	var picture := TextureRect.new(); picture.texture = art.texture(token); picture.mouse_filter = Control.MOUSE_FILTER_IGNORE; control.add_child(picture)

func set_track_stop(kind: String, value: int) -> void:
	if request_ticket != 0 or mode != "place" or draft.definition.get("key", "") != "Trap:TrackStop": return
	if kind == "friction":
		if value not in [10,50,500,10000,50000]: return
	elif kind == "dump_direction":
		if value < 0 or value > 4: return
	else: return
	_detach_draft()
	if kind == "friction": draft.track_friction = value
	else: draft.track_dump_direction = value
	draft.invalidate(); corner = Vector3i(-1,-1,-1); hover = corner; draft.origin = corner
	rebuild_orientation(); draw_outline(); update_prompt()

func set_orientation(index: int) -> void:
	if request_ticket != 0 or mode != "place": return
	_detach_draft(); corner = Vector3i(-1,-1,-1); hover = corner
	var retract := index == 4 and str(draft.definition.family) == "Bridge"
	if draft.orient(0 if retract else index,retract):
		draft.origin = corner; rebuild_orientation(); draw_outline(); update_prompt()

func update_prompt() -> void:
	heading.text = "Click a tile to be a corner of the %s." % selected_label if int(draft.definition.get("area_mode",1)) > 1 else "Click a tile to place the %s." % selected_label
	# Native single_item_options_reference: placement uses the full building name.
	if draft.is_single_item_building():
		var name: String = {"Bed":"Bed","Chair":"Seat","Table":"Table","Coffin":"Burial Receptacle","Cabinet":"Cabinet","Box":"Container","Statue":"Statue","Slab":"Slab","TractionBench":"Traction Bench","Bookcase":"Bookcase","DisplayFurniture":"Display Furniture","OfferingPlace":"Offering Place","Instrument":"Instrument","Door":"Door","Hatch":"Floor Hatch","Cage":"Cage","Chain":"Restraint","Armorstand":"Armor Stand","Weaponrack":"Weapon Rack","GrateWall":"Wall Grate","GrateFloor":"Floor Grate","Floodgate":"Floodgate","NestBox":"Nest Box","Hive":"Hive","Workshop:Quern":"Quern","AnimalTrap":"Animal Trap","WindowGlass":"Glass Window","Trap:PressurePlate":"Pressure Plate"}[draft.definition.key]
		heading.text = "Click a tile to place the %s." % name
	if draft.definition.get("family","") == "Rollers": heading.text = "Click a tile to be one end of the Rollers."
	if draft.definition.get("key","") == "RoadDirt": heading.text = "Click a tile to be a corner of the Dirt Road."
	if draft.is_fixed_recipe(): heading.text = draft.FixedRecipes.RECIPES[draft.definition.key].placement
	message.text = ""; update_buttons()

func send(request: Dictionary) -> void:
	if not play_enabled or not panel.visible or request_ticket != 0: return
	var generation := draft_generation
	request_ticket = action_service.submit("construction",request,func(ticket,result,sent):
		if generation == draft_generation and ticket == request_ticket and panel.visible:
			request_ticket = 0; _receive_result(result,sent))
	message.text = "Waiting for Dwarf Fortress" if request_ticket != 0 else "Management connection unavailable"
	update_buttons()

func preview() -> void:
	if draft.definition.is_empty() or draft.origin.z < 0: return
	# A stair anchor is an unfinished gesture until another elevation is chosen.
	# Do not let a delayed one-level preview rejection discard that anchor.
	if mode == "place" and int(draft.definition.get("area_mode",0)) == 4 and draft.dimensions.z < 2: return
	if draft.is_connected_track() and (corner.z < 0 or draft.track_destination.z < 0 or draft.track_destination == draft.origin): return
	send(draft.request(Action.Preview))

func target_tile(tile: Vector3i, commit: bool = false) -> void:
	if mode != "place" or draft.definition.is_empty() or tile.z < 0: return
	# These native rectangle gestures validate the first tile before anchoring.
	if commit and draft.definition.get("key","") in ["FarmPlot","Bridge","RoadDirt","RoadPaved","Construction:ReinforcedWall"] and corner.z<0:
		_detach_draft();pending_read.clear()
		if not draft.set_site(tile,tile): return
		hover=tile;preview_delay=-1;mode="anchor";draw_outline();preview();return
	var had_corner := corner.z >= 0
	if commit and int(draft.definition.area_mode) > 1 and not had_corner: corner = tile
	_detach_draft(); pending_read.clear()
	if draft.is_connected_track() and not had_corner:
		draft.invalidate(); draft.origin = tile; draft.track_destination = Vector3i(-1,-1,-1)
		hover = tile; preview_delay = -1; draw_outline(); return
	if not draft.set_site(corner if corner.z >= 0 else tile,tile):
		preview_delay = -1; hover = tile; message.text = draft.error; draw_outline(); return
	hover = tile; draw_outline()
	if commit and (int(draft.definition.area_mode) == 1 or had_corner):
		mode = "checking"; preview_delay = -1; preview()
	else: preview_delay = 0.15

func load_materials(filter_index: int, cursor: int = 0) -> void:
	if not draft.preview_valid or request_ticket != 0: return
	mode = "materials"
	material_view.set_busy(true); material_view.set_locked(true)
	var generation := draft_generation
	pause_guard.acquire(func(ok:bool):
		if generation != draft_generation or not panel.visible: return
		if not ok:
			cancel_site();mode="place";footer.show();return
		send(draft.material_request(filter_index,cursor)))

func select_material(filter_index: int, row_index: int, count: int) -> void:
	if mode != "materials" or request_ticket != 0 or not pending_read.is_empty(): return
	if not draft.select_group(filter_index,row_index,count):
		material_view.status.text = draft.error; return
	material_view.refresh()
	if not draft.variable_count(filter_index) and draft.covered(filter_index): finish_filter(filter_index)

func deselect_material_item(filter_index: int, row_index: int, item_id: int) -> void:
	if mode != "materials" or request_ticket != 0 or not pending_read.is_empty(): return
	if draft.deselect_item(filter_index,row_index,item_id): material_view.refresh()

func select_material_item(filter_index: int, row_index: int, item_id: int) -> void:
	if mode != "materials" or request_ticket != 0 or not pending_read.is_empty(): return
	if not draft.select_item(filter_index,row_index,item_id): return
	material_view.refresh()
	if not draft.variable_count(filter_index) and draft.covered(filter_index): finish_filter(filter_index)

func finish_filter(filter_index: int) -> void:
	if mode != "materials" or request_ticket != 0 or not pending_read.is_empty() or not draft.covered(filter_index): return
	if filter_position >= draft.filters.size() or int(draft.filters[filter_position].index) != filter_index: return
	filter_position += 1
	if filter_position == draft.filters.size(): place()
	else:
		var next_index := int(draft.filters[filter_position].index)
		material_view.show_filter(draft,next_index,selected_label)
		# Multi-input admission already pinned all recipe pages. Re-reading page
		# zero would invalidate the draft as a duplicate, losing earlier choices.
		if draft.snapshots.has(next_index) and int(draft.snapshots[next_index].next_cursor)==0:
			apply_last_material(next_index)
		else: load_materials(next_index)

func place() -> void:
	if request_ticket != 0 or not draft.can_place(): return
	var request: Dictionary = draft.place_request()
	mode = "placing"; pending_read.clear(); send(request)
	if pause_guard != null: pause_guard.mutation_ticket = request_ticket
	draft.preview_valid = false

func begin_inspect() -> void:
	cancel_site(); menu.hide(); footer.show(); orientation_panel.hide(); mode = "inspect"
	heading.text = "Click a building to inspect construction"; message.text = ""

func remove_building() -> void:
	if inspected_id >= 0: send({"action":Action.Remove,"building_id":inspected_id,"definition":inspected_key})
	elif inspected_terrain.z >= 0: send({"action":Action.RemoveConstruction,"origin":inspected_terrain})

func _receive_result(state: Dictionary, request: Dictionary) -> void:
	message.text = str(state.get("message",""))
	var data: Dictionary = state.get("construction",{})
	# Non-atomic area Place may report confirmed work even on a refusal. Preserve
	# that evidence; never replay or imply that a rejected batch did nothing.
	if int(request.action) == Action.Place and data.has("placed"):
		var id := int(data.get("first_building",-1))
		if int(data.placed) > 0 and id >= 0 and str(request.get("definition","")) != "Construction:Track": placed_sites[id] = {"origin":request.origin,"width":request.width,"height":request.height,"depth":request.get("depth",1)}
		message.text += "\nPlaced %d; skipped %d" % [int(data.placed),int(data.get("skipped",0))]
		draw_outline()
	if int(state.get("status",Status.Rejected)) != Status.Ok:
		if int(request.action) == Action.Preview and mode == "place" and corner == hover: corner = Vector3i(-1,-1,-1)
		draft.invalidate(); pending_read.clear(); material_view.hide(); footer.show()
		if mode != "menu": mode = "place" if not draft.definition.is_empty() else "inspect"
		draw_outline(); update_buttons(); return
	match int(request.action):
		Action.Catalog:
			var cursor := int(request.get("cursor",0)); var revision := int(data.get("list_revision",0))
			if catalog_cursors.has(cursor) or (cursor > 0 and revision != catalog_revision):
				catalog.clear(); pressure_creatures.clear(); menu.clear_catalog(); message.text = "Construction catalog changed; reopen to refresh"; return
			catalog_revision = revision; catalog_cursors.append(cursor)
			if cursor == 0: pressure_creatures = data.get("pressure_creatures",[]).duplicate(true)
			for row in state.get("catalog",[]):
				for old in catalog:
					if old.key == row.key:
						catalog.clear(); pressure_creatures.clear(); menu.clear_catalog(); message.text = "Construction catalog repeated a key"; return
				catalog.append(row)
			var next := int(state.get("next_cursor",0))
			if next > 0: send({"action":Action.Catalog,"cursor":next,"expected_list_revision":catalog_revision})
			else: menu.set_catalog(catalog)
		Action.Preview:
			if not draft.accept_preview(state):
				message.text = draft.error
				if mode == "place" and corner == hover: corner = Vector3i(-1,-1,-1)
				if mode == "anchor": mode = "place"
			elif mode == "anchor":
				corner=request.origin;mode="place";preview_delay=-1
			elif mode == "checking":
				material_elapsed = 0; filter_position = 0
				if draft.filters.is_empty(): place()
				else:
					footer.hide(); material_view.show_filter(draft,int(draft.filters[0].index),selected_label)
					load_materials(int(draft.filters[0].index))
			if mode == "checking": mode = "place"
			draw_outline()
		Action.ConstructionMaterials:
			var result: String = draft.accept_materials(state,request,true)
			material_view.status.text = str(state.get("message",""))
			# The bridge retains this read-only builder; polling does not restart it.
			# A quarter-second delay accumulated after each finished stage/page.
			if result == "pending": pending_read = request.duplicate(true); read_delay = 0.05
			elif result == "failed":
				material_view.hide(); footer.show(); mode = "place"; message.text = draft.error
			material_view.refresh()
			if result == "ready":
				# Native exposes one scrollable list. Transport pages are collected
				# under the pinned revision, without an invented paging control.
				var next := int(draft.snapshots[int(request.filter)].next_cursor)
				if next > 0: load_materials(int(request.filter),next)
				else: apply_last_material(int(request.filter))
			update_material_shortage()
		Action.Place:
			if int(data.get("placed",0)) > 0: remember_material(request)
			var text := message.text
			var definition: Dictionary = draft.definition.duplicate(true)
			var facing := int(draft.direction); var retract := bool(draft.retracting)
			cancel_site()
			if keep_building.button_pressed:
				draft.choose(definition)
				# Native keep_direction_reference resets raised/retracting bridges
				# to west-facing placement after each successful build.
				if definition.get("key","") != "Bridge": draft.orient(facing,retract)
				mode = "place"; footer.show(); rebuild_orientation(); update_prompt(); message.text = text
			else:
				message.text = text; close_panel() # e4 wall_placed_mixed_materials: unchecked returns to the map.
		Action.Inspect, Action.InspectAtTile:
			inspected_id = int(state.get("building_id",-1)); inspected_key = str(data.get("building_key",""))
			inspected_terrain = request.get("origin",Vector3i(-1,-1,-1)) if state.get("terrain_construction",false) else Vector3i(-1,-1,-1)
			message.text += "\nStage %d / %d; %d jobs%s" % [int(state.get("build_stage",-1)),int(state.get("max_stage",-1)),int(state.get("jobs",0)),"; removing" if state.get("removing",false) else ""]
		Action.Remove, Action.RemoveConstruction:
			placed_sites.erase(inspected_id); inspected_id = -1; inspected_terrain = Vector3i(-1,-1,-1); draw_outline()
	update_buttons()

func update_buttons() -> void:
	if remove_button == null: return
	# native_placement_hover_correction: Bridge and Pressure Plate retain the
	# left placement pane alongside their right option pane.
	material_options.visible = mode != "inspect"
	inspection_tools.visible = mode == "inspect"
	select_after.disabled = request_ticket != 0 or mode != "place"
	use_closest.disabled = select_after.disabled or not supports_closest_material()
	use_closest.set_pressed_no_signal(material_strategy == "closest")
	use_last.visible = supports_last_material()
	use_last.disabled = select_after.disabled or last_material.is_empty()
	# Native terrain_last_reference.before renders the remembered noun with an
	# initial capital even though the semantic group description is lowercase.
	var last_name := str(last_material.get("name",""))
	if not last_name.is_empty():last_name=last_name.left(1).to_upper()+last_name.substr(1)
	use_last.text = "Use last material" + ("\n " + last_name if not last_material.is_empty() else "")
	select_after.set_pressed_no_signal(material_strategy == "after")
	use_last.set_pressed_no_signal(material_strategy == "last")
	keep_building.disabled = mode != "place" or request_ticket != 0
	remove_button.disabled = request_ticket != 0 or (inspected_id < 0 and inspected_terrain.z < 0)
	for control in orientation.get_children():
		if control is BaseButton: control.disabled = request_ticket != 0 or mode != "place"
		elif control.has_method("set_locked"): control.set_locked(request_ticket != 0 or mode != "place")
	for control in orientation.get_children():
		if control.get_meta("unsupported",false): control.disabled = true
	orientation_panel.visible = mode == "place" and (int(draft.definition.get("orientations",1)) != 1 or draft.definition.get("key", "") in ["Trap:TrackStop","Trap:PressurePlate"])
	var material_busy: bool = request_ticket != 0 or not pending_read.is_empty() or mode == "placing" or (pause_guard != null and pause_guard.sequence != 0 and mode == "materials")
	material_view.set_busy(mode in ["materials","placing"] and material_busy)
	material_view.set_locked(material_busy)

func _process(delta: float) -> void:
	if pause_guard != null and mode not in ["materials","placing"]: pause_guard.release()
	if not play_enabled or not panel.visible: return
	var view := get_viewport().get_visible_rect().size
	var anchor := Vector2(view.x * 0.48,view.y - 40)
	if hud != null:
		canvas.scale = Vector2.ONE * hud.ui_scale_value()
		view /= hud.ui_scale_value()
		var launcher: Rect2 = hud.navigation[launcher_destination].get_global_rect()
		anchor = Vector2(launcher.get_center().x,launcher.position.y-2)
	menu.layout(view,anchor); material_view.resize_to_view(view)
	layout_placement(view)
	var z := int(world.get_top_z())
	if z != current_z:
		current_z = z
		if not (mode == "place" and corner.z >= 0 and (int(draft.definition.get("area_mode",0)) == 4 or draft.is_connected_track())):
			if mode != "menu": handle_back()
		draw_outline()
	if preview_delay >= 0:
		preview_delay -= delta
		if preview_delay < 0 and mode == "place" and request_ticket == 0: preview()
	if mode == "inspect" and inspected_id >= 0 and request_ticket == 0:
		inspect_delay -= delta
		if inspect_delay <= 0:
			inspect_delay = 1.0; send({"action":Action.Inspect,"building_id":inspected_id})
	if mode == "materials":
		material_elapsed += delta
		if material_elapsed > 120 and not pending_read.is_empty():
			pending_read.clear(); draft.invalidate(); material_view.hide(); footer.show(); mode = "place"
			message.text = "Material lookup timed out; choose the site again"
		elif not pending_read.is_empty() and request_ticket == 0:
			read_delay -= delta
			if read_delay <= 0:
				var request := pending_read.duplicate(true); pending_read.clear(); send(request)

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible or not ui_host.allows_panel_input(self): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		handle_back(); get_viewport().set_input_as_handled(); return
	if mode not in ["place","inspect"]: return
	if event is InputEventMouseMotion and mode == "place":
		var tile: Vector3i = world.pick_tile(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position),world.get_top_z())
		if tile != hover: target_tile(tile)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tile: Vector3i = world.pick_tile(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position),world.get_top_z())
		if tile.z >= 0:
			if mode == "place" and (draft.is_single_item_building() or draft.is_fixed_recipe()):
				# Native picker_side_reference: moving within the same tile does
				# not move the picker. Use our projected tile, not native UI state.
				var center := camera.unproject_position(Vector3(tile.x+0.5,tile.z+float(world.floor_height()),tile.y+0.5))
				material_picker_right = center.x <= get_viewport().get_visible_rect().size.x/2.0
			if mode == "inspect" and request_ticket == 0: send({"action":Action.InspectAtTile,"origin":tile})
			elif mode == "place": target_tile(tile,true)
		get_viewport().set_input_as_handled()

func layout_placement(view: Vector2) -> void:
	var top := 52.0
	var right := view.x - 24.0
	if hud != null:
		top = maxf(top,hud.status_panel.get_rect().end.y)
		if hud.minimap.visible: right = minf(right,hud.minimap_panel.position.x-8)
	footer.position = Vector2(32,top)
	# Native Bridge and furniture pickers sit left of the minimap sidebar.
	material_view.position.x = maxf(32,right-16-material_view.size.x) if draft.definition.get("key","")=="Bridge" or draft.is_single_item_building() or draft.is_fixed_recipe() or draft.is_terrain_construction() else 32
	if (draft.is_single_item_building() or draft.is_fixed_recipe()) and not material_picker_right: material_view.position.x = 32
	material_view.position.y = top
	material_view.size.y = maxf(100,view.y-top-40)
	orientation_panel.position = Vector2(576,maxf(48,top-4)) if draft.definition.get("key","") == "Trap:PressurePlate" else Vector2(610,top)
	if orientation_panel.position.x + orientation_panel.size.x > right:
		orientation_panel.position = Vector2(32,footer.get_rect().end.y+8)

func visible_outline_sites() -> Array:
	var sites: Array = placed_sites.values().duplicate(true)
	if draft.is_connected_track() and not draft.track_path.is_empty():
		for tile in draft.track_path: sites.append({"origin":tile,"width":1,"height":1,"depth":1})
	elif draft.origin.z >= 0:
		sites.append({"origin":draft.origin,"width":draft.dimensions.x,"height":draft.dimensions.y,"depth":draft.dimensions.z})
	var z := int(world.get_top_z()); var visible_sites: Array = []
	for site in sites:
		if z >= int(site.origin.z) and z < int(site.origin.z) + int(site.get("depth",1)): visible_sites.append(site)
	return visible_sites

func draw_outline() -> void:
	if outline == null: return
	var visible_sites := visible_outline_sites()
	var z := int(world.get_top_z())
	if visible_sites.is_empty(): outline.mesh = null; return
	var mesh := ImmediateMesh.new(); var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(0.8,0.65,0.15); material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for site in visible_sites:
		var p: Vector3i = site.origin; var y := float(z) + float(world.floor_height()) + 0.02
		var corners: Array[Vector3] = [Vector3(p.x,y,p.y),Vector3(p.x+site.width,y,p.y),Vector3(p.x+site.width,y,p.y+site.height),Vector3(p.x,y,p.y+site.height)]
		for i in 4: mesh.surface_add_vertex(corners[i]); mesh.surface_add_vertex(corners[(i+1)%4])
	mesh.surface_end(); outline.mesh = mesh

func _detach_draft() -> void:
	draft_generation += 1
	if action_service != null: action_service.detach(request_ticket)
	request_ticket = 0

func _session_changed() -> void:
	if pause_guard != null: pause_guard.abandon()
	last_material.clear(); material_strategy = "after"
	cancel_site(); catalog.clear(); pressure_creatures.clear(); catalog_cursors.clear(); menu.clear_catalog(); placed_sites.clear(); draw_outline()
	mode = "menu"; menu.open(); footer.show(); message.text = "World changed; reopen to refresh"

func cancel_gesture() -> void:
	if mode in ["place","checking","anchor"]: handle_back()

func allows_elevation_input() -> bool:
	return panel.visible and mode == "place"
