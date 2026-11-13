extends "res://scripts/farm_panel.gd"
# Staged workshop owner; the caller supplies the installed subtype icon.
signal unit_requested(id: int)
signal information_requested(destination: String)
var workers=preload("res://scripts/workshop_workers_state.gd").new()
var candidate_modes=preload("res://scripts/workshop_candidate_modes.gd").new()
var refreshing_modes:=false
var selector
var tasks=preload("res://scripts/workshop_tasks_state.gd").new()
var orders=preload("res://scripts/workshop_orders_state.gd").new()
var order_choices=preload("res://scripts/workshop_order_picker_state.gd").new()
var order_picker
var conditions=preload("res://scripts/work_order_conditions_state.gd").new()
var conditions_view
var global_orders=preload("res://scripts/global_work_orders_state.gd").new()
var global_orders_view
var details=preload("res://scripts/work_order_details_state.gd").new()
var details_view
var global_orders_mode:=false
var job_details=preload("res://scripts/job_settings_state.gd").new()
var job_details_view

func _init() -> void:
	state=preload("res://scripts/building_header_state.gd").new()

func configure(world,service,host,help=null) -> void:
	tasks.configure(service);workers.configure(service);orders.configure(service);candidate_modes.configure(service);order_choices.configure(service)
	conditions.configure(service)
	global_orders.configure(service)
	global_orders.changed.connect(func():if global_orders_mode:_release_if_closed.call_deferred())
	details.configure(service)
	job_details.configure(service)
	candidate_modes.applied.connect(func():refreshing_modes=true;candidate_modes.clear();workers.refresh())
	super.configure(world,service,host,help)
	panel.configure_tasks(world,tasks,"")
	panel.configure_workers(world,workers)
	panel.configure_orders(world,orders,help)
	job_details_view=preload("res://scripts/work_order_details_view.gd").new();job_details_view.job_context=true;job_details_view.workshop_job_context=true;canvas.add_child(job_details_view)
	job_details_view.configure_details(world,job_details);job_details_view.hide()
	job_details_view.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self) and _job_details_open()
	job_details_view.cancelled.connect(_close_job_details)
	job_details.changed.connect(func():
		job_details_view.visible=_job_details_open()
		panel.visible=not _job_details_open() and state.building_id>=0)
	job_details.applied.connect(func():tasks.refresh();state.refresh();contents.refresh())
	panel.tasks.details_requested.connect(_open_job_details)
	panel.tasks.priority_requested.connect(func(id):
		if play_enabled and ui_host.allows_panel_input(self) and panel.tasks_allowed():tasks.toggle_priority(id))
	global_orders_view=preload("res://scripts/global_work_orders_view.gd").new();canvas.add_child(global_orders_view);global_orders_view.configure_orders(world,global_orders,help);global_orders_view.hide()
	global_orders_view.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self) and not conditions_view.visible and not details_view.visible and not _job_details_open()
	global_orders_view.cancelled.connect(_close_global_orders)
	global_orders_view.create_requested.connect(open_global_order_picker)
	global_orders_view.conditions_requested.connect(func(id,_workshop):global_orders_view.hide();conditions_view.open(-2,id))
	conditions_view=preload("res://scripts/work_order_conditions_view.gd").new();canvas.add_child(conditions_view);conditions_view.configure_conditions(world,conditions,help);conditions_view.hide()
	conditions_view.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self)
	conditions_view.cancelled.connect(_back_conditions)
	for view in [global_orders_view,conditions_view]:
		view.information_requested.connect(func(caption):
			if play_enabled and ui_host.allows_panel_input(self):information_requested.emit(caption))
	panel.orders.conditions_requested.connect(func(id):conditions_view.open(state.building_id,id))
	conditions.applied.connect(orders.refresh)
	details_view=preload("res://scripts/work_order_details_view.gd").new();canvas.add_child(details_view);details_view.configure_details(world,details);details_view.hide()
	details_view.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self)
	details_view.cancelled.connect(_back_details)
	details.applied.connect(_back_details)
	global_orders_view.details_requested.connect(func(id):global_orders_view.hide();details_view.open(-2,id))
	panel.orders.details_requested.connect(func(id):details_view.open(state.building_id,id))
	order_picker=preload("res://scripts/workshop_order_picker_view.gd").new();canvas.add_child(order_picker);order_picker.configure_picker(world,order_choices);order_picker.hide()
	order_picker.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self)
	order_picker.cancelled.connect(_back_order_picker)
	panel.orders.choose_requested.connect(func():
		if orders.phase==orders.Phase.Ready and orders.snapshot.get("manager_available",false):
			order_picker.open(state.building_id,state.snapshot.get("native_name",""),panel.building_icon))
	order_choices.created.connect(func(receipt):
		orders.refresh()
		if receipt.get("workshop_id",-1)==-1:global_orders.refresh();global_orders_view.show())
	selector=preload("res://scripts/workshop_candidates_view.gd").new();canvas.add_child(selector);selector.configure(world);selector.extra_columns=2;selector.responsive_height=true;selector.configure_modes(candidate_modes,help);selector.hide()
	selector.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self) and workers.phase==workers.Phase.Ready and not candidate_modes.applying
	selector.cancelled.connect(_close_picker)
	selector.unit_chosen.connect(func(id):
		if workers.phase==workers.Phase.Ready:_close_picker();workers.select_worker(id))
	panel.workers.choose_requested.connect(_open_picker)
	panel.workers.unit_requested.connect(func(id):unit_requested.emit(id))
	panel.tab_requested.connect(_select_tab)
	panel.input_allowed=func():return play_enabled and ui_host.allows_panel_input(self) and not selector.visible and not order_picker.visible and not conditions_view.visible and not global_orders_view.visible and not details_view.visible and not _job_details_open()
	workers.changed.connect(_workers_changed)
	workers.applied.connect(state.refresh)
	workers.applied.connect(contents.refresh)
	tasks.applied.connect(state.refresh)
	tasks.applied.connect(contents.refresh)

func _create_view():return preload("res://scripts/workshop_sheet_view.gd").new()
func _open_state(id: int,_season: int) -> void:
	_close_job_details()
	_close_conditions()
	_close_order_picker();_close_picker();workers.close();tasks.close();orders.close();panel.selected_tab=0;state.open(id)
func _contents_supported() -> bool:return true

func open_workshop(id: int,icon: String) -> void:
	if panel==null:return
	panel.building_icon=icon;open_target(id)

func _state_changed() -> void:
	if global_orders_mode:
		_release_if_closed.call_deferred();return
	super._state_changed()
	if opening:return
	if state.building_id<0 or state.snapshot.get("removing",false):
		_close_job_details()
		_close_conditions()
		_close_order_picker();_close_picker();workers.close();tasks.close();orders.close()
	elif not state.snapshot.is_empty() and tasks.building_id!=state.building_id:tasks.open(state.building_id)
	if _job_details_open():panel.hide()

func close_panel() -> void:
	_close_job_details()
	global_orders_mode=false
	_close_conditions()
	_close_order_picker();_close_picker();workers.close();tasks.close();orders.close();super.close_panel()

func _exit_tree() -> void:
	job_details.dispose()
	details.dispose()
	global_orders.dispose()
	conditions.dispose()
	order_choices.dispose();candidate_modes.dispose();workers.dispose();tasks.dispose();orders.dispose();super._exit_tree()

func _close_order_picker() -> void:
	order_choices.close()
	if order_picker!=null:order_picker.hide()

func open_global_order_picker() -> void:
	if global_orders.phase!=global_orders.Phase.Ready or not global_orders.native_state.get("manager_available",false):return
	global_orders_view.hide();order_picker.open(-2,"","")

func _back_order_picker() -> void:
	var global: bool=order_choices.building_id==-2
	_close_order_picker()
	if global:global_orders.refresh();global_orders_view.show()

func _close_conditions() -> void:
	details.close()
	if details_view!=null:details_view.hide()
	conditions.close()
	if conditions_view!=null:conditions_view.hide()
	global_orders.close()
	if global_orders_view!=null:global_orders_view.hide()

func _back_conditions() -> void:
	conditions.close();conditions_view.hide()
	global_orders.refresh();global_orders_view.show()

func _back_details() -> void:
	var global: bool=details.building_id==-2
	details.close();details_view.hide()
	if global:global_orders.refresh();global_orders_view.show()
	elif orders.building_id>=0:orders.refresh()

func _close_global_orders() -> void:
	global_orders.close();global_orders_view.hide()
	if global_orders_mode:
		global_orders_mode=false;ui_host.release(self);return
	if orders.building_id>=0:orders.refresh()

func open_global_orders() -> void:
	if not play_enabled:return
	close_panel()
	if not ui_host.activate(self):return
	global_orders_mode=true;global_orders_view.open()

func _release_if_closed() -> void:
	# A standalone global list has no selected workshop. Keep its owner while
	# navigating child panels; deferred checks also allow close/read transitions.
	if global_orders_mode:
		for model in [global_orders,conditions,details,order_choices]:
			if model.phase not in [model.Phase.Closed,model.Phase.Unavailable]:return
		global_orders_mode=false;ui_host.release(self);return
	super._release_if_closed()

func _select_tab(index: int) -> void:
	if index not in [0,1,2] or not panel.tasks_allowed() or tasks.phase==tasks.Phase.Applying:return
	_close_picker();panel.tasks.choose_mode(false);panel.selected_tab=index
	if index==1 and workers.building_id!=state.building_id:workers.open(state.building_id)
	if index==2:orders.open(state.building_id)
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
	if job_details_view!=null:
		var viewport:=get_viewport().get_visible_rect().size
		job_details_view.layout(viewport/Preferences.effective_scale_vector(viewport))
	if details_view!=null:
		var viewport:=get_viewport().get_visible_rect().size
		details_view.layout(viewport/Preferences.effective_scale_vector(viewport))
	if global_orders_view!=null:
		var viewport:=get_viewport().get_visible_rect().size
		global_orders_view.layout(viewport/Preferences.effective_scale_vector(viewport))
	if conditions_view!=null:
		var viewport:=get_viewport().get_visible_rect().size
		conditions_view.layout(viewport/Preferences.effective_scale_vector(viewport))
	if order_picker!=null:
		var viewport:=get_viewport().get_visible_rect().size
		order_picker.layout(viewport/Preferences.effective_scale_vector(viewport))
	if selector!=null:
		var viewport:=get_viewport().get_visible_rect().size
		var view:=viewport/Preferences.effective_scale_vector(viewport)
		selector.layout(view);selector.position=Vector2(32,48+fposmod(view.y,12)*0.5)
func _input(event: InputEvent) -> void:
	if _job_details_open():return
	if details_view!=null and details_view.visible:return
	if global_orders_view!=null and global_orders_view.visible:return
	if conditions_view!=null and conditions_view.visible:return
	if order_picker!=null and order_picker.visible:return
	if panel!=null and panel.selected_tab==2 and panel.orders.editing and event is InputEventKey:
		if play_enabled and ui_host.allows_panel_input(self):panel.orders.feed_key(event)
		get_viewport().set_input_as_handled();return
	if selector!=null and selector.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			_close_picker();get_viewport().set_input_as_handled()
		return
	super._input(event)
func handle_escape() -> void:
	if _job_details_open():job_details_view.back()
	elif details_view!=null and details_view.visible:details_view.back()
	elif conditions_view!=null and conditions_view.visible:_back_conditions()
	elif global_orders_view!=null and global_orders_view.visible:_close_global_orders()
	elif order_picker!=null and order_picker.visible:_back_order_picker()
	elif panel!=null and panel.orders.editing:panel.orders.finish_entry()
	elif selector!=null and selector.visible:_close_picker()
	else:super.handle_escape()

func _job_details_open() -> bool:
	return job_details.phase not in [job_details.Phase.Closed,job_details.Phase.Unavailable]

func _close_job_details() -> void:
	job_details.close()
	if job_details_view!=null:job_details_view.hide()

func _open_job_details(id: int) -> void:
	if _job_details_open() or not play_enabled or not ui_host.allows_panel_input(self) or not panel.tasks_allowed() or tasks.phase!=tasks.Phase.Ready:return
	for row in tasks.jobs():
		if row.id==id and row.editable:
			job_details.open(state.building_id,id);return
