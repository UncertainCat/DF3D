extends Control
# Native386629 counteroffer pane. Visibility follows requested items, not the
# negotiation flag: accepted goods remain here until the explicit Okay action.
signal dismissed
var input_allowed: Callable
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var colors: Array[Color]=[]
var page: Dictionary={}
var icons: Dictionary={}
var button: Rect2
func configure_counter(source) -> void:
	art.configure(source);picture.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
func set_page(value: Dictionary,textures: Dictionary) -> void:
	page=value;icons=textures;queue_redraw()
func layout(extent: Vector2) -> void:
	size=extent;button=Rect2(size.x-80,0,64,36);queue_redraw()
func _text(value: String,point: Vector2,color: int) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _patch(texture: Texture2D,origin: Vector2,columns: int) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
func _draw() -> void:
	if colors.size()!=16 or page.is_empty():return
	draw_rect(Rect2(Vector2.ZERO,size),Color8(28,28,28))
	_patch(art.texture("HORIZONTAL_OPTION_CONFIRM"),button.position,8)
	for i in mini(2,page.heading.size()):
		var heading: String=page.heading[i]
		# Native glyph cells survive button artwork; its caption replaces cells.
		if i==1:
			var start: int=int((button.position.x+16)/8)
			var end: int=start+String(page.dismiss).length()
			_text(heading.substr(0,maxi(0,start)),Vector2(0,24),15)
			if heading.length()>end:_text(heading.substr(end),Vector2(end*8,24),15)
		else:_text(heading,Vector2(0,12),15)
	_text(page.dismiss,button.position+Vector2(16,24),15)
	for i in page.rows.size():
		var row: Dictionary=page.rows[i];var y: int=36+(int(page.offset)+i)*36
		if y>=size.y:break
		_patch(art.texture("BUTTON_RECTANGLE"),Vector2(0,y),int(size.x/8)-1)
		_patch(picture.texture(false),Vector2(0,y),5)
		var icon: Texture2D=icons.get(row.id)
		if icon!=null and y+36<=size.y:draw_texture_rect(icon,Rect2(2,y+2,32,32),false)
		var caption: String=row.caption;var length: int=maxi(0,int(size.x/8)-23)
		if caption.length()>length:caption=caption.substr(0,length-3)+"..." if length>3 else caption.substr(0,length)
		# DF writes value cells after the caption, replacing those glyph cells.
		# Drawing both strings over one another would blend their glyph pixels.
		if row.appraisal>0:caption=caption.substr(0,maxi(0,int((size.x-272)/8)))
		_text(caption,Vector2(56,y+24),[14,15,13,12,10][row.disposition])
		if row.contained_count>0:_text(row.contents_caption.substr(0,maxi(0,int((size.x-272)/8))),Vector2(56,y+36),14)
		if row.appraisal>0:_text("Value: "+row.value_caption,Vector2(size.x-216,y+24),14)
		_text("Weight: "+row.weight_caption,Vector2(size.x-216,y+36),15)
func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index==MOUSE_BUTTON_LEFT and not page.is_empty() and button.has_point(event.position):dismissed.emit()
