extends Node
# Composition of registered UI; staged routes remain hidden by the registry.
# The host owns input; actions outlive views.
const Registry = preload("res://scripts/ui_availability.gd")
var view
var world
var host
var actions
var controllers := {}
var red_alert_dismissal
var session_timer := 0.0
var native_options
var native_options_session
var agreement_tracker
var tile_hover
var item_follow
var creature_follow
var tile_selection
var follow_frame: Array=[]

func setup(owner, audio_panel, original_ui) -> void:
	view = owner
	world = view.world
	host = preload("res://scripts/ui_host.gd").new()
	host.interaction = view._interaction
	add_child(host)
	actions = preload("res://scripts/semantic_action_service.gd").new()
	actions.configure(world,true)
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
	if view._fixture == "":
		var options_layer := CanvasLayer.new()
		options_layer.layer = 22
		add_child(options_layer)
		native_options = preload("res://scripts/native_options.gd").new()
		options_layer.add_child(native_options)
		native_options.configure(world)
		native_options.input_allowed = func(): return view._loader.entered
		native_options_session = preload("res://scripts/native_options_session.gd").new()
		add_child(native_options_session)
		native_options_session.configure(world,native_options)
		hud.native_options = native_options
		native_options.visibility_changed.connect(hud.sync_menu_gate)
		host.views_reset.connect(native_options.close)
	hud.exit_controller = view._release_close
	if hud.exit_controller != null:
		hud.exit_controller.confirmation.visibility_changed.connect(hud.sync_menu_gate)
	hud.exit_requested.connect(func():
		if view._release_close != null: view._release_close.request_close()
		else: view.get_tree().quit())
	hud.panel_requested.connect(open_destination)
	hud.notification_requested.connect(open_notification)
	hud.notification_dismissal_requested.connect(dismiss_notification)
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
	if Registry.TILE_HOVER_AVAILABLE:
		var hover = preload("res://scripts/tile_hover.gd").new()
		hover.name = "TileHover"
		hover.world = world
		hover.hud = hud
		hover.camera = view.camera_rig.get_node("Camera3D")
		hover.actions = actions
		add_child(hover)
		tile_hover=hover
	if view._fixture=="":ensure_agreement_tracker()
	view._interaction.enable_shell()
	audio_panel.launcher.hide()
	if view._loader != null: view._set_play_enabled(false)

# One owner per live main scene; fixture rendering has no live agreement source.
func ensure_agreement_tracker():
	if agreement_tracker!=null:return agreement_tracker
	agreement_tracker=preload("res://scripts/continuing_agreements_hud.gd").new()
	agreement_tracker.name="ContinuingAgreements"
	agreement_tracker.hud=view._fortress_hud
	agreement_tracker.configure(world,actions)
	add_child(agreement_tracker)
	if tile_hover!=null:
		move_child(agreement_tracker,tile_hover.get_index())
		agreement_tracker.hover_claim_changed.connect(tile_hover.set_obscured)
	return agreement_tracker

func open_building_holder(kind: int,id: int) -> void:
	if not host.play_enabled:return
	if kind in [4,15]:
		var target: Dictionary=world.inspect_entity(3,id)
		if target.get("building_kind",-1)==kind+1 and not target.get("complete",true):
			controller("pending_building").open_target(id)
			return
	if kind==4:controller("farm").open_target(id)
	elif kind==8:controller("door").open_target(id)
	elif kind==10:controller("chest").open_target(id)
	elif kind in [5,13]:
		# The item receipt supplies native type/ID; resident semantics supply the
		# subtype artwork. The opened header still obtains fresh action authority.
		if not host.play_enabled:return
		var target: Dictionary=world.inspect_entity(3,id)
		if target.get("building_kind",-1)!=(6 if kind==5 else 14) or not target.get("complete",false):return
		var mapping=preload("res://scripts/location_staff_indicators.gd")
		var icon: Dictionary=mapping.art_for({"kind":2 if kind==5 else 1,"subtype":target.get("subtype",-1),"custom_code":target.get("custom","")})
		if icon.is_empty() or icon.get("token","").is_empty():return
		var token: String=icon.token
		if not icon.get("fallback","").is_empty() and world.ui_texture(token)==null:token=icon.fallback
		controller("workshop").open_workshop(id,token)

func open_item_carrier(kind: int,id: int) -> void:
	if kind!=2 or not host.play_enabled:return
	var target: Dictionary=world.inspect_entity(1,id)
	if not target.is_empty():
		controller("inspector").creature_sheet.tab="Overview"
		open_target(target.tile,1,id)

func controller(id: String):
	if not Registry.PANEL_SCRIPTS.has(id): return null
	if controllers.has(id): return controllers[id]
	var panel = load(Registry.PANEL_SCRIPTS[id]).new()
	if id=="nobles":
		add_child(panel);panel.configure(world,actions,host)
		panel.information_available=func(caption):return caption in ["Creatures","Tasks","Places","Labor","Work orders","Objects","Justice"]
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		controllers[id]=panel;return panel
	if id=="justice":
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		panel.focus_requested.connect(focus_tile)
		panel.inspect_requested.connect(func(tile,unit_id):
			if host.allows_panel_input(panel) and controller("inspector").open_target(tile,1,unit_id,true):focus_tile(tile))
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		controllers[id]=panel;return panel
	if id=="objects":
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.focus_requested.connect(focus_tile)
		panel.inspect_requested.connect(func(item_id,tile):
			if not host.play_enabled:return
			focus_tile(tile);controller("farm").item_owner.open_target(item_id))
		controllers[id]=panel;return panel
	if id=="places":
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.focus_requested.connect(focus_tile)
		panel.inspect_requested.connect(func(tab,building_id,tile):
			if not host.play_enabled:return
			focus_tile(tile)
			if tab in [0,1]:controller("areas").open_zone(building_id)
			elif tab==2:controller("areas").open_stockpile(building_id)
			else:controller("inspector").open_target(tile,3,building_id,true))
		controllers[id]=panel;return panel
	if id=="tasks":
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.focus_requested.connect(focus_tile)
		panel.inspect_requested.connect(func(tile,unit_id):
			if host.allows_panel_input(panel) and controller("inspector").open_target(tile,1,unit_id,true):focus_tile(tile))
		controllers[id]=panel;return panel
	if id=="stocks":
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		panel.focus_requested.connect(focus_tile);ensure_follow()
		panel.item_owner.configure_follow(item_follow)
		panel.item_owner.holder_requested.connect(func(target):
			var holder: Dictionary=panel.item_owner.state.snapshot.get("holder",{})
			if holder.get("id",-1)==target:open_building_holder(int(holder.get("type",-1)),target))
		panel.item_owner.carrier_requested.connect(open_item_carrier)
		panel.item_owner.stockpile_requested.connect(func(target):controller("areas").open_stockpile(target))
		controllers[id]=panel;return panel
	if id=="work_details":
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.standing_orders_requested.connect(func():controller("standing_orders").open_from_labor())
		panel.kitchen_requested.connect(func():controller("standing_orders").open_from_labor(true))
		panel.stone_use_requested.connect(func():controller("standing_orders").open_from_labor(false,true))
		controllers[id]=panel;return panel
	if id=="standing_orders":
		add_child(panel);panel.configure(world,actions,host)
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.work_details_requested.connect(func():controller("work_details").open_from_labor())
		controllers[id]=panel;return panel
	if id=="residents":
		add_child(panel);panel.configure(world,actions,host)
		panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.panel.hover_help=view._fortress_hud.native_help
		panel.focus_requested.connect(focus_tile)
		panel.inspect_requested.connect(func(tile,unit_id):
			if host.allows_panel_input(panel) and controller("inspector").open_target(tile,1,unit_id,true):focus_tile(tile))
		controllers[id]=panel;return panel
	if id in ["farm","chest","workshop","door","pending_building"]:
		add_child(panel);panel.configure(world,actions,host,view._fortress_hud.native_help)
		ensure_follow()
		panel.holder_requested.connect(open_building_holder)
		if id=="workshop":
			panel.camera=view.camera_rig.get_node("Camera3D")
			panel.unit_requested.connect(func(unit_id):open_item_carrier(2,unit_id))
			panel.information_requested.connect(func(caption):_open_staged_information(panel,caption))
		panel.item_owner.configure_follow(item_follow)
		panel.item_owner.carrier_requested.connect(open_item_carrier)
		panel.item_owner.stockpile_requested.connect(func(target):controller("areas").open_stockpile(target))
		controllers[id]=panel;return panel
	if id in ["reports", "alerts"]:
		add_child(panel)
		panel.configure(world,actions,host)
		panel.focus_requested.connect(focus_tile)
		if id == "reports": panel.speaker_requested.connect(inspect_report_speaker)
		else:
			panel.history_requested.connect(func(): open_destination("Reports"))
			panel.panel.minimap_input=func(point):
				if view==null or not "_fortress_hud" in view:return false
				var hud=view._fortress_hud
				if hud==null or not hud.minimap.is_visible_in_tree() or not hud.minimap.allowed:return false
				return Rect2(hud.minimap.get_global_transform_with_canvas()*Vector2.ZERO,hud.minimap.size*hud.minimap.get_global_transform_with_canvas().get_scale()).has_point(point)
		controllers[id] = panel
		return panel
	panel.world = world
	panel.interaction = view._interaction
	panel.ui_host = host
	if id == "inspector":
		panel.focus_requested.connect(focus_tile)
		ensure_follow();panel.follow=creature_follow
		panel.history_requested.connect(func(unit_id):controller("reports").open_creature_history(unit_id))
		panel.object_requested.connect(func(kind,target_id):
			if kind==2:controller("farm").item_owner.open_target(target_id)
			elif kind==1:open_item_carrier(2,target_id)
			elif kind==3:
				var target: Dictionary=world.inspect_entity(3,target_id)
				if not target.is_empty():open_target(target.tile,3,target_id))
		panel.zone_requested.connect(func(zone_id,tile):focus_tile(tile);controller("areas").open_zone(zone_id))
		panel.action_service = actions
		panel.hover_help=view._fortress_hud.native_help
	if id in ["construction", "areas"]: panel.hud = view._fortress_hud
	if id in ["construction", "areas"]:
		panel.action_service = actions
		panel.camera = view.camera_rig.get_node("Camera3D")
	add_child(panel)
	host.register(panel)
	controllers[id] = panel
	if id == "areas":
		panel.focus_requested.connect(focus_tile)
		panel.options_requested.connect(func():
			if native_options != null: native_options.open())
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

# Internal transitions between staged native information screens. Public routes
# retain their separate acceptance gate; unknown tabs never fall back to Zones
# or the older readouts. The host closes the source only after accepting a target.
func _open_staged_information(source,caption: String) -> void:
	var completed_nobles: bool=controllers.get("nobles")==source and source.completing_information_handoff and host.active==null
	if not host.play_enabled or host.overlay_blocked or (not host.allows_panel_input(source) and not completed_nobles):return
	match caption:
		"Creatures":controller("residents").open_panel()
		"Tasks":controller("tasks").open_panel()
		"Places":controller("places").open_panel()
		"Objects":controller("objects").open_panel()
		"Justice":controller("justice").open_panel()
		"Labor":controller("work_details").open_panel()
		"Work orders":controller("workshop").open_global_orders()
		"Nobles and administrators":controller("nobles").open_panel()

func open_destination(destination: String) -> void:
	destination = Registry.READ_LAUNCHERS.get(destination,destination)
	if not Registry.PANEL_ROUTES.has(destination) or not host.play_enabled: return
	var panel = controller(Registry.PANEL_ROUTES[destination])
	if destination in ["Stockpiles", "Zones"]: panel.set_area_kind(0 if destination == "Stockpiles" else 1)
	if panel.has_method("set_info_page"): panel.set_info_page(destination)
	panel.open_panel()

func open_target(tile: Vector3i, kind: int, id: int) -> void:
	if not host.play_enabled:return
	if kind==3:
		var target: Dictionary=world.inspect_entity(kind,id)
		if target.get("building_kind",0)==9 and target.get("complete",false):
			open_tile_selection(tile);return
	controller("inspector").open_target(tile,kind,id)

# Native selection entry. Completed doors use it from ordinary map picking;
# remaining map targets retain their separate acceptance gate.
func open_tile_selection(tile: Vector3i) -> void:
	if tile_selection==null:
		tile_selection=preload("res://scripts/tile_selection_panel.gd").new()
		add_child(tile_selection);tile_selection.configure(world,actions,host,_selection_destination)
	tile_selection.open_tile(tile)

func _selection_destination(kind: int,id: int,tile: Vector3i):
	var c=preload("res://scripts/management_contract.gd")
	if kind==c.SelectionKind.Item:
		var target=controller("farm").item_owner
		target.open_target(id);return target if host.active==target else null
	if kind==c.SelectionKind.Unit:
		var target=controller("inspector")
		return target if target.open_target(tile,1,id,true) else null
	if kind==c.SelectionKind.Building:
		var info: Dictionary=world.inspect_entity(3,id)
		if not info.get("complete",false):return null
		var building_kind: int=info.get("building_kind",0)
		if building_kind not in [5,6,9,11,14]:
			# Keep existing building inspection available within staged selection.
			# This does not qualify those incomplete native building controls.
			var inspector=controller("inspector")
			return inspector if inspector.open_target(tile,3,id,true) else null
		open_building_holder(building_kind-1,id)
		var target=controllers.get("farm" if building_kind==5 else "door" if building_kind==9 else "chest" if building_kind==11 else "workshop")
		return target if target!=null and host.active==target and target.state.building_id==id else null
	return null

func open_notification(group:Dictionary) -> void:
	if host.play_enabled: controller("alerts").open_group(group)

func inspect_report_speaker(unit_id:int) -> void:
	if not host.play_enabled:return
	var target:Dictionary=world.inspect_entity(1,unit_id)
	if target.is_empty():return
	if controllers.has("reports"): controllers.reports.close_panel()
	# Native speaker navigation targets the current creature, not report.pos.
	focus_tile(target.tile)
	open_target(target.tile,1,unit_id)

func close_panel() -> void:
	if tile_selection!=null:
		var navigation=tile_selection.navigation
		var selected=navigation.owner.get_ref() if navigation.owner!=null else null
		navigation.close()
		if is_instance_valid(selected) and host.active==selected:selected.close_panel()
	if controllers.has("inspector"): controllers.inspector.close_panel()

func is_open() -> bool:
	if tile_selection!=null and tile_selection.navigation.owner!=null:
		if tile_selection.navigation.owner.get_ref()==host.active and host.active!=null:return true
	return controllers.has("inspector") and controllers.inspector.is_open()

func focus_tile(tile: Vector3i) -> void:
	_focus_tile(tile,false)

func ensure_follow() -> void:
	if item_follow!=null:return
	item_follow=preload("res://scripts/item_follow.gd").new();add_child(item_follow);item_follow.configure(actions)
	creature_follow=preload("res://scripts/creature_follow.gd").new();add_child(creature_follow);creature_follow.configure(actions)
	item_follow.changed.connect(func():
		if item_follow.item_id>=0 and creature_follow.unit_id>=0:creature_follow.stop())
	creature_follow.changed.connect(func():
		if creature_follow.unit_id>=0 and item_follow.item_id>=0:item_follow.stop())
	for follower in [item_follow,creature_follow]:
		follower.position_changed.connect(_follow_tile)
		view.camera_rig.navigation_requested.connect(follower.stop)
	view.camera_rig.mode_changed.connect(func():
		if view.camera_rig.is_walk_mode():item_follow.stop();creature_follow.stop())

func _follow_tile(tile: Vector3i) -> void:
	world.set_top_z(tile.z)
	var rig=view.camera_rig
	rig.follow_level(world.get_top_z())
	rig.follow_on(Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5),rig.current_distance(),preload("res://scripts/presentation_settings.gd").effective_scale_vector(get_viewport().get_visible_rect().size))
	follow_frame=_follow_frame()

func _follow_frame() -> Array:
	var rig=view.camera_rig;var camera=rig.get_node("Camera3D")
	var extent:=get_viewport().get_visible_rect().size
	return [extent,preload("res://scripts/presentation_settings.gd").effective_scale_vector(extent),camera.projection,camera.size,camera.fov,camera.basis,rig.current_distance()]

func _process(_delta: float) -> void:
	if item_follow==null:return
	var position: Variant=creature_follow.last_position if creature_follow.unit_id>=0 else item_follow.last_position
	if position==null:return
	# Reframe stationary targets after viewport/projection changes.
	if _follow_frame()!=follow_frame:_follow_tile(position)

func _focus_tile(tile: Vector3i, automatic: bool) -> void:
	# Leave gravity controls before selecting the report/entity destination,
	# then synchronize the rig before it clamps focus.
	view.camera_rig.exit_walk()
	world.set_top_z(tile.z)
	view.camera_rig.follow_level(world.get_top_z())
	view.camera_rig.focus_on(Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5),view.camera_rig.current_distance(),automatic)

# Session UI is global. Rendering only needs the resulting attachment/input gates.
func update_session(delta: float) -> bool:
	if view._loader == null: return true
	session_timer -= delta
	if session_timer <= 0:
		session_timer = 0.25
		view._session_state = world.poll_session()
	view._loader.update_session(view._session_state, view._fort_ready(), world.last_error())
	view._loader.update_progress(world.known_block_count(), world.map_block_count())
	view._session_controls.update_session(view._session_state, view._loader.entered)
	if native_options_session != null:
		native_options_session.update_session(view._session_state)
		# The global host dismisses local drafts on loss of the entered fortress;
		# submitted requests remain owned until their matching receipt settles.
		if not view._loader.entered: native_options.close()

	if view._release_close != null: view._release_close.update_session(view._session_state)
	view._set_play_enabled(view._loader.entered and not view._session_controls.blocks_commands(), view._loader.entered)
	view._audio.set_menu(not view._loader.entered)
	return view._loader.can_attach

func update_controls(enabled: bool, keep_map: bool) -> void:
	if view._session_controls != null:
		if not view._fortress_hud.menu_open() or view._interaction.construction_active or not (enabled or keep_map):
			view._session_controls.panel.hide()
	view._fortress_hud.update_state(enabled, enabled or keep_map, view._session_state)

func dismiss_notification(group:Dictionary) -> void:
	if not group.get("alert_button",false):return
	if red_alert_dismissal==null:
		red_alert_dismissal=preload("res://scripts/red_alert_dismiss_controller.gd").new()
		add_child(red_alert_dismissal)
		red_alert_dismissal.configure(world,actions)
	red_alert_dismissal.dismiss(int(group.get("fortress_epoch",0)))
