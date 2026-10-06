extends PanelContainer
# A reusable native picker row. The view owns its current semantic callbacks;
# hidden/rebound rows never retain authority from an earlier snapshot.
var line := Control.new()
var pick := Button.new()
var all := Button.new()
var none := Button.new()
var expand := TextureButton.new()
var subtract := TextureButton.new()
var count := Label.new()
var distance := Label.new()
var frame := NinePatchRect.new()
var icon := TextureRect.new()
var actions := {}
var _unlocked_disabled := {}
var _colors := {}
var _binding_key := []
var _binding_generation := 0
var _pressed_generations := {}

func configure(art, cancel: Callable) -> void:
	custom_minimum_size = Vector2(416,36)
	add_child(line)
	line.custom_minimum_size = Vector2(416,36)
	for key in ["pick","all","none","expand","subtract"]:
		var button: BaseButton = get(key)
		button.button_down.connect(func(): _pressed_generations[key] = _binding_generation)
		button.pressed.connect(func():
			var generation: int = _pressed_generations.get(key,_binding_generation)
			_pressed_generations.erase(key)
			if generation != _binding_generation: return
			var action: Callable = actions.get(key,Callable())
			if action.is_valid(): action.call())
		button.gui_input.connect(cancel)
	for button in [pick,all,none]:
		button.custom_minimum_size.y = 36
		line.add_child(button)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT; pick.clip_text = true
	all.text = "All"; none.text = "None"
	expand.custom_minimum_size = Vector2(16,36); line.add_child(expand)
	subtract.size = Vector2(24,36)
	subtract.texture_normal = art.texture("BUTTON_SUBTRACT")
	subtract.texture_hover = art.texture("BUTTON_SUBTRACT_HOVER")
	subtract.texture_pressed = art.texture("BUTTON_SUBTRACT_PRESSED")
	subtract.texture_disabled = art.texture("BUTTON_SUBTRACT_INVALID")
	line.add_child(subtract)
	for label in [count,distance]:
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE; line.add_child(label)
	distance.name = "Distance"
	frame.name = "ItemFrame"; frame.texture = art.texture("BUTTON_PICTURE_BOX")
	frame.position = Vector2(16,0); frame.size = Vector2(36,36)
	frame.patch_margin_left = 8; frame.patch_margin_right = 8
	frame.patch_margin_top = 12; frame.patch_margin_bottom = 12
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; line.add_child(frame)
	icon.name = "ItemIcon"; icon.position = Vector2(18,2); icon.size = Vector2(32,32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; line.add_child(icon)
	_color(pick,"font_color",_source_color(art.world,15))
	_color(pick,"font_disabled_color",_source_color(art.world,15))
	_color(all,"font_color",_source_color(art.world,14))
	_color(none,"font_color",_source_color(art.world,4))
	for button in [all,none]: _color(button,"font_disabled_color",_source_color(art.world,8))
	_color(count,"font_color",_source_color(art.world,15))
	_color(distance,"font_color",_source_color(art.world,10))
	hide()

func clear() -> void:
	actions.clear(); _binding_key.clear(); _binding_generation += 1; hide()

func apply(view, entry: Dictionary, context: Dictionary) -> Dictionary:
	var row: Dictionary = entry.row
	var index: int = entry.index
	var child: bool = entry.has("item")
	var exact: bool = row.has("candidates")
	var standalone: bool = exact and int(row.get("individual_id",-1)) >= 0
	var group: bool = exact and not child and not standalone
	var item: Dictionary = entry.item if child else (row.candidates[0] if exact and not row.candidates.is_empty() else {})
	var identity := [view.current_filter,view.draft.definition.get("key",""),view.draft.snapshots.get(view.current_filter,{}).get("revision",0),index,int(item.get("id",-1)) if child or standalone else -1,context.chosen]
	if identity != _binding_key:
		_binding_key = identity; _binding_generation += 1
	var selected: Array = context.selected
	var chosen: int = (1 if selected.has(int(item.get("id",-1))) else 0) if child or standalone else context.chosen
	var cost: int = int(item.get("distance",-1)) if child or standalone else context.distance
	var title: String = str(item.name) if child else entry.title
	var column: int = context.column
	var text := title
	if exact:
		if group and chosen == 0 and int(row.count) > 1: text += " [%d]" % int(row.count)
		text = text.left(1).to_upper() + text.substr(1)
		if group and chosen > 0: text += "..."
		var chars: int = 31 if context.single else ((15 if chosen > 0 else 22) if context.windmill or context.fixed else (13 if chosen > 0 else 20))
		if context.terrain: chars = (29 if context.single else (13 if chosen > 0 else 20)) + (0 if context.scrollbar else 2)
		if text.length() > chars: text = text.left(chars-3) + "..."
	else:
		if chosen > 0: text += "  %d/%d" % [chosen,context.limit]
		elif int(row.count) > 1: text += " [%d]" % int(row.count)
	pick.text = text; pick.tooltip_text = "" if exact else title
	pick.position = Vector2(56 if exact else 40,0)
	pick.size = Vector2((248 if context.single else 176) if exact else maxf(32,size.x-136),36)
	_color(pick,"font_color",view._palette(15) if exact else Color("dddddd"))
	_color(pick,"font_disabled_color",view._palette(15) if exact else Color("666666"))
	pick.disabled = (context.limit > 0 and (chosen == 0 and context.full if child or standalone else chosen >= int(row.count) or context.full))
	if not exact: pick.disabled = chosen >= int(row.count) or context.full
	actions = {"pick":view._pick_item.bind(index,int(item.id)) if child or standalone else view._pick.bind(index,chosen+1)}
	var controls := {"index":index,"pick":pick,"items":[]}
	expand.visible = group
	if group:
		var key: String = context.key
		expand.texture_normal = view.art.texture("BUTTON_EXPANDER_OPEN" if view.expanded.get(key,false) else "BUTTON_EXPANDER_CLOSED")
		expand.disabled = false; actions.expand = view._expand.bind(key)
		controls.expand = expand
	var batch: bool = not child and not standalone
	all.visible = batch and (not exact or context.limit > 0 and not context.single)
	none.visible = all.visible
	all.position = Vector2(352+column if exact else size.x-80,0); all.size = Vector2(24,36)
	none.position = Vector2(384+column if exact else size.x-48,0); none.size = Vector2(32,36)
	all.disabled = pick.disabled; none.disabled = chosen == 0
	_color(all,"font_color",view._palette(14) if exact else Color("ffff00"))
	_color(none,"font_color",view._palette(4) if exact else Color("dddddd"))
	for button in [all,none]: _color(button,"font_disabled_color",view._palette(8) if exact else Color("666666"))
	if batch:
		controls.all = all; controls.none = none
		actions.all = view._pick.bind(index,mini(int(row.count),chosen+context.limit-context.total_selected))
		actions.none = view._pick.bind(index,0)
	subtract.visible = exact and not standalone and context.subtract
	if subtract.visible:
		subtract.position = Vector2(320+column if context.terrain else (336 if context.windmill or context.fixed else 320),0)
		subtract.disabled = chosen == 0; controls.subtract = subtract
		actions.subtract = view._unpick_item.bind(index,int(item.id)) if child else view._pick.bind(index,maxi(0,chosen-1))
	count.visible = exact and chosen > 0
	count.text = "%d/%d" % [chosen,context.needed]
	count.position = Vector2(176+column,0); count.size = Vector2(56,36)
	_color(count,"font_color",view._palette(15))
	distance.visible = exact and cost >= 0
	distance.text = "Dist: %d" % cost
	distance.position = Vector2(240+column,0); distance.size = Vector2(104,36)
	_color(distance,"font_color",view._palette(10))
	var source: Array = [int(row.item_type),item.get("appearance",{})]
	icon.texture = view.art.world.construction_item_icon(source[0],source[1]) if not source[1].is_empty() and view.art.world.has_method("construction_item_icon") else null
	icon.visible = exact and icon.texture != null
	frame.visible = icon.visible and context.frame
	if child or standalone: controls.id = int(item.id)
	for key in ["pick","all","none","expand","subtract"]: _unlocked_disabled[key] = get(key).disabled
	set_locked(view.locked)
	show()
	return controls

func set_locked(value: bool) -> void:
	for key in _unlocked_disabled: get(key).disabled = value or _unlocked_disabled[key]

func _color(control: Control, role: String, value: Color) -> void:
	var key := str(control.get_instance_id())+":"+role
	if _colors.get(key) == value: return
	_colors[key] = value
	control.add_theme_color_override(role,value)

func _source_color(world, index: int) -> Color:
	return world.ui_palette_color(index) if world != null and world.has_method("ui_palette_color") else Color.TRANSPARENT
