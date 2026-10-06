extends Control
# Unexposed native confirmation component. Session ownership belongs to caller.
# Exact copy/layout: native_options_confirmations.json, protected074236/080920.
signal confirmed(token: String)
signal cancelled
const PROMPTS := {
	"RETIRE_FORTRESS": ["Retire", ["Really retire?  The world will be saved but", "you will need to unretire the fort to play", "here again."]],
	"ABANDON_FORTRESS": ["Abandon", ["Really quit?  The fort will be saved but", "you will need to reclaim the fort to play", "here again."]],
	"QUIT_WITHOUT_SAVING": ["Quit", ["Really quit without saving?", "All of your progress since the last", "save will be lost."]],
	"SAVE_OVERWRITE": ["Save", ["There is a folder with this name already.", "Would you like to overwrite it?"]],
}
var art=preload("res://scripts/original_ui.gd").new()
var token:=""
var input_allowed:Callable
func configure(source) -> void:
	art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	if is_inside_tree() and not get_viewport().size_changed.is_connected(layout_reference):
		get_viewport().size_changed.connect(layout_reference)
	hide()
func display(value:String) -> void:
	token=value if PROMPTS.has(value) else ""
	visible=not token.is_empty();queue_redraw()
func layout_reference() -> void:
	if not is_inside_tree():return
	# Native whole-cell placement, verified at960x600,1200x800 and1600x900.
	var viewport:=get_viewport_rect().size
	var columns:=int(viewport.x/8)
	var rows:=int(viewport.y/12)
	position=Vector2(floori((columns-63)/2.0)*8+floori(fposmod(viewport.x,8)/2),
		floori((rows-8)/2.0)*12+floori(fposmod(viewport.y,12)/2))
	size=Vector2(504,120)
func accepts_input() -> bool:
	return is_visible_in_tree() and not token.is_empty() and (not input_allowed.is_valid() or input_allowed.call())
func _input(event:InputEvent) -> void:
	if not accepts_input():return
	# Protected physical Windows captures074713/074822/080920: neither Escape nor
	# right-click cancels or confirms. Consume them before underlying owners.
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
func _gui_input(event:InputEvent) -> void:
	if not accepts_input():return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var width:int=(PROMPTS[token][0].length()+4)*8
		if Rect2(16,72,width,36).has_point(event.position):accept_event();confirmed.emit(token)
		elif Rect2(408,72,80,36).has_point(event.position):accept_event();cancelled.emit()
func patch(name:String,origin:Vector2i,columns:int,rows:int) -> void:
	var texture:Texture2D=art.texture(name)
	if texture==null:return
	for y in rows:
		for x in columns:
			draw_texture_rect_region(texture,Rect2((origin.x+x)*8,(origin.y+y)*12,8,12),Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else 24 if y==rows-1 else 12,8,12))
func _draw() -> void:
	if token.is_empty():return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,63,10)
	patch("HORIZONTAL_OPTION_REMOVE",Vector2i(2,6),PROMPTS[token][0].length()+4,3)
	patch("HORIZONTAL_OPTION_REMOVE",Vector2i(51,6),10,3)
	if theme.default_font==null:return
	var font:Font=theme.default_font
	for line in PROMPTS[token][1].size():font.draw_string(get_canvas_item(),Vector2(16,(3+line)*12),PROMPTS[token][1][line],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	font.draw_string(get_canvas_item(),Vector2(32,96),PROMPTS[token][0],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	font.draw_string(get_canvas_item(),Vector2(424,96),"Cancel",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
