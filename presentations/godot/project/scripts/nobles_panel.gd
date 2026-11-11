extends Node
# Staged owner. Public entry remains gated until the full native workflow passes.
signal information_requested(caption: String)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var state=preload("res://scripts/nobles_state.gd").new()
var layout_size:=Vector2.ZERO
var opening:=false
var _destination: Callable
func _init() -> void:
	state.changed.connect(_sync)
	state.dismissed.connect(_dismissed)
func configure(world,service,host) -> void:
	ui_host=host;state.configure(service)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	panel=preload("res://scripts/nobles_view.gd").new();layer.add_child(panel)
	panel.configure_nobles(world,state);panel.input_allowed=allowed
	panel.cancelled.connect(handle_back)
	panel.information_requested.connect(func(caption):
		if allowed():request_handoff(func():information_requested.emit(caption)))
	host.register(self);_layout();_sync()
func allowed() -> bool:
	return play_enabled and ui_host!=null and ui_host.allows_panel_input(self) and state.phase not in [state.Phase.Applying,state.Phase.Unknown]
func open_panel() -> void:
	if state.phase==state.Phase.Applying:return
	if play_enabled and ui_host!=null and ui_host.activate(self):
		opening=true;_destination=Callable();state.open();opening=false;_sync()
# Explicit host reset/session teardown does not submit simulation mutations.
func close_panel() -> void:
	_destination=Callable();state.close()
func handle_back() -> void:
	if not allowed():return
	_destination=Callable();state.request_dismiss()
func request_handoff(completed: Callable) -> void:
	if not allowed() or _destination.is_valid():return
	if state.phase in [state.Phase.CandidatesReading,state.Phase.CandidatesReady]:state.cancel_appointment()
	if state.phase!=state.Phase.Ready:return
	_destination=completed;state.request_dismiss()
func _dismissed() -> void:
	var completed:=_destination;_destination=Callable()
	if completed.is_valid():completed.call()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:close_panel()
func _sync() -> void:
	var opened: bool=state.phase not in [state.Phase.Closed,state.Phase.Unavailable]
	if panel!=null:panel.visible=opened
	if not opened and not opening and ui_host!=null:ui_host.release(self)
	if state.phase in [state.Phase.Rejected,state.Phase.Unknown,state.Phase.Unavailable]:_destination=Callable()
func _layout() -> void:
	if panel==null:return
	var extent:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(extent)
	panel.scale=scale;layout_size=extent;panel.layout(extent/scale)
func _process(_delta: float) -> void:
	if panel!=null and panel.visible and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:
	_destination=Callable();state.dispose()
