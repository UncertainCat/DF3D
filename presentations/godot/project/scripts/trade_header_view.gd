extends Control
# Staged native header. Dialogue lines are supplied by DF's owned wrapping
# provider; this component does not compose dialogue or infer merchant mood.
var world
var art=preload("res://scripts/original_ui.gd").new()
var colors: Array[Color]=[]
var facts: Dictionary={}
var speaker: Texture2D
func configure_header(source) -> void:
	world=source;art.configure(source);theme=art.theme
	colors=art.installed_palette(source.assets_root())
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_IGNORE
func set_header(value: Dictionary) -> void:
	facts=value.duplicate(true);speaker=null
	if facts.has("appearance"):speaker=world.candidate_icon(facts.appearance)
	queue_redraw()
func layout(panel_size: Vector2) -> void:
	size=Vector2(panel_size.x-16,72);queue_redraw()
func text(value: String,point: Vector2,color: int) -> void:
	if theme.default_font!=null and color>=0 and color<16:
		theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func _draw() -> void:
	if colors.size()!=16:return
	draw_rect(Rect2(Vector2.ZERO,size),Color8(28,28,28))
	if facts.is_empty():return
	# The qualified32x32 merchant occupies32,32 in the native96x64 sheet.
	# Native drawing places that sheet at2,6 without stretching it. Other shapes need admission
	# before this staged component is connected to the public trade route.
	if speaker!=null and speaker.get_size()==Vector2(32,32):
		draw_texture_rect(speaker,Rect2(34,38,32,32),false)
	var color: Array=facts.get("name_color",[7,0,0])
	text(facts.get("name",""),Vector2(96,12),int(color[0])+8*int(color[2]))
	var lines: Array=facts.get("status",[])
	var ink: int=int(facts.get("status_color",7))
	if lines.is_empty():lines=facts.get("lines",[]);ink=14
	for i in lines.size():text(lines[i],Vector2(96,36+i*12),ink)
	text(facts.get("mood",""),Vector2(96,72),int(facts.get("mood_color",-1)))
