extends "res://scripts/location_staff_candidates_frame.gd"
signal unit_chosen(unit_id: int)
signal cancelled
var actions_enabled:=false
var input_allowed: Callable
# Native candidate rows, protected capture20260930-005254. Parent workflow remains
# hidden until input, portraits and complete live acceptance have been verified.
const Format = preload("res://scripts/location_staff_candidates_format.gd")
const COLOR_NAMES = ["BLACK","BLUE","GREEN","CYAN","RED","MAGENTA","BROWN","LGRAY","DGRAY","LBLUE","LGREEN","LCYAN","LRED","LMAGENTA","YELLOW","WHITE"]
var rows: Array = []
var all_rows: Array = []
var filter_key := PackedByteArray()
var filter_text := PackedByteArray()
var filter_focused := false
# Supported native NormalizeSearchString RVA52cee0, table52d058. Byte semantics
# match the guarded native name-key reader, including single-byte accent folds.
const FILTER_FOLD = [99,117,101,97,97,97,97,99,101,101,101,105,105,105,97,97,101,97,97,111,111,111,117,117,121,111,117,155,156,157,158,159,97,105,111,117,110,110]
var first := 0
var selected := 0
var colors: Array[Color] = []
var ticks_override := -1
var last_phase := -1
var last_filter_phase := -1
var unit_icons: Dictionary = {}
var icon_elapsed := 0.0
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()

func configure(source) -> void:
	super.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP
	scrollbar.row_changed.connect(func(value):first=value;update_icons())
	picture.configure(source)
	# Palette values come from the supported installation, never guessed colors.
	var palette := FileAccess.get_file_as_string(source.assets_root().path_join("data/init/colors.txt"))
	colors.clear()
	for color_name in COLOR_NAMES:
		var channels: Array = []
		for channel in ["R","G","B"]:
			var pattern: String = "["+color_name+"_"+channel+":"
			var start := palette.find(pattern)
			if start<0:colors.clear();return
			var value := palette.substr(start+pattern.length()).get_slice("]",0)
			if not value.is_valid_int() or int(value)<0 or int(value)>255:colors.clear();return
			channels.append(float(value)/255.0)
		colors.append(Color(channels[0],channels[1],channels[2]))

func display_rows(observed: Array, offset := 0, cursor := 0) -> void:
	all_rows=observed.duplicate(true)
	if all_rows.is_empty():
		active_header=3;descending=[true,true,true,true];filter_key=PackedByteArray();filter_text=PackedByteArray();filter_focused=false
	_rebuild_filtered_rows()
	first=clampi(offset,0,maxi(0,rows.size()-16))
	selected=cursor
	display(rows.size(),first,active_header,descending)
	update_icons()

# Query normalization and text editing belong to the presentation input path.
# This method takes an already normalized native byte key, never display text.
func apply_filter_key(key: PackedByteArray) -> void:
	filter_key=key.duplicate()
	_rebuild_filtered_rows()
	first=0;selected=0
	display(rows.size(),first,active_header,descending)
	update_icons()

func _rebuild_filtered_rows() -> void:
	rows=[]
	for row in all_rows:
		if filter_key.is_empty():rows.append(row);continue
		# Unknown legacy keys are not guessed from a visible name.
		if row.get("name_sort_key") is PackedByteArray and contains_bytes(row.name_sort_key,filter_key):rows.append(row)
	_sort_rows()

static func contains_bytes(value: PackedByteArray,query: PackedByteArray) -> bool:
	if query.is_empty():return true
	for start in maxi(0,value.size()-query.size()+1):
		var matches:=true
		for index in query.size():
			if value[start+index]!=query[index]:matches=false;break
		if matches:return true
	return false

func move_selection(delta: int) -> void:
	if rows.is_empty():return
	selected=clampi(selected+delta,0,rows.size()-1)
	if selected<first:first=selected
	elif selected>=first+16:first=selected-15
	display(rows.size(),first,active_header,descending)
	update_icons()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():return
	if input_allowed.is_valid() and not input_allowed.call():return
	# Native discrete right-click closes the selector, including from its textbox.
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled();cancelled.emit();return
	if not event is InputEventKey or not event.pressed:return
	# Native outer textbox handling consumes Enter to finish text entry. Only a
	# subsequent unfocused Enter reaches the occupation selector's SELECT action.
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed):
		get_viewport().set_input_as_handled()
		if event.echo:return
		if filter_focused:filter_focused=false;queue_redraw();return
		if actions_enabled and selected>=0 and selected<rows.size():unit_chosen.emit(int(rows[selected].unit_id))
		return
	if filter_focused and event.keycode!=KEY_ESCAPE:
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
		var changed:=false
		if event.keycode==KEY_BACKSPACE:
			if not filter_text.is_empty():filter_text.resize(filter_text.size()-1);changed=true
		elif event.unicode>=32:
			# Native SDL input feeds UTF-8 bytes to its byte-oriented textbox.
			# The 33-cell limit counts those bytes, not Unicode characters.
			for value in String.chr(event.unicode).to_utf8_buffer():
				if filter_text.size()>=33:break
				filter_text.append(value);changed=true
		if changed:
			var key:=filter_text.duplicate()
			for i in key.size():
				if key[i]>=65 and key[i]<=90:key[i]+=32
				elif key[i]>=128 and key[i]<=165:key[i]=FILTER_FOLD[key[i]-128]
			apply_filter_key(key)
		get_viewport().set_input_as_handled()
		return
	if rows.is_empty():return
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed:return
	var delta:=0
	# Supported native interface bindings: arrows/numpad and page keys.
	match event.keycode:
		KEY_UP,KEY_8,KEY_KP_8:delta=-1
		KEY_DOWN,KEY_2,KEY_KP_2:delta=1
		KEY_PAGEUP,KEY_9,KEY_KP_9:delta=-16
		KEY_PAGEDOWN,KEY_3,KEY_KP_3:delta=16
	if delta!=0:
		move_selection(delta)
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index==MOUSE_BUTTON_LEFT:
		if Rect2(24,660,312,36).has_point(event.position):
			filter_focused=true;accept_event();return
		for header in 4:
			# Skills spans cells83..102, including its blank native caption.
			var width: int=20 if header==3 else HEADER_WIDTH[header]
			if Rect2(HEADER_X[header]*8,12,width*8,12).has_point(event.position):
				select_sort(header);accept_event();return
		if actions_enabled and Rect2(8,36,552,576).has_point(event.position):
			var index:=first+int((event.position.y-36)/36)
			if index<rows.size():
				unit_chosen.emit(int(rows[index].unit_id));accept_event();return
		# A click reaching the blank panel dismisses textbox focus. Header and
		# textbox handlers above retain it, matching the native widget dispatch.
		filter_focused=false;queue_redraw()
	if not Rect2(8,36,560,600).has_point(event.position):return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(16 if event.shift_pressed else 1))
		accept_event()

func select_sort(header: int) -> void:
	if header<0 or header>=4:return
	if active_header==header:descending[header]=not descending[header]
	active_header=header
	_sort_rows()
	first=0;selected=0
	display(rows.size(),first,active_header,descending)
	update_icons()

func _sort_rows() -> void:
	# Legacy visual fixtures have no ordering evidence. The live controller
	# requires these fields; never derive missing keys from visible captions.
	for row in rows:
		for key in ["source_index","profession_order","status_order","name_sort_key","profession_sort_key"]:
			if not row.has(key):return
	rows.sort_custom(func(a,b):
		var order:=compare_rows(a,b)
		if order==0:return int(a.source_index)<int(b.source_index)
		return order<0 if descending[active_header] else order>0)

func compare_rows(a: Dictionary,b: Dictionary) -> int:
	match active_header:
		0:return compare_bytes(a.name_sort_key,b.name_sort_key)
		1:
			var primary:=int(a.profession_order)-int(b.profession_order)
			return primary if primary!=0 else int(a.status_order)-int(b.status_order)
		2:return compare_bytes(a.profession_sort_key,b.profession_sort_key)
		3:return int(b.score)-int(a.score)
	return 0

func compare_bytes(a: PackedByteArray,b: PackedByteArray) -> int:
	# Native compares unsigned CP437 bytes, not Unicode codepoints or locale.
	for index in mini(a.size(),b.size()):
		if a[index]!=b[index]:return int(a[index])-int(b[index])
	return a.size()-b.size()

func update_icons() -> void:
	var current: Dictionary={}
	if world!=null:
		for index in mini(16,rows.size()-first):
			var id := int(rows[first+index].get("unit_id",-1))
			if id<0:continue
			var icon: Texture2D=world.selection_icon(1,id,true)
			if icon!=null:current[id]=icon
	# Replace rather than retain an unavailable actor's old appearance.
	unit_icons=current
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	icon_elapsed+=delta
	if icon_elapsed>=0.25:icon_elapsed=0;update_icons()
	var ticks := ticks_override if ticks_override>=0 else Time.get_ticks_msec()
	var phase := 0 if ticks%1000<333 else 1
	if phase!=last_phase:last_phase=phase;queue_redraw()
	var filter_phase:=0 if ticks%1000<500 else 1
	if filter_phase!=last_filter_phase:last_filter_phase=filter_phase;queue_redraw()

func _draw() -> void:
	super._draw()
	if world==null or colors.size()!=16 or theme.default_font==null:return
	var font: Font=theme.default_font
	var ticks := ticks_override if ticks_override>=0 else Time.get_ticks_msec()
	var glyphs: Dictionary={}
	for index in mini(16,rows.size()-first):
		var row: Dictionary=rows[first+index]
		var top := 3+index*3
		var suffix := "SELECTED" if first+index==selected else "DARK"
		patch("BUTTON_RECTANGLE_"+suffix,Vector2i(1,top),69,3)
		patch("",Vector2i(1,top),5,3,picture.texture(first+index==selected))
		# Protected020926: native anchored full-body image32x32, offset2,2.
		var icon: Texture2D=unit_icons.get(int(row.get("unit_id",-1)))
		if icon!=null:draw_texture_rect(icon,Rect2(10,top*12+2,32,32),false)
		for y in 3:
			for x in range(1,70):glyphs.erase(Vector2i(x,top+y))
		var names = Format.name_lines(row.get("base_name"),row.get("profession_name"))
		var color := Format.name_color_index(row.get("profession_color"),row.get("legendary",false),ticks)
		if names!=null and color>=0:
			for line in 2:
				write_cells(glyphs,Vector2i(6,top+1+line),names[line],color)
		var skills = Format.skill_lines(row.get("skills",[]))
		if skills!=null:
			# Native draws every skill, then the next row paints over overflow.
			# The last visible row may extend below the scrolling region.
			for line in skills.size():
				write_cells(glyphs,Vector2i(37,top+1+line),skills[line],15)
	# Native empties the filter's text field after rows, independently of its
	# right-hand icon. Overflow glyphs over that icon remain in the cell buffer.
	for y in range(55,58):
		for x in range(3,38):glyphs.erase(Vector2i(x,y))
	# Native filter text starts atcell51,60, bright white, with byte glyphs.
	var visible_text:=""
	for value in filter_text:
		visible_text+=String.chr(value if value<128 else art.CP437_HIGH[value-128])
	# widget_textbox::render RVA1419533 appends underscore while tick%1000<500.
	if filter_focused and ticks%1000<500:visible_text+="_"
	write_cells(glyphs,Vector2i(5,56),visible_text,15)
	for cell in glyphs:
		var glyph: Array=glyphs[cell]
		font.draw_string(get_canvas_item(),Vector2(cell.x*8,(cell.y+1)*12),glyph[0],HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[glyph[1]])

func write_cells(glyphs: Dictionary, origin: Vector2i, text: String, color: int) -> void:
	# A space replaces the previous glyph too. Drawing overlapping strings
	# cannot reproduce the native character buffer's overwrite behavior.
	for index in text.length():glyphs[origin+Vector2i(index,0)]=[text[index],color]
