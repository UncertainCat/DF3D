extends Control
# Native17b552..17bc55: six-cell summary, saved squad banner and current order.
# All text is supplied by the bridge; truncation follows the local viewport.
const NativeText=preload("res://scripts/native_creature_text.gd")
var art=preload("res://scripts/original_ui.gd").new()
var symbols=preload("res://scripts/native_squad_symbol.gd").new()
var world
var row: Dictionary={}
var banner: Texture2D

func fact(key: String,fallback=null):
	for value in row.get("facts",[]):
		if value.key==key:return value.number if value.has_number else value.text
	return fallback

func configure(source) -> void:
	world=source;art.configure(source);symbols.configure(source);theme=art.theme
	NativeText.load_text(source);texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	resized.connect(queue_redraw)

func present(records: Array) -> void:
	row=records[0] if not records.is_empty() else {}
	banner=null
	if not row.is_empty() and int(row.get("id",-1))>=0:
		banner=symbols.texture({"index":int(fact("symbol",-1)),
			"foreground":[int(fact("foreground_r",0)),int(fact("foreground_g",0)),int(fact("foreground_b",0))],
			"background":[int(fact("background_r",0)),int(fact("background_g",0)),int(fact("background_b",0))]})
	queue_redraw()

func clipped(text: String,columns: int) -> String:
	if text.length()<columns:return text
	return text.left(maxi(0,columns-4))+"..." if columns>4 else text.left(maxi(0,columns-1))

func _draw() -> void:
	if world==null or theme.default_font==null or row.is_empty():return
	if int(row.get("id",-1))<0:
		theme.default_font.draw_string(get_canvas_item(),Vector2(8,24),str(row.get("name","")),HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[15]);return
	var texture: Texture2D=art.texture("BUTTON_RECTANGLE")
	var columns:=maxi(0,int((size.x-16)/8))
	if texture!=null:
		for y in 6:
			for x in columns:
				draw_texture_rect_region(texture,Rect2(Vector2(8+x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else 24 if y==5 else 12,8,12))
	if banner!=null:draw_texture_rect(banner,Rect2(8,2,32,32),false)
	var available:=maxi(0,columns-7)
	var caption:=str(row.get("name",""))
	if caption.length()>=available:caption=str(fact("short_name",caption))
	theme.default_font.draw_string(get_canvas_item(),Vector2(64,24),clipped(caption,available),HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[15])
	theme.default_font.draw_string(get_canvas_item(),Vector2(64,60),clipped(str(fact("order","")),available),HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[clampi(int(fact("order_color",7)),0,15)])
