extends Control
# Native recognition primary row; state and eligibility come from DF.
const C=preload("res://scripts/management_contract.gd")
const GRAY=Color8(192,192,192)
const YELLOW=Color8(255,225,17)
var art=preload("res://scripts/original_ui.gd").new()
var workflow
var current: Dictionary={}
var actions_enabled:=true
var input_allowed: Callable
var action_requested: Callable

func configure(source,owner) -> void:
	workflow=owner;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP;size=Vector2(576,36)
	workflow.changed.connect(refresh);refresh()

func layout(view: Vector2) -> void:
	position=Vector2(384,192+fposmod(view.y,12)*0.5)
	size=Vector2(maxf(0,floorf(view.x/8)*8-624),36)

static func content(snapshot: Dictionary) -> Dictionary:
	var caption: String;var color:=GRAY;var action:=false
	match int(snapshot.get("state",-1)):
		C.LocationRecognitionState.NeedsTemple:caption="You can recognize a priesthood once this is a temple."
		C.LocationRecognitionState.NeedsComplex:caption="You can recognize a high priest when this is a temple complex."
		C.LocationRecognitionState.NeedsWorshippers:
			var high: bool=int(snapshot.get("rank",-1))==1
			var threshold=snapshot.get("high_priest_threshold" if high else "priest_threshold")
			if typeof(threshold)!=TYPE_INT:return {}
			caption=("High priest: " if high else "Priest: ")+str(threshold)+" worshippers needed";color=YELLOW
		C.LocationRecognitionState.RecognizePriesthood:caption="Recognize priesthood";action=true;color=Color.WHITE
		C.LocationRecognitionState.RecognizeHighPriest:caption="Recognize high priest";action=true;color=Color.WHITE
		_:return {}
	return {"caption":caption,"color":color,"action":action}

func refresh() -> void:
	current=content(workflow.recognition.snapshot);visible=not current.is_empty();queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if current.is_empty() or not current.action or not actions_enabled:return
	if input_allowed.is_valid() and not input_allowed.call():return
	if workflow.recognition.phase!=workflow.recognition.Phase.Ready:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and Rect2(0,0,248,36).has_point(event.position):
		accept_event()
		if action_requested.is_valid():action_requested.call()
		else:workflow.recognize()

func _draw() -> void:
	if current.is_empty() or theme==null or theme.default_font==null:return
	if current.action:
		var texture: Texture2D=art.texture("HORIZONTAL_OPTION_CONFIRM")
		if texture!=null:
			for y in 3:
				for x in 31:
					draw_texture_rect_region(texture,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 16 if x==30 else 8,y*12,8,12))
	theme.default_font.draw_string(get_canvas_item(),Vector2(16 if current.action else 0,24),current.caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,current.color)

func _exit_tree() -> void:
	if workflow!=null and workflow.changed.is_connected(refresh):workflow.changed.disconnect(refresh)
