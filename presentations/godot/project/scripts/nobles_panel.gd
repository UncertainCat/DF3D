extends Node
# Staged owner. Public entry remains gated until the full native workflow passes.
signal information_requested(caption: String)
var ui_host
var modal_input:=true
var play_enabled:=true
var panel
var name_panel
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
	panel.symbol_requested.connect(func(row):
		if allowed():state.begin_symbols(state.office(row)))
	name_panel=preload("res://scripts/location_name_view.gd").new();layer.add_child(name_panel)
	name_panel.heading="Name the symbol";name_panel.configure(world,state.symbols.naming)
	name_panel.input_allowed=allowed;name_panel.cancelled.connect(handle_back)
	panel.accounting_requested.connect(func(row,setting):
		if allowed():state.set_accounting(state.office(row),setting))
	panel.information_requested.connect(func(caption):
		if allowed():request_handoff(func():information_requested.emit(caption)))
	host.register(self);_layout();_sync()
func allowed() -> bool:
	if state.phase==state.Phase.Symbols and state.symbols.busy():
		if state.symbols.phase!=state.symbols.Phase.Naming or state.symbols.naming.phase!=state.symbols.naming.Phase.Reading:return false
	return play_enabled and ui_host!=null and ui_host.allows_panel_input(self) and state.phase not in [state.Phase.Applying,state.Phase.Accounting,state.Phase.Unknown]
func open_panel() -> void:
	if state.phase==state.Phase.Symbols:return
	if state.phase in [state.Phase.Applying,state.Phase.Accounting]:return
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
	if state.phase==state.Phase.Symbols:state.cancel_symbols_for_handoff()
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
	var naming: bool=state.phase==state.Phase.Symbols and not state.symbols.step.is_empty()
	if panel!=null:panel.visible=opened and not naming
	if name_panel!=null:name_panel.visible=opened and naming
	if not opened and not opening and ui_host!=null:ui_host.release(self)
	if state.phase in [state.Phase.Rejected,state.Phase.Unknown,state.Phase.Unavailable]:_destination=Callable()
func _layout() -> void:
	if panel==null:return
	var extent:=get_viewport().get_visible_rect().size
	var scale:=preload("res://scripts/presentation_settings.gd").effective_scale_vector(extent)
	panel.scale=scale;layout_size=extent;panel.layout(extent/scale)
	if name_panel!=null:
		var view:=extent/scale;name_panel.scale=scale
		name_panel.layout_frame(Vector2(16,36+fposmod(view.y,12)*0.5),Vector2(floori(view.x/8)*8-224,floori(view.y/12)*12-60))
func _process(_delta: float) -> void:
	if panel!=null and (panel.visible or (name_panel!=null and name_panel.visible)) and (layout_size!=get_viewport().get_visible_rect().size or panel.scale!=preload("res://scripts/presentation_settings.gd").effective_scale_vector(layout_size)):_layout()
func _exit_tree() -> void:
	_destination=Callable();state.dispose()
