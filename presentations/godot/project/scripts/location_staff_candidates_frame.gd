extends Control
# Native selector chrome, protected capture20260930-005254. This is a component
# of the unfinished selector; it does not expose a route or fabricate row content.
const HEADERS := ["Name", "Cat", "Prof", ""]
const HEADER_X := [6,16,25,37]
const HEADER_WIDTH := [10,9,10,4]
var art = preload("res://scripts/original_ui.gd").new()
var world
var scrollbar
var active_header := 3
var descending: Array = [true,true,true,true]
var strips: Dictionary = {}

func configure(source) -> void:
	world=source;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	scrollbar=preload("res://scripts/area_location_scrollbar.gd").new()
	add_child(scrollbar);scrollbar.configure(source)
	scrollbar.position=Vector2(568,36);scrollbar.size=Vector2(16,600);scrollbar.page=16

func layout(view: Vector2) -> void:
	position=Vector2(368,48+fposmod(view.y,12)*0.5);size=Vector2(592,708)

func display(total: int, first := 0, header := 3, directions: Array = [true,true,true,true]) -> void:
	active_header=header;descending=directions.duplicate()
	if scrollbar!=null:scrollbar.set_rows(total,first)
	queue_redraw()

func strip(token: String, index: int) -> Texture2D:
	var key:=token+str(index)
	if not strips.has(key):strips[key]=world.ui_texture(token,index)
	return strips[key]

func patch(token: String, origin: Vector2i, columns: int, rows: int, source: Texture2D=null) -> void:
	var texture: Texture2D=source if source!=null else art.texture(token)
	if texture==null:return
	for y in rows:
		for x in columns:
			draw_texture_rect_region(texture,Rect2((origin.x+x)*8,(origin.y+y)*12,8,12),Rect2((0 if x==0 else 16 if x==columns-1 else 8),(0 if y==0 else 24 if y==rows-1 else 12),8,12))

func _draw() -> void:
	if world==null:return
	# The native rendered right edge is cell119, although the widget rect ends117.
	patch("HOVER_RECTANGLE",Vector2i.ZERO,74,59)
	for header in 4:
		var suffix: String="ACTIVE" if header==active_header else "INACTIVE"
		# Each native header retains its direction when another header is selected.
		var direction: String="DESCENDING" if descending[header] else "ASCENDING"
		for x in 4:
			var arrow:=strip("SORT_"+direction+"_"+suffix,x)
			if arrow!=null:draw_texture_rect(arrow,Rect2((HEADER_X[header]+x)*8,12,8,12),false)
		if HEADERS[header].is_empty():continue
		var width: int=HEADER_WIDTH[header]-4
		for x in width:
			var background:=strip("SORT_TEXT_"+suffix,0 if x==0 else 2 if x==width-1 else 1)
			if background!=null:draw_texture_rect(background,Rect2((HEADER_X[header]+4+x)*8,12,8,12),false)
		var font: Font=theme.default_font
		if font!=null:font.draw_string(get_canvas_item(),Vector2((HEADER_X[header]+5)*8,24),HEADERS[header],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.BLACK if header==active_header else Color8(160,160,160))
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			for x in 39:
				var source_x:=0 if x==0 else x-33 if x>=35 else 1
				draw_texture_rect_region(filter,Rect2((3+x)*8,(55+y)*12,8,12),Rect2(source_x*8,y*12,8,12))
