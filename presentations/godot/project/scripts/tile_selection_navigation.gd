extends RefCounted
# Selection survives only its own confirmed detail-panel handoffs. Detail
# controllers retain their action ownership; this object owns navigation only.
var state=preload("res://scripts/tile_selection_state.gd").new()
var host
var destination: Callable
var owner: WeakRef
var handing_off:=false

func configure(service,source,route: Callable) -> void:
	dispose();host=source;destination=route;state.configure(service)
	host.panel_activated.connect(_activated)
	host.panel_released.connect(_released)
	host.views_reset.connect(close)
	state.selected.connect(_selected)

func open(tile: Vector3i) -> void:
	if host==null or not host.play_enabled or host.overlay_blocked:return
	owner=weakref(host.active) if is_instance_valid(host.active) else null
	state.open(tile)

func close() -> void:
	owner=null;state.close()

func _selected(kind: int,id: int,tile: Vector3i) -> void:
	if host==null or not host.play_enabled or host.overlay_blocked or not destination.is_valid():close();return
	# The route returns the controller only after synchronously acquiring the
	# host. A refused/asynchronous handoff must not retain selection authority.
	handing_off=true
	var next=destination.call(kind,id,tile)
	handing_off=false
	if not is_instance_valid(next) or host.active!=next:close();return
	owner=weakref(next)

func _activated(_controller: Node) -> void:
	if not handing_off:close()

func _released(controller: Node) -> void:
	if not handing_off and owner!=null and owner.get_ref()==controller:close()

func dispose() -> void:
	if host!=null:
		if host.panel_activated.is_connected(_activated):host.panel_activated.disconnect(_activated)
		if host.panel_released.is_connected(_released):host.panel_released.disconnect(_released)
		if host.views_reset.is_connected(close):host.views_reset.disconnect(close)
	if state.selected.is_connected(_selected):state.selected.disconnect(_selected)
	state.dispose();owner=null;host=null;destination=Callable()
