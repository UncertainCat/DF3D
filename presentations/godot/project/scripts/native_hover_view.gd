extends Control
signal showing_changed(showing: bool)
const State=preload("res://scripts/native_hover_state.gd")
# Verbatim native204218 wrapping at the supported 24-cell minimap width.
const ACCESS_HELP = [
	["This option allows","visitors from outside","the fortress to enter","this location."],
	["This option allows","long-term residents of","the fortress to enter","this location."],
	["This option indicates","that the location is","only open to fortress","citizens."],
	["This option indicates","that the location is","only open to members."]]
var state=State.new()
var art=preload("res://scripts/original_ui.gd").new()
var displayed := ""

func configure(source) -> void:
	art.configure(source);theme=art.theme
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	size=Vector2(200,216);hide()

func enter_access(owner: int, mode: int) -> void:
	if mode in [0,1,2,3]: state.enter(owner,str(mode),Time.get_ticks_msec())
	_process(0)

func leave(owner: int) -> void:
	state.leave(owner,Time.get_ticks_msec());_process(0)

func reset() -> void:
	state.reset();_process(0)

func layout(view: Vector2) -> void:
	position=Vector2(view.x-200,fposmod(view.y,12)*0.5)

func _process(_delta: float) -> void:
	var next: String=state.advance(Time.get_ticks_msec())
	if next==displayed: return
	displayed=next;visible=not displayed.is_empty();queue_redraw();showing_changed.emit(visible)

func _draw() -> void:
	if displayed.is_empty(): return
	var frame: Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null or theme.default_font==null: return
	# Native minimap frame clips its top and right borders at the screen edge.
	# Left/middle cells repeat for17 rows; row17 is the existing bottom border.
	for y in 18:
		for x in 25:
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 8,24 if y==17 else 12,8,12))
	var lines: Array=ACCESS_HELP[int(displayed)]
	for row in lines.size():
		theme.default_font.draw_string(get_canvas_item(),Vector2(8,(row+1)*12),lines[row],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
