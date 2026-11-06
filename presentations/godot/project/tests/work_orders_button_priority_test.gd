extends SceneTree
class State extends RefCounted:
	enum Phase {Ready}
	var phase:=Phase.Ready
	var first:=0
	var total:=11
	var native_state: Dictionary={}
	var rows: Dictionary={0:{"id":71,"workshop_id":-1,"position":0,"native_state":{"phase":0,"validation_required":false,"details_available":true}}}
	var removed: Array=[]
	func remove_order(id: int) -> void:removed.append(id)
var failed:=false
func check(value: bool,message: String) -> void:
	if not value:failed=true;push_error(message)
func click(view,point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=point;view._gui_input(event)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var state:=State.new()
	var view=preload("res://scripts/global_work_orders_view.gd").new();root.add_child(view);view.state=state;view.page_rows=10
	var conditions: Array=[];view.conditions_requested.connect(func(id,shop):conditions.append([id,shop]))
	for width in [912,1200]:
		view.size=Vector2(width-256,468)
		var buttons: Array=view.button_positions();var y: int=view.list_top()+18
		click(view,Vector2(buttons[5]+16,y))
		check(conditions.back()==[71,-1] and view.editing_id==-1,"Visible Conditions must open Conditions")
		var point:=Vector2(buttons[10]+16,y)
		check(view.hover_kind(point)=="remove","Visible Remove hover must not show workshop-limit help")
		click(view,point)
		check(state.removed.size()==conditions.size() and state.removed.back()==71 and view.editing_id==-1,"Visible Remove must not edit workshop limit")
		click(view,Vector2(buttons[7]+4,y))
		check(view.editing_id==71 and view.editing_limit,"Unobscured workshop-limit entry remains usable")
		view.finish_entry()
	view.free()
	if not failed:print("WORK_ORDERS_BUTTON_PRIORITY_PASS")
	quit(1 if failed else 0)
