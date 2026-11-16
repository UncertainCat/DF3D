extends Control
# Native386629 counteroffer pane. Visibility follows requested items, not the
# negotiation flag: accepted goods remain here until the explicit Okay action.
signal dismissed
signal scrolled
var input_allowed: Callable
var art=preload("res://scripts/original_ui.gd").new()
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var colors: Array[Color]=[]
var page: Dictionary={}
var icons: Dictionary={}
var button: Rect2
var canvas:=Control.new()
# Native38702e uses ordinary fortress goods height for thumb artwork, while
# counteroffer input uses requested-item height. Keep those two counts separate.
class CounterScrollbar extends "res://scripts/area_location_scrollbar.gd":
	var artwork_count:=0
	var drawing:=false
	func _draw() -> void:
		drawing=true;super._draw();drawing=false
	func thumb() -> Vector2i:
		if not drawing:return super.thumb()
		var cells:=int(size.y/12)-2
		var height:=clampi(1+int(cells*(page-1)/maxi(artwork_count,1)),2,cells)
		var offset:=int(first*cells/maxi(artwork_count,1))
		if first>0:offset=maxi(1,offset)
		if first==artwork_count-page:offset=cells-height
		return Vector2i(1+offset,height)
var scrollbar=CounterScrollbar.new()
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func configure_counter(source) -> void:
	art.configure(source);picture.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	add_child(canvas);canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.clip_contents=true;canvas.draw.connect(_draw_rows)
	add_child(scrollbar);scrollbar.configure(source);scrollbar.wheel_enabled=false;scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(_first):canvas.queue_redraw();scrolled.emit())
func set_page(value: Dictionary,textures: Dictionary,goods_rows: int=-1) -> void:
	page=value;icons=textures;scrollbar.artwork_count=(int(page.get("total",0)) if goods_rows<0 else goods_rows)*3;layout(size)
func layout(extent: Vector2) -> void:
	size=extent
	canvas.position=Vector2(0,36);canvas.size=Vector2(size.x,maxi(0,floori((size.y-36)/36)*36))
	scrollbar.position=Vector2(size.x-24,36);scrollbar.size=Vector2(16,canvas.size.y);scrollbar.page=int(canvas.size.y/12)
	scrollbar.set_rows(int(page.get("total",0))*3,0 if page.is_empty() else scrollbar.first)
	button=Rect2(size.x-80-(16 if scrollbar.visible else 0),0,64,36)
	queue_redraw();canvas.queue_redraw()
func visible_first() -> int:return int(scrollbar.first/3)
func visible_count() -> int:return ceili((canvas.size.y+(scrollbar.first%3)*12)/36)
func _text(value: String,point: Vector2,color: int,target: CanvasItem=self) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(target.get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _patch(texture: Texture2D,origin: Vector2,columns: int,target: CanvasItem=self) -> void:
	if texture==null:return
	for y in 3:
		for x in columns:target.draw_texture_rect_region(texture,Rect2(origin+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,y*12,8,12))
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
func _draw_rows() -> void:
	if colors.size()!=16 or page.is_empty():return
	var width: float=size.x-(16 if scrollbar.visible else 0)
	for i in page.rows.size():
		var row: Dictionary=page.rows[i];var y: int=(int(page.offset)+i)*36-scrollbar.first*12
		if y>=canvas.size.y:break
		if y+36<=0:continue
		_patch(art.texture("BUTTON_RECTANGLE"),Vector2(0,y),int(width/8)-1,canvas)
		_patch(picture.texture(false),Vector2(0,y),5,canvas)
		var icon: Texture2D=icons.get(row.id)
		if icon!=null and y>=0 and y+36<=canvas.size.y:canvas.draw_texture_rect(icon,Rect2(2,y+2,32,32),false)
		var caption: String=row.caption;var length: int=maxi(0,int(width/8)-23)
		if caption.length()>length:caption=caption.substr(0,length-3)+"..." if length>3 else caption.substr(0,length)
		# DF writes value cells after the caption, replacing those glyph cells.
		# Drawing both strings over one another would blend their glyph pixels.
		if row.appraisal>0:caption=caption.substr(0,maxi(0,int((width-272)/8)))
		_text(caption,Vector2(56,y+24),[14,15,13,12,10][row.disposition],canvas)
		if row.contained_count>0:_text(row.contents_caption.substr(0,maxi(0,int((width-272)/8))),Vector2(56,y+36),14,canvas)
		if row.appraisal>0:_text("Value: "+row.value_caption,Vector2(width-216,y+24),14,canvas)
		_text("Weight: "+row.weight_caption,Vector2(width-216,y+36),15,canvas)
func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	if not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index==MOUSE_BUTTON_LEFT and not page.is_empty() and button.has_point(event.position):dismissed.emit()
