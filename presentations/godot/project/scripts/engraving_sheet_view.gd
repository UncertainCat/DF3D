extends Control
# Native engraving renderer1589ff: blue title and plain wrapped artwork prose.
const C=preload("res://scripts/management_contract.gd")
const Native=preload("res://scripts/native_creature_text.gd")
var art=preload("res://scripts/original_ui.gd").new()
var state
var scrollbar
var input_allowed: Callable
var title:=""
var lines: Array[String]=[]
var receipt:=0
var first:=0
var capacity:=0
func configure(world,model) -> void:
	state=model;art.configure(world);Native.load_text(world);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(scrollbar);scrollbar.configure(world)
	scrollbar.input_allowed=allowed;scrollbar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	state.changed.connect(refresh);layout(708);refresh()
func allowed() -> bool:
	return visible and state.phase==state.Phase.Ready and state.ticket==0 and (not input_allowed.is_valid() or input_allowed.call())
func layout(height: float) -> void:
	size=Vector2(488,height);capacity=maxi(0,floori((height-72)/12))
	scrollbar.position=Vector2(456,60);scrollbar.size=Vector2(16,capacity*12);scrollbar.page=capacity
	scrollbar.set_rows(lines.size(),first);scrollbar.visible=capacity>0 and lines.size()>capacity;queue_redraw()
func refresh() -> void:
	visible=state.snapshot.get("kind",0)==C.SelectionKind.Engraving
	var next: int=state.snapshot.get("receipt",0)
	if next!=receipt:first=0;receipt=next
	title=state.snapshot.get("title","");lines.clear()
	var remaining: String=state.snapshot.get("description","") if visible else ""
	while not remaining.is_empty():
		var count:=remaining.length()
		if count>55:
			count=remaining.left(55).rfind(" ")
			if count<=0:count=55
		lines.append(remaining.left(count));remaining=remaining.substr(count)
		while remaining.begins_with(" "):remaining=remaining.substr(1)
	layout(size.y)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		first=clampi(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),0,maxi(0,lines.size()-capacity))
		scrollbar.set_rows(lines.size(),first);queue_redraw();accept_event()
func _draw() -> void:
	if theme.default_font==null:return
	theme.default_font.draw_string(get_canvas_item(),Vector2(16,36),title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Native.colors[9])
	var start:=clampi(first,0,maxi(0,lines.size()-capacity))
	for i in mini(capacity,lines.size()-start):
		theme.default_font.draw_string(get_canvas_item(),Vector2(16,72+i*12),lines[start+i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Native.colors[15])
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
