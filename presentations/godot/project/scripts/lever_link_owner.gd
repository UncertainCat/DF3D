extends Node
# Companion to a building panel. The panel retains focus and map projection;
# this owner retains the Link selection, asynchronous artwork and prompt.
signal changed
signal applied(operation: int,job_id: int)
signal mechanisms_unavailable
var state=preload("res://scripts/lever_state.gd").new()
var source_item=preload("res://scripts/item_sheet_state.gd").new()
var target_item=preload("res://scripts/item_sheet_state.gd").new()
var view
var targeting:=false
var input_allowed: Callable

func configure(world,service,parent: Node) -> void:
	state.configure(service);source_item.configure(service);target_item.configure(service)
	view=preload("res://scripts/lever_link_view.gd").new();parent.add_child(view)
	view.configure(world,state,"");view.hide()
	view.cancelled.connect(cancel)
	state.changed.connect(_state_changed)
	state.applied.connect(func(op,id):applied.emit(op,id))
	state.mechanisms_unavailable.connect(func():mechanisms_unavailable.emit())
	source_item.changed.connect(_art_changed);target_item.changed.connect(_art_changed)
func open(id: int,native_name: String) -> void:
	close();view.building_name=native_name;state.open(id)
func close() -> void:
	targeting=false;source_item.close();target_item.close();state.close()
	if view!=null:view.hide();view.set_items([])
func layout(origin: Vector2) -> void:
	if view!=null:view.position=origin
func allowed() -> bool:return not input_allowed.is_valid() or input_allowed.call()
func begin_link() -> void:
	if allowed():state.begin_link()
func pull() -> void:
	if allowed():state.pull()
func cancel() -> void:
	if allowed():state.cancel_link()
func hover_tile(tile: Vector3i) -> void:
	if allowed() and view!=null and view.visible:state.preview(tile)
func click_tile(tile: Vector3i) -> void:
	if allowed() and view!=null and view.visible:state.click_target(tile)
func _state_changed() -> void:
	var mode: bool=state.phase in [state.Phase.Targeting,state.Phase.Previewing] or (state.phase==state.Phase.Applying and targeting) or (state.phase==state.Phase.Reading and state.pending_link)
	targeting=mode
	if not mode:
		source_item.close();target_item.close()
		if view!=null:view.hide();view.set_items([])
	elif state.phase!=state.Phase.Reading:
		var first: int=state.snapshot.get("source_mechanism",-1)
		var second: int=state.snapshot.get("target_mechanism",-1)
		if source_item.item_id!=first:source_item.open(first)
		if target_item.item_id!=second:target_item.open(second)
		_art_changed()
	changed.emit()
func _art_changed() -> void:
	if view==null:return
	var ready: bool=targeting and source_item.phase==source_item.Phase.Ready and target_item.phase==target_item.Phase.Ready and source_item.item_id==state.snapshot.get("source_mechanism",-1) and target_item.item_id==state.snapshot.get("target_mechanism",-1)
	view.visible=ready
	view.set_items([source_item.snapshot,target_item.snapshot] if ready else [])
func _process(_delta: float) -> void:
	if view!=null and view.visible and not view.ready_art():view.refresh()
func _exit_tree() -> void:
	state.dispose();source_item.dispose();target_item.dispose()
	if is_instance_valid(view):view.queue_free()
