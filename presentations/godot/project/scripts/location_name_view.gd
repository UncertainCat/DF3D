extends Control
# Native naming reference223634. This component is not an exposed Details route.
signal cancelled
const Art=preload("res://scripts/original_ui.gd")
const COMPONENTS=["Front Compound","Rear Compound","First Adjective","Second Adjective","Hyphen Compound","The X","Of X"]
const PARTS=["Singular Noun","Plural Noun","Adjective","Prefix","Present (1st)","Present (3rd)","Preterite","Past Participle","Present Participle"]
const CYAN=Color8(18,254,207)
const YELLOW=Color8(255,225,17)
var art=Art.new()
var state
var scrollbar
var first:=0
var entering_filter:=false
var input_allowed: Callable
var _query:=PackedByteArray()
var _component:=-1

func configure(source,model) -> void:
	art.configure(source);theme=art.theme;state=model
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(scrollbar);scrollbar.configure(source)
	scrollbar.position=Vector2(576,108);scrollbar.size=Vector2(16,540);scrollbar.page=15
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	state.changed.connect(refresh);refresh()

func layout(view: Vector2) -> void:
	position=Vector2(368,48+fposmod(view.y,12)*0.5);size=Vector2(608,660)

func refresh() -> void:
	if _component!=state.component or _query!=state.query:
		first=0;_component=state.component;_query=state.query.duplicate()
	scrollbar.set_rows(state.rows.size(),first);first=scrollbar.first
	queue_redraw()

func available() -> bool:
	return state!=null and state.phase in [state.Phase.Ready,state.Phase.Editing]

func component_rect(index: int) -> Rect2:return Rect2(16,72+index*36,184,36)
func random_rect(index: int) -> Rect2:return Rect2(208,72+index*36,64,36)
func clear_rect(index: int) -> Rect2:return Rect2(272,72+index*36,56,36)
func row_rect(index: int) -> Rect2:return Rect2(352,108+index*36,224,36)

func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		entering_filter=false;cancelled.emit();accept_event();return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if event.position.x>=352:scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
		accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	accept_event()
	if Rect2(512,12,64,36).has_point(event.position):entering_filter=false;cancelled.emit();return
	if Rect2(352,72,240,36).has_point(event.position):entering_filter=not entering_filter;queue_redraw();return
	for index in 7:
		if component_rect(index).has_point(event.position):state.set_choices(index,state.query);return
	if not available():return
	if Rect2(424,12,80,36).has_point(event.position):state.random_whole();return
	for index in 7:
		if random_rect(index).has_point(event.position):state.random_component(index);return
		if clear_rect(index).has_point(event.position):state.clear_component(index);return
	for index in mini(15,state.rows.size()-first):
		if row_rect(index).has_point(event.position):state.choose(first+index);return

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()) or not event is InputEventKey or not event.pressed:return
	if event.keycode==KEY_ESCAPE:
		entering_filter=false;cancelled.emit();get_viewport().set_input_as_handled();return
	if not entering_filter:return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	var value: PackedByteArray=state.query.duplicate()
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:entering_filter=false;queue_redraw()
	elif event.keycode==KEY_BACKSPACE:
		if not value.is_empty():value.resize(value.size()-1)
	elif event.unicode>=32:
		for byte in String.chr(event.unicode).to_utf8_buffer():
			if value.size()>=10:break
			value.append(byte-32 if byte>=97 and byte<=122 else byte)
	state.set_choices(state.component,value)
	get_viewport().set_input_as_handled()

func patch(token: String, rect: Rect2) -> void:
	var texture: Texture2D=art.texture(token)
	if texture==null:return
	var columns:=int(rect.size.x/8);var lines:=int(rect.size.y/12)
	for y in lines:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),
				Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else 24 if y==lines-1 else 12,8,12))

func text(value: String, point: Vector2, color:=Color.WHITE) -> void:
	if theme!=null and theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)

func button(token: String, rect: Rect2, caption: String, color:=Color.WHITE) -> void:
	patch(token,rect);text(caption,rect.position+Vector2(floorf((rect.size.x-caption.length()*8)/2),24),color)

static func short_word(value: String) -> String:
	# Native1fde73/1fdfe2: nine-cell columns, threshold7 and six-cell result.
	return value.left(3)+"..." if value.length()>=7 else value

func _draw() -> void:
	if state==null:return
	patch("HOVER_RECTANGLE",Rect2(0,0,608,660))
	text("Name the location",Vector2(224,24))
	button("HORIZONTAL_OPTION_CONFIRM",Rect2(424,12,80,36),"Random")
	button("HORIZONTAL_OPTION_CONFIRM",Rect2(512,12,64,36),"Done")
	var native: String=state.snapshot.get("native_header","")
	var english: String=state.snapshot.get("english_header","")
	text(native,Vector2(296-floori(native.length()/2.0)*8,48),YELLOW)
	if not state.snapshot.is_empty():text('"'+english+'"',Vector2(296-floori((english.length()+2)/2.0)*8,60),CYAN)
	for index in 7:
		patch("BUTTON_CATEGORY_RECTANGLE_ON_SELECTED" if index==state.component else "BUTTON_CATEGORY_RECTANGLE_ON",component_rect(index))
		# Native unselected category cells retain a black one-pixel left edge.
		if index!=state.component:draw_rect(Rect2(16,72+index*36,1,36),Color.BLACK)
		text(COMPONENTS[index],Vector2(40,96+index*36))
		button("HORIZONTAL_OPTION_CONFIRM",random_rect(index),"Random")
		var words: Array=state.snapshot.get("value",{}).get("words",[])
		var present: bool=words.size()==7 and words[index]>=0
		button("HORIZONTAL_OPTION_REMOVE" if present else "HORIZONTAL_OPTION_INACTIVE",clear_rect(index),"Clear")
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			for x in 30:
				var source_x:=0 if x==0 else x-24 if x>=26 else 1
				draw_texture_rect_region(filter,Rect2(352+x*8,72+y*12,8,12),Rect2(source_x*8,y*12,8,12))
	var display:=""
	for byte in state.query:display+=String.chr(byte if byte<128 else Art.CP437_HIGH[byte-128])
	text(display if not display.is_empty() else "...",Vector2(368,96),Color.WHITE if entering_filter else Color8(160,160,160))
	for index in mini(15,state.rows.size()-first):
		var row: Dictionary=state.rows[first+index]
		patch("BUTTON_RECTANGLE",row_rect(index))
		text(short_word(row.english),Vector2(352,132+index*36),CYAN)
		text(short_word(row.translated),Vector2(424,132+index*36),YELLOW)
		text(PARTS[row.part],Vector2(496,132+index*36))

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
