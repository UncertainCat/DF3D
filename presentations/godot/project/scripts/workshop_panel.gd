extends "res://scripts/farm_panel.gd"
# Staged workshop owner; the caller supplies the installed subtype icon.
signal unit_requested(id: int)
var workers=preload("res://scripts/workshop_workers_state.gd").new()
var candidate_modes=preload("res://scripts/workshop_candidate_modes.gd").new()
var refreshing_modes:=false
var selector
var tasks=preload("res://scripts/workshop_tasks_state.gd").new()

func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()

func configure(world,service,host,help=null) -> void:
	tasks.configure(service);workers.configure(service);candidate_modes.configure(service)
	candidate_modes.applied.connect(func():refreshing_modes=true;candidate_modes.clear();workers.refresh())
	super.configure(world,service,host,help)
	panel.configure_tasks(world,tasks,"")
	panel.configure_workers(world,workers)
	selector=preload("res://scripts/workshop_candidates_view.gd").new();canvas.add_child(selector);selector.configure(world);selector.extra_columns=2;selector.responsive_height=true;selector.configure_modes(candidate_modes,help);selector.hide()
	selector.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self) and workers.phase==workers.Phase.Ready and not candidate_modes.applying
	selector.cancelled.connect(_close_picker)
	selector.unit_chosen.connect(func(id):
		if workers.phase==workers.Phase.Ready:_close_picker();workers.select_worker(id))
	panel.workers.choose_requested.connect(_open_picker)
	panel.workers.unit_requested.connect(func(id):unit_requested.emit(id))
	panel.tab_requested.connect(_select_tab)
	panel.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self) and not selector.visible
	workers.changed.connect(_workers_changed)
	workers.applied.connect(state.refresh)
	workers.applied.connect(contents.refresh)
	tasks.applied.connect(state.refresh)
	tasks.applied.connect(contents.refresh)

func _create_view():return preload("res://scripts/workshop_sheet_view.gd").new()
func _open_state(id: int,_season: int) -> void:
	_close_picker();workers.close();tasks.close();panel.selected_tab=0;state.open(id)
func _contents_supported() -> bool:return true

func open_workshop(id: int,icon: String) -> void:
	if panel==null:return
	panel.building_icon=icon;open_target(id)

func _state_changed() -> void:
	super._state_changed()
	if opening:return
	if state.building_id<0 or state.snapshot.get("removing",false):
		_close_picker();workers.close();tasks.close()
	elif not state.snapshot.is_empty() and tasks.building_id!=state.building_id:tasks.open(state.building_id)

func close_panel() -> void:
	_close_picker();workers.close();tasks.close();super.close_panel()

func _exit_tree() -> void:
	candidate_modes.dispose();workers.dispose();tasks.dispose();super._exit_tree()

func _select_tab(index: int) -> void:
	if index not in [0,1] or not panel.tasks_allowed() or tasks.phase==tasks.Phase.Applying:return
	_close_picker();panel.tasks.choose_mode(false);panel.selected_tab=index
	if index==1 and workers.building_id!=state.building_id:workers.open(state.building_id)
	panel.refresh()
func _open_picker() -> void:
	if workers.phase!=workers.Phase.Ready or not panel.tasks_allowed():return
	selector.active_header=1;selector.display_rows(workers.rows);selector.actions_enabled=true;selector.show();selector.update_icons()
func _close_picker() -> void:
	refreshing_modes=false;candidate_modes.clear()
	if selector!=null:selector.hide();selector.actions_enabled=false;selector.display_rows([])
func _workers_changed() -> void:
	if refreshing_modes and selector!=null and selector.visible:
		if workers.phase==workers.Phase.Ready:
			refreshing_modes=false;selector.display_rows(workers.rows,selector.first,selector.selected)
		elif workers.phase!=workers.Phase.Reading:_close_picker()
		return
	if selector!=null and selector.visible and workers.phase!=workers.Phase.Ready:_close_picker()
func _process(delta: float) -> void:
	super._process(delta)
	if selector!=null:
		var viewport:=get_viewport().get_visible_rect().size
		var view:=viewport/Preferences.effective_scale_vector(viewport)
		selector.layout(view);selector.position=Vector2(32,48+fposmod(view.y,12)*0.5)
func _input(event: InputEvent) -> void:
	if selector!=null and selector.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			_close_picker();get_viewport().set_input_as_handled()
		return
	super._input(event)
func handle_escape() -> void:
	if selector!=null and selector.visible:_close_picker()
	else:super.handle_escape()
