extends Control
# Native153273: portrait, white species name, and raw species description.
const C=preload("res://scripts/management_contract.gd")
var art=preload("res://scripts/original_ui.gd").new()
var state
var world
var title:=""
var lines: Array[String]=[]
var portrait: Texture2D
var receipt:=0

func configure(source,model) -> void:
	world=source;state=model;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	state.changed.connect(refresh);layout(708);refresh()

func layout(height: float) -> void:
	size=Vector2(488,height);queue_redraw()

func refresh() -> void:
	visible=state.snapshot.get("open",false) and state.snapshot.get("kind",0)==C.SelectionKind.Vermin
	var next: int=state.snapshot.get("receipt",0)
	if next!=receipt:
		receipt=next;portrait=null
		if visible and state.snapshot.has("portrait"):portrait=world.item_portrait_icon(state.snapshot.portrait)
	title=state.snapshot.get("title","");lines.clear()
	var remaining: String=state.snapshot.get("description","") if visible else ""
	while not remaining.is_empty():
		var count:=remaining.length()
		if count>56:
			count=remaining.left(56).rfind(" ")
			if count<=0:count=56
		lines.append(remaining.left(count));remaining=remaining.substr(count)
		while remaining.begins_with(" "):remaining=remaining.substr(1)
	queue_redraw()

func _draw() -> void:
	if portrait!=null:draw_texture_rect(portrait,Rect2(8,12,96,96),false)
	if theme.default_font==null:return
	var caption:=title
	if caption.length()>=38:caption=caption.left(34)+"..."
	theme.default_font.draw_string(get_canvas_item(),Vector2(112,36),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	for i in lines.size():
		theme.default_font.draw_string(get_canvas_item(),Vector2(16,132+i*12),lines[i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
