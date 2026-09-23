extends Node
# Composition of accepted UI only. The host owns input; actions outlive views.
const Registry = preload("res://scripts/ui_availability.gd")
var view
var world
var host
var actions
var controllers := {}
var session_timer := 0.0

func setup(owner, audio_panel, original_ui) -> void:
	view = owner
	world = view.world
	host = preload("res://scripts/ui_host.gd").new()
	host.interaction = view._interaction
	add_child(host)
	actions = preload("res://scripts/semantic_action_service.gd").new()
	actions.configure(world)
	add_child(actions)
	actions.session_changed.connect(host.reset_local_views)
	view._interaction.selection_panel = self
	if view._fixture == "":
		view._loader = preload("res://scripts/fort_loader.gd").new()
		view._loader.world = world
		view._loader.audio = view._audio
		add_child(view._loader)
		view._loader.load_art(world.assets_root())
		original_ui.apply(view._loader)
		view._session_controls = preload("res://scripts/session_controls.gd").new()
		view._session_controls.world = world
		view._session_controls.audio = view._audio
		add_child(view._session_controls)
		original_ui.apply(view._session_controls)
	view._fortress_hud = preload("res://scripts/fortress_hud.gd").new()
	var hud = view._fortress_hud
	hud.world = world
	hud.interaction = view._interaction
	hud.camera_rig = view.camera_rig
	hud.session_controls = view._session_controls
	hud.audio_panel = audio_panel
	hud.ui_host = host
	add_child(hud)
	hud.panel_requested.connect(open_destination)
	hud.info_requested.connect(func(destination): open_destination(preload("res://scripts/native_info_frame.gd").destination(destination)))
	hud.recovery_requested.connect(host.reset_local_views)
	host.views_reset.connect(hud.close_menus)
	hud.level_step_requested.connect(view._step_top_z)
	var elevation = preload("res://scripts/elevation_overview.gd").new()
	elevation.world = world
	elevation.hud = hud
	elevation.camera_rig = view.camera_rig
	hud.root_control.add_child(elevation)
	elevation.level_requested.connect(func(level):
		view._interaction.cancel_selection()
		view._step_top_z(level-world.get_top_z()))
	var hover = preload("res://scripts/tile_hover.gd").new()
	hover.world = world
	hover.hud = hud
	hover.camera = view.camera_rig.get_node("Camera3D")
	add_child(hover)
	view._interaction.enable_shell()
	audio_panel.launcher.hide()
	if view._loader != null: view._set_play_enabled(false)

func controller(id: String):
	if not Registry.PANEL_SCRIPTS.has(id): return null
	if controllers.has(id): return controllers[id]
	var panel = load(Registry.PANEL_SCRIPTS[id]).new()
	panel.world = world
	panel.interaction = view._interaction
	panel.ui_host = host
	if id in ["construction", "areas"]:
		panel.action_service = actions
		panel.camera = view.camera_rig.get_node("Camera3D")
	add_child(panel)
	host.register(panel)
	controllers[id] = panel
	if id == "readouts":
		panel.info_frame.destination_requested.connect(open_destination)
		panel.focus_requested.connect(focus_tile)
		panel.inspect_requested.connect(func(unit_id):
			var target: Dictionary = world.inspect_entity(1,unit_id)
			if target.is_empty():
				panel.message.text = "This resident is no longer available."
				return
			open_target(target.tile,1,unit_id))
	return panel

func open_destination(destination: String) -> void:
	destination = Registry.READ_LAUNCHERS.get(destination,destination)
	if not Registry.PANEL_ROUTES.has(destination) or not host.play_enabled: return
	var panel = controller(Registry.PANEL_ROUTES[destination])
	if panel.has_method("set_info_page"): panel.set_info_page(destination)
	panel.open_panel()

func open_target(tile: Vector3i, kind: int, id: int) -> void:
	if host.play_enabled: controller("inspector").open_target(tile,kind,id)

func close_panel() -> void:
	if controllers.has("inspector"): controllers.inspector.close_panel()

func is_open() -> bool:
	return controllers.has("inspector") and controllers.inspector.is_open()

func focus_tile(tile: Vector3i) -> void:
	world.set_top_z(tile.z)
	view.camera_rig.focus_on(Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5),view.camera_rig.current_distance())

# Session UI is global. Rendering only needs the resulting attachment/input gates.
func update_session(delta: float) -> bool:
	if view._loader == null: return true
	session_timer -= delta
	if session_timer <= 0:
		session_timer = 0.25
		view._session_state = world.poll_session()
	view._loader.update_session(view._session_state, view._fort_ready(), world.last_error())
	view._session_controls.update_session(view._session_state, view._loader.entered)
	if view._release_close != null: view._release_close.update_session(view._session_state)
	view._set_play_enabled(view._loader.entered and not view._session_controls.blocks_commands(), view._loader.entered)
	view._audio.set_menu(not view._loader.entered)
	return view._loader.can_attach

func update_controls(enabled: bool, keep_map: bool) -> void:
	if view._session_controls != null:
		if not view._fortress_hud.menu_open() or view._interaction.construction_active or not (enabled or keep_map):
			view._session_controls.panel.hide()
	view._fortress_hud.update_state(enabled, enabled or keep_map, view._session_state)
