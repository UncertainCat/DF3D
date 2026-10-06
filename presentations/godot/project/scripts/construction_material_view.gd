extends PanelContainer
# Native e4 material panel. The controller owns tickets and filter progression.
signal group_selected(filter_index: int, row_index: int, count: int)
signal item_selected(filter_index: int, row_index: int, item_id: int)
signal item_deselected(filter_index: int, row_index: int, item_id: int)
signal filter_done(filter_index: int)
signal cancel_requested
var draft
var current_filter := 0
var building_label := ""
var locked := false
var busy_indicator: Control
var heading: Label
var amount: Label
var search: LineEdit
var rows: Control
var done: Button
var status: Label
var scroll: ScrollContainer
var row_controls: Array = []
var expanded: Dictionary = {}
var expansion_revision := 0
var _laying_out_rows := false
var _rows_need_scrollbar := false
var _row_styles: Array[StyleBox] = []
const MaterialRow = preload("res://scripts/construction_material_row.gd")
var _row_pool: Array = []
var _entries: Array = []
var _group_context: Dictionary = {}
var _first_visible := -1
var _visible_count := -1
var _binding_rows := false
var art = preload("res://scripts/original_ui.gd").new()
var bands = preload("res://scripts/build_menu_view.gd").new()

func configure(source) -> void:
	art.configure(source)
	theme = art.theme
	theme.default_font_size = 12
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bands.art = art
	var panel_style: StyleBox = art.compact_panel()
	if panel_style is StyleBoxTexture and art.texture("INTERFACE_BACKGROUND") != null:
		var pixels: Image = panel_style.texture.get_image()
		var color: Color = art.texture("INTERFACE_BACKGROUND").get_image().get_pixel(0,0)
		var left := int(panel_style.get_texture_margin(SIDE_LEFT))
		var top := int(panel_style.get_texture_margin(SIDE_TOP))
		for y in range(top,pixels.get_height() - top):
			for x in range(left,pixels.get_width() - left): pixels.set_pixel(x,y,color)
		panel_style.texture = ImageTexture.create_from_image(pixels)
	panel_style.set_content_margin(SIDE_LEFT,16); panel_style.set_content_margin(SIDE_RIGHT,16)
	panel_style.set_content_margin(SIDE_TOP,32); panel_style.set_content_margin(SIDE_BOTTOM,16)
	add_theme_stylebox_override("panel",panel_style)
	position = Vector2(32,52)
	custom_minimum_size.x = 480
	var box := VBoxContainer.new(); add_child(box)
	var header := HBoxContainer.new(); box.add_child(header)
	heading = Label.new(); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(heading)
	busy_indicator=preload("res://scripts/busy_indicator.gd").new()
	busy_indicator.color=_palette(14)
	header.add_child(busy_indicator);busy_indicator.hide()
	done = Button.new(); done.text = "Done"; done.pressed.connect(_done); header.add_child(done)
	# Native weapon picker Done uses the green confirmation frame.
	done.custom_minimum_size = Vector2(48,24)
	for state in ["normal","hover","pressed","disabled"]:
		var style := art.make_style("HORIZONTAL_OPTION_INACTIVE" if state=="disabled" else "HORIZONTAL_OPTION_CONFIRM",8)
		for side in [SIDE_TOP,SIDE_BOTTOM]:
			style.set_texture_margin(side,12); style.set_content_margin(side,0)
		for side in [SIDE_LEFT,SIDE_RIGHT]: style.set_content_margin(side,8)
		done.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color"]: done.add_theme_color_override(state,Color.WHITE)
	amount = Label.new(); box.add_child(amount)
	search = LineEdit.new(); search.placeholder_text = "..."; search.text_changed.connect(func(_text): _render_rows()); box.add_child(search)
	var filter_style := StyleBoxTexture.new(); filter_style.texture = art.texture("BUTTON_FILTER")
	filter_style.set_texture_margin(SIDE_LEFT,8); filter_style.set_texture_margin(SIDE_RIGHT,32)
	filter_style.set_texture_margin(SIDE_TOP,12); filter_style.set_texture_margin(SIDE_BOTTOM,12)
	filter_style.set_content_margin(SIDE_LEFT,12); filter_style.set_content_margin(SIDE_RIGHT,36)
	filter_style.set_content_margin(SIDE_TOP,0); filter_style.set_content_margin(SIDE_BOTTOM,0)
	search.custom_minimum_size.y = 36
	search.context_menu_enabled = false
	search.gui_input.connect(_gui_input)
	search.add_theme_stylebox_override("normal",filter_style); search.add_theme_stylebox_override("focus",filter_style)
	scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.resized.connect(_scroll_resized)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; box.add_child(scroll)
	rows = Control.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# One shared button style per picker, not five new resources per button.
	var row_theme := Theme.new()
	var empty := StyleBoxEmpty.new()
	for state in ["normal","hover","pressed","disabled","focus"]: row_theme.set_stylebox(state,"Button",empty)
	row_theme.set_color("font_color","Button",Color("dddddd"))
	row_theme.set_color("font_hover_color","Button",_palette(15))
	row_theme.set_color("font_disabled_color","Button",Color("666666"))
	rows.theme = row_theme
	for light in [true,false]:
		var stripe: StyleBox = bands._row_style(light)
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: stripe.set_content_margin(side,0)
		_row_styles.append(stripe)
	scroll.add_child(rows)
	# Allocate the ordinary viewport's widgets once during UI setup. Larger
	# windows grow this pool by visible rows, never by inventory size.
	_ensure_row_pool(24)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value): _render_visible_rows())
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size.x = 430; box.add_child(status)
	# Controller diagnostics have no native copy/layout provenance. They must not
	# become player-facing status text; semantic receipts retain the failure details.
	status.hide()
	resize_to_view(Vector2(1200,800))
	tree_exiting.connect(func(): bands.free())
	visibility_changed.connect(func():
		if not visible:
			_entries.clear(); _group_context.clear(); row_controls.clear()
			for widget in _row_pool: widget.clear())

func resize_to_view(view: Vector2) -> void:
	var width := 472 if draft != null and (draft.definition.get("key","")=="Bridge" or draft.is_single_item_building() or draft.is_fixed_recipe() or draft.is_terrain_construction()) else 480
	custom_minimum_size = Vector2(width,maxf(180,view.y - 92))
	size = custom_minimum_size

func show_filter(value, filter_index: int, label: String) -> void:
	draft = value; current_filter = filter_index; building_label = label
	expanded.clear(); expansion_revision = 0
	search.clear(); scroll.scroll_vertical = 0
	show(); refresh()

func refresh() -> void:
	if draft == null: return
	heading.text = "Select materials for the " + building_label
	# Verbatim native picker-initial heading, including the recipe template and period.
	if draft.is_connected_track(): heading.text = "Select materials for the Track (NSEW)."
	elif draft.is_terrain_construction():
		# Full native headings: stairs_placement.terrain_picker_reference.
		heading.text = {"Construction:ReinforcedWall":"Select materials for the Reinforced Wall.","Construction:Wall":"Select materials for the Wall.","Construction:Floor":"Select materials for the Floor.","Construction:Ramp":"Select materials for the Ramp.","Construction:Fortification":"Select materials for the Fortification.","Construction:Stairs":"Select materials for the Up/Down Stair."}[draft.definition.key]
	elif draft.is_fixed_recipe(): heading.text = draft.FixedRecipes.RECIPES[draft.definition.key].heading
	elif draft.is_single_item_building():
		# Full native headings: furniture_material_copy.common_exact_picker.
		heading.text = {
			"Bed":"Select materials for the Bed.", "Chair":"Select materials for the Seat.",
			"Table":"Select materials for the Table.", "Coffin":"Select materials for the Burial Receptacle.",
			"Cabinet":"Select materials for the Cabinet.", "Box":"Select materials for the Container.",
			"Statue":"Select materials for the Statue.", "Slab":"Select materials for the Slab.",
			# additional_single_item_reference: full native headings, not menu labels.
			"TractionBench":"Select materials for the Traction Bench.", "Bookcase":"Select materials for the Bookcase.",
			"DisplayFurniture":"Select materials for the Display Furniture.", "OfferingPlace":"Select materials for the Offering Place.",
			"Instrument":"Select materials for the Instrument.", "Door":"Select materials for the Door.",
			"Hatch":"Select materials for the Floor Hatch.", "Cage":"Select materials for the Cage.",
			"Chain":"Select materials for the Restraint.", "Armorstand":"Select materials for the Armor Stand.",
			"Weaponrack":"Select materials for the Weapon Rack.", "GrateWall":"Select materials for the Wall Grate.",
			"GrateFloor":"Select materials for the Floor Grate.", "Floodgate":"Select materials for the Floodgate.",
			"NestBox":"Select materials for the Nest Box.", "Hive":"Select materials for the Hive.",
			"Workshop:Quern":"Select materials for the Quern.", "AnimalTrap":"Select materials for the Animal Trap.",
			"WindowGlass":"Select materials for the Glass Window.", "Trap:PressurePlate":"Select materials for the Pressure Plate."
		}[draft.definition.key]
	elif draft.definition.get("key","") == "Bridge": heading.text = "Select materials for the Bridge."
	elif draft.definition.get("key","") == "Windmill": heading.text = "Select materials for the Windmill."
	elif draft.is_magma_building():
		# Full native headings captured in magma_placement.native_closest.
		heading.text = {
			"Workshop:MagmaForge":"Select materials for the Magma Forge.",
			"Furnace:MagmaSmelter":"Select materials for the Magma Smelter.",
			"Furnace:MagmaGlassFurnace":"Select materials for the Magma Glass Furnace.",
			"Furnace:MagmaKiln":"Select materials for the Magma Kiln."
		}[draft.definition.key]
	var variable: bool = draft.variable_count(current_filter)
	amount.text = "Amount needed: 1 to 10" if variable else "Amount needed: %d" % draft.needed(current_filter)
	amount.visible = variable or draft.needed(current_filter) > 0
	if draft.definition.get("key","")=="Construction:ReinforcedWall":
		amount.visible = draft.snapshots.get(current_filter,{}).get("rows",[]).any(func(row):return int(draft.available_row(current_filter,row).count)>0)
	done.visible = variable
	done.disabled = locked or not draft.covered(current_filter)
	search.editable = not locked
	var snapshot: Dictionary = draft.snapshots.get(current_filter,{})
	var revision := int(snapshot.get("revision",0))
	if revision != expansion_revision:
		expanded.clear(); expansion_revision = revision
	_render_rows()

func set_busy(value: bool) -> void:
	busy_indicator.visible=value

func set_locked(value: bool) -> void:
	if locked == value: return
	locked = value
	if draft == null: return
	done.disabled = locked or not draft.covered(current_filter)
	search.editable = not locked
	for widget in _row_pool: widget.set_locked(locked)

func _ensure_row_pool(count: int) -> void:
	while _row_pool.size() < count:
		var widget = MaterialRow.new()
		widget.configure(art,_gui_input)
		rows.add_child(widget)
		_row_pool.append(widget)

func _render_rows() -> void:
	_entries.clear(); _group_context.clear(); row_controls.clear()
	if draft != null:
		var entries: Array = draft.snapshots.get(current_filter,{}).get("rows",[])
		for index in entries.size():
			var row: Dictionary = draft.available_row(current_filter,entries[index])
			if row.has("candidates") and int(row.count) == 0: continue
			var title := str(row.get("caption",""))
			if title.is_empty(): title = str(row.get("name",""))
			if not search.text.is_empty() and not title.to_lower().contains(search.text.to_lower()): continue
			var group := row_controls.size()
			row_controls.append({"index":index,"items":[]})
			_entries.append({"index":index,"group":group,"row":row,"title":title})
			if row.has("candidates") and int(row.get("individual_id",-1)) < 0 and expanded.get(str(draft.identity(row)),false):
				for item in row.candidates:
					_entries.append({"index":index,"group":group,"row":row,"title":title,"item":item})
	rows.custom_minimum_size = Vector2(416,_entries.size()*36)
	_rows_need_scrollbar = _entries.size()*36 > (scroll.size.y if scroll.size.y>0 else 584)
	_render_visible_rows(true)

func _render_visible_rows(force := false) -> void:
	if _binding_rows or rows == null: return
	_binding_rows = true
	var count := mini(_entries.size(),ceili(maxf(36,scroll.size.y)/36)+1)
	var first := clampi(scroll.scroll_vertical/36,0,maxi(0,_entries.size()-1))
	if not force and first == _first_visible and count == _visible_count:
		_binding_rows = false; return
	_first_visible = first; _visible_count = count
	_ensure_row_pool(count)
	for control in row_controls:
		var index: int = control.index
		control.clear(); control.index = index; control.items = []
	var common := {}
	if draft != null:
		_laying_out_rows = true
		common = {"single":_single_picker(),"terrain":draft.is_terrain_construction(),"fixed":draft.is_fixed_recipe(),"windmill":draft.definition.get("key","")=="Windmill",
			"scrollbar":_rows_need_scrollbar,"column":_column_offset(),"limit":_limit(),"needed":draft.needed(current_filter),"total_selected":draft.selected_count(current_filter)}
		common.full = common.total_selected >= common.limit
		common.subtract = not common.single and (common.windmill or draft.definition.get("key","")=="Bridge" or common.terrain or common.fixed)
		common.frame = draft.definition.get("key","") in ["Windmill","Bridge"] or _magma_single() or draft.is_single_item_building() or common.fixed or common.terrain
		_laying_out_rows = false
	for slot in _row_pool.size():
		var widget = _row_pool[slot]
		var logical := first+slot
		if slot >= count or logical >= _entries.size() or draft == null:
			widget.clear(); continue
		var entry: Dictionary = _entries[logical]
		if not _group_context.has(entry.index):
			_group_context[entry.index] = {"chosen":draft.group_count(current_filter,entry.row),"selected":draft.selected_ids(current_filter,entry.row),"distance":draft.group_distance(current_filter,entry.row),"key":str(draft.identity(entry.row))}
		var context: Dictionary = common.duplicate()
		context.merge(_group_context[entry.index])
		widget.position = Vector2(0,logical*36); widget.size = Vector2(maxf(416,rows.size.x),36)
		widget.add_theme_stylebox_override("panel",_row_styles[logical%2])
		var controls: Dictionary = widget.apply(self,entry,context)
		var group: Dictionary = row_controls[entry.group]
		if entry.has("item"): group.items.append(controls)
		else:
			group.merge(controls,true)
			if controls.has("id"): group.items.append({"id":controls.id,"pick":controls.pick})
	_binding_rows = false

# Native DF53.16 material picker: material_candidates.json individual_picker_capture
# and picker_art_capture. Coordinates are relative to the expander's left edge;
# source rows use 8x12 cells and three-cell row height. Candidate names are sourced.
func _palette(index: int) -> Color:
	if not art.world.has_method("ui_palette_color"): return Color.TRANSPARENT
	return art.world.ui_palette_color(index)

func _magma_single() -> bool:
	return draft.is_magma_building() and _limit()==1

func _single_picker() -> bool:
	return draft.variable_count(current_filter) or draft.is_single_item_building() or (draft.is_fixed_recipe() and _limit()==1) or (draft.is_terrain_construction() and _limit()==1) or _magma_single() or (draft.definition.get("key","")=="Bridge" and _limit()==1)

func _scroll_resized() -> void:
	if draft == null: return
	var scrollbar: bool = _entries.size()*36 > scroll.size.y
	if draft.is_terrain_construction() and scrollbar != _rows_need_scrollbar:
		_rows_need_scrollbar = scrollbar
	_render_visible_rows(true)

func _terrain_scrollbar() -> bool:
	if _laying_out_rows: return _rows_need_scrollbar
	var count := 0
	for row in draft.snapshots.get(current_filter,{}).get("rows",[]):
		var title := str(row.get("caption",""))
		if title.is_empty(): title = str(row.get("name",""))
		if not search.text.is_empty() and not title.to_lower().contains(search.text.to_lower()): continue
		count += 1
		if expanded.get(str(draft.identity(row)),false): count += row.get("candidates",[]).size()
	return count*36 > (scroll.size.y if scroll.size.y>0 else 584)

func _column_offset() -> int:
	if draft.is_terrain_construction(): return (64 if _single_picker() else 0)+(0 if _terrain_scrollbar() else 16)
	if draft.is_fixed_recipe(): return 80 if _single_picker() else 16
	if _magma_single() or draft.is_single_item_building(): return 80
	if draft.definition.get("key","")=="Bridge" and _limit()==1: return 64
	return 16 if draft.definition.get("key","")=="Windmill" else 0

func _unpick_item(row_index: int, item_id: int) -> void:
	if not locked: item_deselected.emit(current_filter,row_index,item_id)

func _expand(key: String) -> void:
	if locked: return
	expanded[key] = not expanded.get(key,false)
	_render_rows()

func _pick_item(row_index: int, item_id: int) -> void:
	if _limit() == 0: _done(); return
	if not locked: item_selected.emit(current_filter,row_index,item_id)

func _limit() -> int:
	return 10 if draft.variable_count(current_filter) else draft.needed(current_filter)

func _pick(row_index: int, count: int) -> void:
	# Native pending-only overlap still asks for a row click, without reserving it.
	if _limit() == 0: _done(); return
	if not locked: group_selected.emit(current_filter,row_index,count)

func _done() -> void:
	if not locked and draft != null and draft.covered(current_filter): filter_done.emit(current_filter)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_requested.emit(); accept_event()
