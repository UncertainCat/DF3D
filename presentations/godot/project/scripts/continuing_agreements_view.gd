extends Control
# Native3f6834 sizing and3f9956 row rendering. Rows already carry DF's text/order.
var art=preload("res://scripts/original_ui.gd").new()
var rows: Array=[]
var available_rows:=0
var displayed_rows:=0

func configure(source) -> void:
	art.configure(source);theme=art.theme
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	hide()

func layout(view: Vector2) -> void:
	position=Vector2((floori(view.x/8)-28)*8+floorf(fposmod(view.x,8)*0.5),216+floorf(fposmod(view.y,12)*0.5))
	available_rows=maxi(0,floori((floori(view.y/12)-22)/4.0))
	_refresh()

func display(value: Array) -> void:
	rows=value.duplicate(true);_refresh()

func _refresh() -> void:
	displayed_rows=mini(rows.size(),available_rows)
	size=Vector2(208,(displayed_rows*4+1)*12)
	visible=not rows.is_empty();queue_redraw()

static func shortened(text: String) -> String:
	# Right-left=25. Native compares length with23, resizes to22, replaces last3.
	return text.substr(0,19)+"..." if text.length()>=23 else text

func row_at(point: Vector2) -> Dictionary:
	# Native hit region includes the frame's X extent and the three text rows,
	# including unsupported applicant slots; separator rows have no target.
	var cell:=Vector2i(floori(point.x/8),floori(point.y/12))
	if cell.x<0 or cell.x>25 or cell.y<1:return {}
	var index:=int((cell.y-1)/4)
	if index>=displayed_rows or (cell.y-1)%4==3:return {}
	return rows[index].duplicate(true)

func _draw() -> void:
	if rows.is_empty():return
	var frame: Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null or theme.default_font==null:return
	var height:=displayed_rows*4+1
	for y in height:
		for x in 26:
			var origin:=Vector2(0 if x==0 else (16 if x==25 else 8),0 if y==0 else (24 if y==height-1 else 12))
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(origin,Vector2(8,12)))
	for i in displayed_rows:
		for j in 3:
			var field: String=["heading","applicant","date"][j]
			var color: int=[11,14,7][j]
			theme.default_font.draw_string(get_canvas_item(),Vector2(16,(i*4+j+2)*12),shortened(str(rows[i][field])),HORIZONTAL_ALIGNMENT_LEFT,-1,12,art.world.ui_palette_color(color))
