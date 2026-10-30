extends Control
# Native selector evidence: protected140512/140912. Coordinates use DF's 12px cells.
signal row_changed(first: int)
var count := 0
var page := 10
var first := 0
var dragging := false
var hover_cell := -1
var source
var textures: Dictionary = {}
var use_classic_art := false
var classic_textures: Dictionary = {}
var input_allowed: Callable
var wheel_enabled := true

func configure(world) -> void:
	source = world
	size = Vector2(16,360)
	mouse_exited.connect(func(): hover_cell = -1; queue_redraw())
	visibility_changed.connect(func(): if not is_visible_in_tree(): dragging = false)

func set_rows(total: int, position := 0) -> void:
	count = total; first = clampi(position,0,maxi(0,count-page))
	visible = count > page
	queue_redraw()

func move_to(position: int) -> void:
	var next := clampi(position,0,maxi(0,count-page))
	if next == first: return
	first = next; row_changed.emit(first); queue_redraw()

func thumb() -> Vector2i:
	var cells := int(size.y/12)-2
	# Native counts the inclusive span between the first and last visible rows.
	var height := clampi(1+int(cells*(page-1)/maxi(count,1)),2,cells)
	var offset := int(first*cells/maxi(count,1))
	if first > 0: offset = maxi(1,offset)
	if first == count-page: offset = cells-height
	return Vector2i(1+offset,height)

func drag_to(y: float) -> void:
	var cell := floori(y/12)
	var cells := int(size.y/12)-2
	if cell <= 1: move_to(0)
	elif cell >= cells: move_to(count-page)
	else: move_to(int((cell-1)*(count-page)/cells))

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if input_allowed.is_valid() and not input_allowed.call():dragging=false;return
	if dragging and event is InputEventMouseMotion:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		drag_to(local.y); get_viewport().set_input_as_handled()
	elif dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false; get_viewport().set_input_as_handled(); queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():dragging=false;return
	if event is InputEventMouseMotion:
		hover_cell = floori(event.position.y/12); queue_redraw()
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if wheel_enabled:move_to(first+(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)*(page if event.shift_pressed else 1))
		accept_event(); return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	var cell := floori(event.position.y/12)
	var grip := thumb()
	if cell == 0: move_to(first-1)
	elif cell == int(size.y/12)-1: move_to(first+1)
	elif cell < grip.x: move_to(first-page)
	elif cell >= grip.x+grip.y: move_to(first+page)
	else: dragging = true
	accept_event()

func texture(token: String) -> Texture2D:
	if use_classic_art: return classic_texture(token)
	if not textures.has(token):
		if source == null or not source.has_method("ui_texture"): return null
		if token in ["SCROLLBAR","SCROLLBAR_OFFCENTER_SCROLLER","SCROLLBAR_OFFCENTER_SCROLLER_HOVER","SCROLLBAR_SMALL_SCROLLER","SCROLLBAR_SMALL_SCROLLER_HOVER"]:
			textures[token] = source.ui_texture(token)
		else:
			var left: Texture2D = source.ui_texture(token,0)
			var right: Texture2D = source.ui_texture(token,1)
			if left == null or right == null: return null
			var combined := Image.create(16,12,false,Image.FORMAT_RGBA8)
			combined.blit_rect(left.get_image(),Rect2i(0,0,8,12),Vector2i.ZERO)
			combined.blit_rect(right.get_image(),Rect2i(0,0,8,12),Vector2i(8,0))
			textures[token] = ImageTexture.create_from_image(combined)
	return textures[token]

func classic_texture(token: String) -> Texture2D:
	if classic_textures.is_empty():
		if source == null: return null
		var sheet := Image.load_from_file(source.assets_root().path_join("data/art/scrollbar.png"))
		if sheet == null or sheet.get_size() != Vector2i(96,48): return null
		# Native init.scrollbar_texpos layout, independently observed in the
		# religious selector. This sheet differs from INTERFACE_BITS at edges.
		var cells := {"SCROLLBAR":[0,12,24],"SCROLLBAR_UP_HOVER":[2],"SCROLLBAR_DOWN_HOVER":[14],
			"SCROLLBAR_TOP_SCROLLER":[6],"SCROLLBAR_TOP_SCROLLER_HOVER":[8],
			"SCROLLBAR_BOTTOM_SCROLLER":[42],"SCROLLBAR_BOTTOM_SCROLLER_HOVER":[44],
			"SCROLLBAR_BLANK_SCROLLER":[30],"SCROLLBAR_BLANK_SCROLLER_HOVER":[32],
			"SCROLLBAR_CENTER_SCROLLER":[18],"SCROLLBAR_CENTER_SCROLLER_HOVER":[20],
			"SCROLLBAR_OFFCENTER_SCROLLER":[10,22],"SCROLLBAR_OFFCENTER_SCROLLER_HOVER":[34,46],
			"SCROLLBAR_SMALL_SCROLLER":[26,38],"SCROLLBAR_SMALL_SCROLLER_HOVER":[28,40]}
		for name in cells:
			var combined := Image.create(16,12*cells[name].size(),false,Image.FORMAT_RGBA8)
			for row in cells[name].size():
				var cell: int = cells[name][row]
				combined.blit_rect(sheet,Rect2i((cell%12)*8,(cell/12)*12,16,12),Vector2i(0,row*12))
			classic_textures[name] = ImageTexture.create_from_image(combined)
	return classic_textures.get(token)

func _draw() -> void:
	if count <= page: return
	var cells := int(size.y/12)
	var grip := thumb()
	var middle := grip.x+(grip.y-1)*0.5
	for cell in cells:
		var token := "SCROLLBAR"
		var row := 0 if cell == 0 else 2 if cell == cells-1 else 1
		if cell == 0 and hover_cell == 0: token = "SCROLLBAR_UP_HOVER"; row = 0
		elif cell == cells-1 and hover_cell == cells-1: token = "SCROLLBAR_DOWN_HOVER"; row = 0
		elif cell >= grip.x and cell < grip.x+grip.y:
			row = 0
			if grip.y == 2: token = "SCROLLBAR_SMALL_SCROLLER"; row = cell-grip.x
			elif cell == grip.x: token = "SCROLLBAR_TOP_SCROLLER"
			elif cell == grip.x+grip.y-1: token = "SCROLLBAR_BOTTOM_SCROLLER"
			elif cell == middle: token = "SCROLLBAR_CENTER_SCROLLER"
			elif absf(cell-middle) == 0.5: token = "SCROLLBAR_OFFCENTER_SCROLLER"; row = 0 if cell < middle else 1
			else: token = "SCROLLBAR_BLANK_SCROLLER"
			if hover_cell > 0 and hover_cell < cells-1: token += "_HOVER"
		var art := texture(token)
		if art != null: draw_texture_rect_region(art,Rect2(0,cell*12,16,12),Rect2(0,row*12,16,12))
