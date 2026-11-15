extends SceneTree
# Native3a8eec/3a8f1a distinguish removing a restriction from assigning one.
# Exercise the actual owner's asynchronous picker lifetime around that boundary.
class Workers:
	extends RefCounted
	signal changed
	enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
	var phase=Phase.Ready
	var permitted_workers: Array=[42]
	var rows: Array=[{"unit_id":42},{"unit_id":43}]
	var requests: Array=[]
	func select_worker(id):requests.append(id);phase=Phase.Applying;changed.emit()
class Selector:
	extends Control
	var actions_enabled:=true
	var first:=3
	var selected:=42
	var rows: Array=[]
	func display_rows(value,offset=0,selection=-1):rows=value;first=offset;selected=selection
var failed:=false
func check(value: bool,message: String) -> void:
	if not value:failed=true;push_error(message)
func _initialize() -> void:
	var owner=preload("res://scripts/workshop_panel.gd").new()
	var workers=Workers.new();var selector=Selector.new()
	owner.workers=workers;owner.selector=selector
	workers.changed.connect(owner._workers_changed)
	owner._choose_worker(42)
	check(selector.visible and owner.retaining_worker_picker,"Removing restriction must retain picker while applying")
	owner._choose_worker(42)
	check(workers.requests==[42],"Pending removal must not submit duplicate input")
	workers.phase=Workers.Phase.Reading;workers.changed.emit()
	check(selector.visible,"Confirmed removal refresh must retain picker")
	workers.permitted_workers=[];workers.phase=Workers.Phase.Ready;workers.changed.emit()
	check(selector.visible and selector.first==3 and selector.selected==42 and selector.rows==workers.rows,"Refresh must preserve picker position and adopt current rows")
	owner._choose_worker(43)
	check(not selector.visible and workers.requests==[42,43],"Assigning new worker closes picker")
	selector.show();workers.phase=Workers.Phase.Ready;workers.permitted_workers=[42]
	owner._choose_worker(42);workers.phase=Workers.Phase.Unknown;workers.changed.emit()
	check(not selector.visible and not owner.retaining_worker_picker,"Unknown removal retires interactive picker")
	selector.show();workers.phase=Workers.Phase.Ready
	owner._choose_worker(42);owner._close_picker()
	workers.phase=Workers.Phase.Ready;workers.changed.emit()
	check(not selector.visible,"Late refresh cannot reopen cancelled picker")
	workers.changed.disconnect(owner._workers_changed);selector.free();owner.free()
	if not failed:print("WORKSHOP_WORKER_PICKER_PASS")
	quit(1 if failed else 0)
