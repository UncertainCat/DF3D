extends Control
# Native build hierarchy only. The construction controller owns commands/drafts.
signal leaf_selected(key: String)
signal close_requested
const DATA = "res://panels/build_menu.json"
const ROW_HEIGHT := 36.0
const ICON_WIDTH := 32.0
const SEPARATOR := 8.0
var entries: Array = []
var catalog: Dictionary = {}
var path: Array[int] = []
var row_count := 7
var level_widths: Array[float] = []
var compact_levels: Array[bool] = []
var row_controls: Array = []
var viewport_size := Vector2(1200, 800)
var anchor := Vector2(580, 760)
var art = preload("res://scripts/original_ui.gd").new()

func configure(source) -> void:
	entries = JSON.parse_string(FileAccess.get_file_as_string(DATA)).entries
	art.configure(source)
	theme = art.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_render()

func set_catalog(rows: Array) -> void:
	catalog.clear()
	for row in rows: catalog[str(row.key)] = row.duplicate(true)
	_render()

func open() -> void:
	path.clear()
	show()
	_render()

func clear_catalog() -> void:
	catalog.clear()
	path.clear()
	_render()

func levels() -> Array:
	var result: Array = [entries]
	var rows := entries
	for index in path:
		if index < 0 or index >= rows.size() or not rows[index].has("children"): break
		rows = rows[index].children
		result.append(rows)
	return result

func activate(level: int, index: int) -> void:
	var groups := levels()
	if level < 0 or level >= groups.size() or index < 0 or index >= groups[level].size(): return
	var row: Dictionary = groups[level][index]
	if row.has("children"):
		path.resize(level)
		path.append(index)
		_render()
	else:
		var key := str(row.get("catalog_key", ""))
		if catalog.has(key) and catalog[key].get("supported", false): leaf_selected.emit(key)

func back() -> void:
	if path.is_empty(): close_requested.emit()
	else:
		path.pop_back()
		_render()

func layout(view: Vector2, bottom_anchor: Vector2) -> void:
	if viewport_size == view and anchor == bottom_anchor: return
	viewport_size = view
	anchor = bottom_anchor
	# e2: seven 36-pixel rows at 800 high; tall capture: eight at 900.
	row_count = clampi(int(view.y / (ROW_HEIGHT * 3.0)), 2, 12)
	_render()

func column_width(rows: Array) -> float:
	var width := 0.0
	var font: Font = get_theme_default_font()
	for row in rows: width = maxf(width, font.get_string_size(str(row.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	return ceilf((width + ICON_WIDTH + 16.0) / 8.0) * 8.0

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style

func _row_style(light: bool) -> StyleBox:
	var texture: Texture2D = art.texture("BUTTON_RECTANGLE_LIGHT" if light else "BUTTON_RECTANGLE_DARK")
	if texture == null: return _style(Color("252525") if light else Color("1c1c1c"))
	var style := StyleBoxTexture.new(); style.texture = texture
	style.set_texture_margin(SIDE_LEFT, 8); style.set_texture_margin(SIDE_RIGHT, 8)
	style.set_texture_margin(SIDE_TOP, 12); style.set_texture_margin(SIDE_BOTTOM, 12)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return style

func _render() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	row_controls.clear(); level_widths.clear(); compact_levels.clear()
	var groups := levels()
	var total := SEPARATOR * maxf(0, groups.size() - 1)
	for rows in groups:
		var width := column_width(rows) * ceilf(float(rows.size()) / row_count)
		level_widths.append(width); compact_levels.append(false); total += width
	# Compact the oldest ancestors first, preserving every row's icon and target.
	for level in range(maxi(0, groups.size() - 1)):
		if total <= viewport_size.x - 24.0: break
		var width := 36.0 * ceilf(float(groups[level].size()) / row_count)
		total -= level_widths[level] - width
		level_widths[level] = width; compact_levels[level] = true
	custom_minimum_size = Vector2(total, row_count * ROW_HEIGHT)
	size = custom_minimum_size
	position = Vector2(clampf(anchor.x - total / 2.0, 0.0, maxf(0.0, viewport_size.x - total - 24.0)), maxf(0.0, anchor.y - size.y))
	var x := 0.0
	for level in groups.size():
		if level > 0:
			var separator := TextureRect.new(); separator.texture = art.texture("BUTTON_RECTANGLE_DIVIDER")
			separator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; separator.stretch_mode = TextureRect.STRETCH_TILE
			separator.position = Vector2(x, 0); separator.size = Vector2(SEPARATOR, size.y)
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(separator); x += SEPARATOR
		var background := ColorRect.new(); background.color = Color("1c1c1c")
		background.position = Vector2(x, 0); background.size = Vector2(level_widths[level], size.y)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
		var rows: Array = groups[level]
		var width := 36.0 if compact_levels[level] else column_width(rows)
		for column in int(ceilf(float(rows.size()) / row_count)):
			for stripe in row_count:
				var band := Panel.new()
				band.position = Vector2(x + column * width, stripe * ROW_HEIGHT)
				band.size = Vector2(width, ROW_HEIGHT)
				band.add_theme_stylebox_override("panel", _row_style(stripe % 2 == 0))
				band.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(band)
		var controls: Array = []
		for index in rows.size():
			var row: Dictionary = rows[index]
			var selected := level < path.size() and path[level] == index
			var opener := row.has("children")
			var definition: Dictionary = catalog.get(str(row.get("catalog_key", "")), {})
			var button := Button.new()
			button.position = Vector2(x + int(index / row_count) * width, (index % row_count) * ROW_HEIGHT)
			button.size = Vector2(width, ROW_HEIGHT)
			button.disabled = not opener and not definition.get("supported", false)
			button.tooltip_text = str(row.label)
			# Catalog reasons describe unfinished adapter work, not native tooltip
			# copy. Keep them in semantic diagnostics, never in the visible menu.
			button.add_theme_stylebox_override("normal", _row_style(selected or index % row_count % 2 == 0))
			button.add_theme_stylebox_override("hover", _row_style(true))
			button.add_theme_stylebox_override("pressed", _row_style(true))
			button.add_theme_stylebox_override("disabled", _row_style(index % row_count % 2 == 0))
			button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			button.pressed.connect(activate.bind(level, index))
			button.gui_input.connect(_gui_input)
			add_child(button); controls.append(button)
			var frame := NinePatchRect.new(); frame.name = "Frame"
			frame.texture = art.texture("BUTTON_PICTURE_BOX"); frame.size = Vector2(36, 36)
			frame.patch_margin_left = 8; frame.patch_margin_right = 8; frame.patch_margin_top = 12; frame.patch_margin_bottom = 12
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(frame)
			var icon := TextureRect.new(); icon.name = "Icon"; icon.position = Vector2(2, 2); icon.size = Vector2(ICON_WIDTH, ICON_WIDTH)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var token := str(row.icon)
			if row.has("custom_icon"): token = "CUSTOM_WORKSHOP_LIST_ICON:" + str(row.custom_icon)
			icon.texture = art.texture(token) if not token.is_empty() else null
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(icon)
			if button.disabled: icon.modulate = Color(0.5, 0.5, 0.5)
			if not compact_levels[level]:
				var text := Label.new(); text.text = row.label; text.position = Vector2(ICON_WIDTH + 6, 0)
				text.size = Vector2(width - ICON_WIDTH - 6, ROW_HEIGHT); text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				text.add_theme_font_size_override("font_size", 12)
				text.add_theme_color_override("font_color", Color("666666") if button.disabled else (Color("7bbbbb") if level < path.size() and not selected else Color("00ffff")) if opener else Color("dddddd"))
				text.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(text)
		row_controls.append(controls)
		x += level_widths[level]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		back(); accept_event()
