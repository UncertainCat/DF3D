extends Control
# DF53.16 native cell captures: fixtures/construction/pressure_plate.json.
# Coordinates are relative to native cell (73,5), at 8x12 pixels per cell.
signal choice(kind: String, value: int)
signal scrolled(first: int)
var art
var profile: Dictionary
var examples: Array
var first := 0
var enabled := true
var rows: Control
var scrollbar
var reset_group := ButtonGroup.new()

func configure(original_art, options: Dictionary, creatures: Array, offset: int, interactive: bool) -> void:
	art = original_art; profile = options.duplicate(); examples = creatures.duplicate(true)
	first = clampi(offset,0,185); enabled = interactive
	theme = art.theme.duplicate(); theme.default_font_size = 12
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Native placement/Keep captures retain the full pane with creature triggers off.
	custom_minimum_size = Vector2(384,432)
	reset_button("Resets",true,Vector2.ZERO,Vector2(80,36))
	reset_button("One use only",false,Vector2(88,0),Vector2(128,36))
	for entry in [["water",36,"Water does not trigger"],["magma",72,"Magma does not trigger"],["track",108,"Minecarts do not trigger"],["units",144,"Creatures do not trigger"]]:
		var flag: String = entry[0]; var y: int = entry[1]
		texture_button(flag,int(not profile[flag]),Vector2(0,y),"BUILDING_PLACEMENT_PRESSURE_PLATE_" + ("ACTIVE_TRIGGER" if profile[flag] else "INACTIVE_TRIGGER"))
		if not profile[flag]: label(entry[2],Vector2(40,y+12))
		elif flag in ["water","magma"]:
			label("Water" if flag == "water" else "Magma",Vector2(40,y)); label("Depth",Vector2(40,y+12))
			for depth in 8:
				var selected: bool = depth >= int(profile[flag+"_min"]) and depth <= int(profile[flag+"_max"])
				texture_button(flag+"_depth",depth,Vector2(104+depth*32,y),"BUILDING_PLACEMENT_PRESSURE_PLATE_"+flag.to_upper()+"_%d_" % depth+("ON" if selected else "OFF"))
		elif flag == "track":
			label("Cart",Vector2(40,y)); label("Weight",Vector2(40,y+12))
			for button in [["track_min",-1,96],["track_min",1,168],["track_max",-1,224],["track_max",1,296]]:
				var token := "BUTTON_ADD" if button[1] == 1 else "BUTTON_SUBTRACT"
				texture_button(button[0],button[1],Vector2(button[2],y),token,token+"_HOVER",token+"_PRESSED")
			weight(int(profile.track_min),false,Vector2(120,y+12))
			label("to",Vector2(200,y+12)); weight(int(profile.track_max),true,Vector2(248,y+12))
		else: label("Creature trigger settings",Vector2(40,y+12))
	if not profile.units: return
	texture_button("citizens",int(not profile.citizens),Vector2(0,180),"BUILDING_PLACEMENT_PRESSURE_PLATE_"+("ACTIVE_TRIGGER" if profile.citizens else "INACTIVE_TRIGGER"))
	label("Citizens trigger" if profile.citizens else "Citizens do not trigger",Vector2(40,192))
	if examples.size() != 200: return
	label("Range: %s to %s" % [example(int(profile.unit_min)),example(int(profile.unit_max))],Vector2(8,228))
	rows = Control.new(); rows.position = Vector2(16,252); rows.size = Vector2(344,180); add_child(rows)
	rows.gui_input.connect(row_input)
	rebuild_rows()
	var bar = preload("res://scripts/area_location_scrollbar.gd").new()
	scrollbar = bar
	add_child(bar); bar.configure(art.world); bar.position = Vector2(360,252); bar.size = Vector2(16,180)
	bar.page = 15; bar.set_rows(200,first)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	bar.row_changed.connect(func(value: int): first = value; rebuild_rows(); scrolled.emit(first))

func set_locked(locked: bool) -> void:
	enabled = not locked
	for control in find_children("*","BaseButton",true,false): control.disabled = locked
	if scrollbar != null:
		scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
		if locked: scrollbar.dragging = false

func row_input(event: InputEvent) -> void:
	if not enabled or scrollbar == null or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(first + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)*(15 if event.shift_pressed else 1))
		rows.accept_event()

func label(text: String, at: Vector2, color: Color = Color.WHITE) -> Label:
	var control := Label.new(); control.text = text; control.position = at
	control.add_theme_color_override("font_color",color); control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control); return control

func weight(value: int, upper: bool, at: Vector2) -> void:
	# Native character226 is the CP437 weight glyph (mapped to U+0393 by DF2UTF).
	var text := "Any" if upper and value == 2000 else str(value) + String.chr(0x393)
	var control := label(text,at); control.size.x = 48; control.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func reset_button(text: String, resets: bool, at: Vector2, dimensions: Vector2) -> void:
	var control := Button.new(); control.text = text; control.position = at; control.size = dimensions
	control.toggle_mode = true; control.button_pressed = profile.resets == resets; control.disabled = not enabled
	control.button_group = reset_group
	control.set_meta("pressure_kind","resets"); control.set_meta("pressure_value",int(resets))
	control.add_theme_color_override("font_color",Color.WHITE); control.add_theme_color_override("font_pressed_color",Color.WHITE)
	control.pressed.connect(func(): choice.emit("resets",int(resets))); add_child(control)

func texture_button(kind: String, value: int, at: Vector2, token: String, hover: String = "", pressed: String = "") -> void:
	var control := TextureButton.new(); control.position = at; control.disabled = not enabled
	control.texture_normal = art.texture(token)
	if not hover.is_empty(): control.texture_hover = art.texture(hover)
	if not pressed.is_empty(): control.texture_pressed = art.texture(pressed)
	control.set_meta("pressure_kind",kind); control.set_meta("pressure_value",value)
	control.pressed.connect(func(): choice.emit(kind,value)); add_child(control)

func example(size_value: int) -> String:
	var index := clampi(size_value / 1000 - 1,0,199)
	var row: Dictionary = examples[index]
	return "(%d)" % int(row.size) if int(row.race_id) == -1 else str(row.name)

func rebuild_rows() -> void:
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	for i in 15:
		var row: Dictionary = examples[first+i]
		var selected: bool = int(row.size) >= int(profile.unit_min) and int(row.size) <= int(profile.unit_max)
		var control := Button.new(); control.text = example(int(row.size)); control.position = Vector2(0,i*12)
		control.alignment = HORIZONTAL_ALIGNMENT_LEFT; control.disabled = not enabled
		control.mouse_filter = Control.MOUSE_FILTER_PASS
		for state in ["normal","hover","pressed","disabled","focus"]: control.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		control.add_theme_color_override("font_color",Color.WHITE if selected else Color("808080"))
		control.add_theme_color_override("font_hover_color",Color.WHITE)
		control.set_meta("pressure_kind","creature"); control.set_meta("pressure_value",int(row.size))
		control.pressed.connect(func(): choice.emit("creature",int(row.size))); rows.add_child(control)
		# Apply dimensions after inheriting the native bitmap font; the fallback
		# theme's larger minimum would otherwise make adjacent hit regions overlap.
		control.size = Vector2(344,12)
