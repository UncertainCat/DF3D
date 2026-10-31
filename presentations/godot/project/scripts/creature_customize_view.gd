extends Control
# Native15aa16..15b172: two three-row fields, repeated filter middle,
# four-column feather endcap. The owner supplies semantic captions and focus.
signal field_requested(profession: bool)
const Art=preload("res://scripts/original_ui.gd")
var art=Art.new()
var captions: Array[String]=["",""]
var labels: Array[Label]=[]
var input_allowed: Callable

func configure(source) -> void:
	art.configure(source);theme=art.theme
	size=Vector2(288,72);mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for index in 2:
		var label:=Label.new();label.position=Vector2(16,12+index*36)
		label.size=Vector2(248,12);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size",12)
		add_child(label);labels.append(label)
	queue_redraw()

func present(nickname: String,profession: String,color: Color) -> void:
	captions=[nickname,profession]
	for index in labels.size():
		labels[index].text=captions[index]
		labels[index].add_theme_color_override("font_color",color)

func field_rect(profession: bool) -> Rect2:
	return Rect2(0,36 if profession else 0,288,36)

func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for profession in [false,true]:
		if field_rect(profession).has_point(event.position):
			field_requested.emit(profession);accept_event();return

func _draw() -> void:
	var frame: Texture2D=art.texture("BUTTON_FILTER")
	var endcap: Texture2D=art.texture("BUTTON_FILTER_NAME")
	if frame==null or endcap==null:return
	for field in 2:
		for y in 3:
			for x in 32:
				draw_texture_rect_region(frame,Rect2(x*8,field*36+y*12,8,12),Rect2(0 if x==0 else 8,y*12,8,12))
		draw_texture_rect(endcap,Rect2(256,field*36,32,36),false)
