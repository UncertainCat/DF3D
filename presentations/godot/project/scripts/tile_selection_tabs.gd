extends Control
# Native side tabs; the selection owner supplies ordered identities and icons.
# This staged view does not collect candidates or open detail sheets itself.
signal alternative_requested(index: int)
const C=preload("res://scripts/management_contract.gd")
var art=preload("res://scripts/original_ui.gd").new()
var alternatives: Array=[]
var icons: Array=[]
var selected: int=-1
var enabled:=false
var input_allowed: Callable
var inactive: Array[Texture2D]=[]

func configure(source) -> void:
	art.configure(source)
	for row in 3:inactive.append(source.ui_texture("HOVER_TAB_INACTIVE",row))
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
	hide()

func set_selection(snapshot: Dictionary,images: Array=[]) -> void:
	alternatives=snapshot.get("alternatives",[]).duplicate(true)
	icons=images.duplicate();selected=-1
	for index in alternatives.size():
		var target: Dictionary=alternatives[index]
		if target.kind==snapshot.get("kind",C.SelectionKind.None) and target.id==snapshot.get("id",-1):selected=index
	# A selected group member has no selected tab in native DF.
	size=Vector2(40,36*alternatives.size())
	visible=snapshot.get("open",false) and not alternatives.is_empty()
	queue_redraw()

func layout(sheet_position: Vector2) -> void:
	position=sheet_position+Vector2(480,0)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	if enabled and (not input_allowed.is_valid() or input_allowed.call()):
		var index:=floori(event.position.y/36)
		if index>=0 and index<alternatives.size() and event.position.x>=8:
			alternative_requested.emit(index)
	accept_event()

func cell(token: String,source: Vector2i,target: Vector2i) -> void:
	var texture: Texture2D=art.texture(token)
	if texture!=null:draw_texture_rect_region(texture,Rect2(Vector2(target)*Vector2(8,12),Vector2(8,12)),Rect2(Vector2(source)*Vector2(8,12),Vector2(8,12)))

func _draw() -> void:
	for index in alternatives.size():
		for y in 3:
			var row:=index*3+y
			if index==selected:
				if y==0 and index>0:cell("HOVER_TAB_INSIDE_CORNER_TOP",Vector2i.ZERO,Vector2i(0,row))
				elif y==2:cell("HOVER_TAB_INSIDE_CORNER_BOTTOM",Vector2i.ZERO,Vector2i(0,row))
				else:cell("HOVER_RECTANGLE",Vector2i(1,0 if index==0 and y==0 else 1),Vector2i(0,row))
				for x in range(1,5):cell("HOVER_TAB",Vector2i(0 if x==1 else 2 if x==4 else 1,y),Vector2i(x,row))
			else:
				cell("HOVER_RECTANGLE",Vector2i(2,0 if index==0 and y==0 else 1),Vector2i(0,row))
				if inactive[y]!=null:draw_texture(inactive[y],Vector2(8,row*12))
				for x in range(2,5):cell("HOVER_RECTANGLE",Vector2i(2 if x==4 else 1,y),Vector2i(x,row))
		if index<icons.size() and icons[index]!=null:draw_texture_rect(icons[index],Rect2(10,index*36+2,32,32),false)
