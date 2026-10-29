extends Node
# Staged main-scene owner. Public building selection remains on the inspector
# until removal, external selectors and the full farm workflow are accepted.
const Preferences=preload("res://scripts/presentation_settings.gd")
var state=preload("res://scripts/farm_state.gd").new()
var contents=preload("res://scripts/building_contents_state.gd").new()
var ui_host
var panel
var canvas: CanvasLayer
var play_enabled:=true
var modal_input:=false
var opening:=false
var right_down:=false
var right_travel:=0.0

func configure(world,service,host,help=null) -> void:
	ui_host=host;state.configure(service);contents.configure(service)
	canvas=CanvasLayer.new();canvas.layer=5;add_child(canvas)
	panel=preload("res://scripts/farm_sheet_view.gd").new();canvas.add_child(panel);panel.configure(world,state,help,contents)
	panel.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self)
	state.changed.connect(_state_changed)
	state.applied.connect(contents.refresh)
	contents.applied.connect(state.refresh)
	ui_host.register(self);_process(0)

func open_target(id: int,season: int=-1) -> void:
	if not play_enabled or not ui_host.activate(self):return
	opening=true;contents.close();state.open(id,season);opening=false;_state_changed()

func _state_changed() -> void:
	if not opening and state.building_id>=0 and not state.snapshot.is_empty():
		if state.snapshot.get("removing",false):contents.close()
		elif contents.building_id!=state.building_id:contents.open(state.building_id)
	if not opening and state.building_id<0:
		# A tab/target replacement emits Closed before starting its next read.
		# Only a terminal closure may release this owner's input gate.
		_release_if_closed.call_deferred()

func _release_if_closed() -> void:
	if state.building_id<0:
		contents.close();panel.hide();ui_host.release(self);cancel_gesture()

func close_panel() -> void:
	contents.close();state.close();panel.finish_rename();panel.hide();ui_host.release(self);cancel_gesture()

func handle_escape() -> void:close_panel()
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value and panel!=null:close_panel()
func cancel_gesture() -> void:right_down=false;right_travel=0

func _process(_delta: float) -> void:
	if panel==null:return
	var viewport:=get_viewport().get_visible_rect().size
	var factor:=Preferences.effective_scale_vector(viewport)
	canvas.scale=factor;panel.layout(viewport/factor)

func _input(event: InputEvent) -> void:
	if panel==null or not panel.visible or not ui_host.allows_panel_input(self):return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_F10:return # Reserved for the host's view reset.
		if event.keycode==KEY_ESCAPE:
			close_panel();get_viewport().set_input_as_handled()
		elif panel.name_entry.editing:
			panel.feed_name_key(event);get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and right_down:right_travel+=event.relative.length()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed:right_down=true;right_travel=0
		else:
			var click:=right_down and right_travel<4;right_down=false
			if click:close_panel();get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	contents.dispose();state.dispose()
