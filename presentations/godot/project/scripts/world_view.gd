# DF3D base renderer: terrain from the mesher stage textured through the asset provider,
# units/items as cutout volumes composited from DF's published layer stacks, buildings
# as extension-owned meshes, all fed by the Df3dWorld GDExtension node (world model API only).
# Requires a verified Steam DF install; no placeholder mode. Environment hooks: ENGINEERING.md.
# Keys: PageUp/PageDown or ] [ move the z-slice, F3 debug overlay (R reveal), P pause / O resume.
extends Node3D

@onready var world: Df3dWorld = $Df3dWorld
@onready var units: MultiMeshInstance3D = $Units
@onready var terrain: Node3D = $Terrain
@onready var buildings: Node3D = $Buildings
@onready var item_markers: MultiMeshInstance3D = $ItemMarkers
@onready var status: Label = $UI/Status
@onready var camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
const PresentationDemand = preload("res://scripts/presentation_demand.gd")
const Preferences = preload("res://scripts/presentation_settings.gd")
const ItemPreparation = preload("res://scripts/item_preparation.gd")
const ActorDeaths = preload("res://scripts/actor_death_visuals.gd")

var _attach_timer := 0.0
var _play_camera_mask := -1
var _focused := false
var _session_generation_seen := 0
var _ui: Node
var _interaction: Node3D
var _release_close: Node
var _debug_visible := false
var _session_controls: CanvasLayer
var _fortress_hud: CanvasLayer
var _fixture := OS.get_environment("DF3D_FIXTURE")
var _requested_top_z := -1
var _assets_ok := false
var _loader: CanvasLayer
var _session_state: Dictionary = {}
var _audio: Node
var _gameplay_feedback: RefCounted
var _combat_effects: Node3D
# Tier-4 hook: when DF3D_SCREENSHOT is set, save a frame once the terrain
# window is built (min 3s, max 60s) and quit.
var _screenshot_path := OS.get_environment("DF3D_SCREENSHOT")
var _dump_dir := OS.get_environment("DF3D_DUMP_COMPOSITES")
var _dump_done := false
var _screenshot_min := 3.0
var _screenshot_max := 60.0
var _elapsed := 0.0
# Frame time over the last frames (ms), for the stats line.
var _frame_ms_sum := 0.0
var _frame_ms_n := 0
# One MultiMeshInstance3D per spatial cell and sprite texture region.
var _actor_animation = preload("res://scripts/actor_animation_state.gd").new()
var _unit_probe = preload("res://scripts/unit_upload_probe.gd").new()
var _actor_motion = preload("res://scripts/actor_motion_pool.gd").new()
var _unit_status = preload("res://scripts/unit_status_overlay.gd").new()
var _unit_demand = preload("res://scripts/unit_demand.gd").new()
var _unit_indices: Dictionary = {}
var _unit_partition_positions := PackedVector3Array()
var _unit_membership_ids := PackedInt64Array()
var _unit_clip: Dictionary = {}
var _unit_clip_scope: Array = []
var _stack_atlas_seen := -1
var _unit_terrain_seen := -1
var _actor_deaths = preload("res://scripts/actor_death_visuals.gd").new()
var _projectiles = preload("res://scripts/projectile_visuals.gd").new()
var _projectile_release_cursor := 0
var _projectile_generation := -1
var _sprite_presentation: Node
var _sprite_resources = preload("res://scripts/sprite_resource_owner.gd").new()
var _sprite_layers: Dictionary = _sprite_resources.unit_layers
# Items retain separate upload groups; contour meshes and materials are shared
# with unit layers and all spatial cells.
var _item_layers: Dictionary = _sprite_resources.item_layers
var _cutout_resources: Dictionary = _sprite_resources.resources
var _spatial_sprites := false
var _spatial_items := true
var _item_cell_xy := 32
var _item_cell_z := 1
var _presentation_demand_enabled := OS.get_environment("DF3D_PRESENTATION_DEMAND") != "0"
var _sprite_cell_xy := 16
var _sprite_cell_z := 1
var _items_drawn := 0
var _sprite_shader: Shader = preload("res://shaders/unit_sprite.gdshader")

func _ready() -> void:
	camera_rig.walk_world = world
	if OS.get_environment("DF3D_RELEASE") == "1":
		_release_close = preload("res://scripts/release_close.gd").new()
		_release_close.world = world
		_release_close.close_requested.connect(func(): get_tree().quit())
		add_child(_release_close)
	add_child(_projectiles)
	_frame_costs.configure(world)
	_frame_costs.hitches = _hitches
	if _hitches.enabled:
		var hitch_path := OS.get_environment("DF3D_HITCH_OUT")
		if hitch_path.is_empty():
			_prune_hitch_sessions("user://hitches", HITCH_SESSION_FILES_KEPT - 1)
			hitch_path = "user://hitches/session-%s-%s.jsonl" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
		var hitch_error: Error = _hitches.configure_output(hitch_path)
		if hitch_error != OK: push_warning("Hitch report writer could not start: " + error_string(hitch_error))
		if OS.get_environment("DF3D_FRAME_BOUNDARIES") == "1":
			_hitches.boundary_clock = world.profiling_cpu_clock
			_hitches.render_checkpoint = world.profiling_render_boundary
			RenderingServer.frame_pre_draw.connect(_hitch_pre_draw)
		get_tree().process_frame.connect(_hitch_frame_boundary)
		var process_tail = preload("res://scripts/hitch_process_tail.gd").new()
		process_tail.recorder = _hitches
		add_child(process_tail)
	get_viewport().use_occlusion_culling = OS.get_environment("DF3D_OCCLUSION") != "0"
	configure_unit_batches(OS.get_environment("DF3D_SPATIAL_SPRITES") == "1",
		int(OS.get_environment("DF3D_SPRITE_CELL_XY")), int(OS.get_environment("DF3D_SPRITE_CELL_Z")))
	configure_item_batches(OS.get_environment("DF3D_SPATIAL_ITEMS") != "0",
		int(OS.get_environment("DF3D_ITEM_CELL_XY")), int(OS.get_environment("DF3D_ITEM_CELL_Z")))
	status.visible = false
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.position = Vector2(12, 270)
	_interaction = preload("res://scripts/interaction.gd").new()
	_interaction.world = world
	_interaction.camera = $CameraRig/Camera3D
	_interaction.camera_rig = camera_rig
	add_child(_interaction)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.8, 0.8)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/actor_marker.gdshader")
	_actor_motion.bind_material(mat)
	_unit_status.world = world
	_unit_status.motion = _actor_motion
	add_child(_unit_status)
	mesh.material = mat
	mm.mesh = mesh
	units.multimesh = mm
	var imm := MultiMesh.new()
	imm.transform_format = MultiMesh.TRANSFORM_3D
	imm.use_colors = true
	imm.use_custom_data = true
	var imesh := BoxMesh.new()
	imesh.size = Vector3(0.3, 0.3, 0.3)
	var imat := ShaderMaterial.new()
	imat.shader = preload("res://shaders/shared_stack_marker.gdshader")
	imesh.material = imat
	imm.mesh = imesh
	item_markers.multimesh = imm

	# Assets first: a missing or unrecognized install is a hard stop.
	_assets_ok = world.load_assets(OS.get_environment("DF3D_DF_PATH"))
	if not _assets_ok:
		status.visible = true
		status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		status.text = "DF3D cannot start: Dwarf Fortress assets unavailable.\n%s" % world.assets_error()
		push_error("df3d: %s" % world.assets_error())
		return

	world.set_terrain_root(terrain)
	var original_ui := preload("res://scripts/original_ui.gd").new()
	original_ui.configure(world)
	original_ui.apply(_interaction)

	var audio := preload("res://scripts/audio.gd").new()
	audio.name = "Audio"
	add_child(audio)
	_audio = audio
	audio.start(world.assets_root(), false, _fixture == "")
	_combat_effects = preload("res://scripts/combat_effects.gd").new()
	add_child(_combat_effects)
	_combat_effects.configure(world.assets_root())
	_gameplay_feedback = preload("res://scripts/gameplay_feedback.gd").new()
	_gameplay_feedback.world = world
	_gameplay_feedback.sounds = audio.sfx
	_gameplay_feedback.visuals = _combat_effects
	_gameplay_feedback.animation = _actor_animation
	_interaction.audio = audio
	var audio_panel := preload("res://scripts/audio_panel.gd").new()
	audio_panel.audio = audio
	add_child(audio_panel)
	original_ui.apply(audio_panel)
	_ui = preload("res://scripts/fortress_ui.gd").new()
	add_child(_ui)
	_ui.setup(self,audio_panel,original_ui)
	_sprite_presentation = preload("res://scripts/sprite_presentation.gd").new()
	add_child(_sprite_presentation)
	_sprite_presentation.configure(self)
	$CameraRig/Camera3D.set_meta("actor_animation", _actor_animation)
	$CameraRig/Camera3D.set_meta("actor_ceilings", _unit_clip)
	_sprite_presentation.set_style(preload("res://scripts/presentation_settings.gd").visual_style)
	_fortress_hud.visual_style_changed.connect(_sprite_presentation.set_style)
	world.set_building_root(buildings)
	var entity_budget_env := OS.get_environment("DF3D_ENTITY_BUDGET")
	if entity_budget_env != "":
		world.set_entity_budget_ms(float(entity_budget_env))
	# Diagnostic terrain-depth override for smoke tools and fixture captures.
	var window_env := OS.get_environment("DF3D_WINDOW")
	if window_env != "":
		world.set_window_depth(int(window_env))
	if OS.get_environment("DF3D_REVEAL") == "1":
		world.set_reveal_hidden(true)
	var budget_env := OS.get_environment("DF3D_COMPOSITE_BUDGET")
	if budget_env != "":
		world.set_composite_budget_ms(float(budget_env))
	var top_env := OS.get_environment("DF3D_TOP_Z")
	if top_env != "":
		_requested_top_z = int(top_env)

	if _fixture != "":
		var tick_env := OS.get_environment("DF3D_FIXTURE_TICK")
		if tick_env != "":
			world.set_fixed_render_tick(float(tick_env))
		var speed_env := OS.get_environment("DF3D_FIXTURE_SPEED")
		if speed_env != "":
			world.set_replay_speed(float(speed_env))
		if not world.load_fixture(_fixture):
			push_error("df3d: cannot load fixture %s: %s" % [_fixture, world.last_error()])

var _frame_costs=preload("res://scripts/frame_costs.gd").new()
var _hitches=preload("res://scripts/hitch_recorder.gd").new()
var _hitch_phase_override := "" # Development captures can label sampled windows.
const HITCH_SESSION_FILES_KEPT := 5

# Keep only the newest session files (by name: unix time prefix) so opt-in
# profiling never accumulates unbounded output under user://.
static func _prune_hitch_sessions(directory: String, keep: int) -> void:
	var dir := DirAccess.open(directory)
	if dir == null: return
	var sessions: Array[String] = []
	for name in dir.get_files():
		if name.begins_with("session-") and name.ends_with(".jsonl"): sessions.append(name)
	sessions.sort()
	while sessions.size() > keep:
		dir.remove(sessions.pop_front())

func _hitch_pre_draw() -> void:
	# Pre-draw is a CPU submission boundary, not GPU completion.
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		_hitches.pre_draw(Time.get_ticks_usec())

func _hitch_frame_boundary() -> void:
	var phase := _hitch_phase_override
	if phase.is_empty():
		phase = "playing" if _focused and _loader != null and _loader.entered else "loading_or_menu"
	_hitches.begin_frame(Time.get_ticks_usec(), phase)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_hitch_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_hitch_pre_draw)
	if get_tree().process_frame.is_connected(_hitch_frame_boundary):
		get_tree().process_frame.disconnect(_hitch_frame_boundary)
	_hitches.shutdown()
	if _frame_costs.enabled and is_instance_valid(world):
		var capture: String = _frame_costs.write_capture(world)
		if not capture.is_empty(): print("DF3D profile: ", capture)

var _resident_info_timer := 0.0
var _stream_log_elapsed := 0.0
var _stream_log_counts := [0,0,0,0,0]
var _stream_log_enabled: bool = OS.get_environment("DF3D_STREAM_LOG") == "1" or _frame_costs.enabled
func _process(delta: float) -> void:
	_hitches.application_boundary(true)
	var stage_start: int = _frame_costs.start()
	_stream_log_elapsed += delta
	if _stream_log_enabled and _stream_log_elapsed >= 5.0:
		_stream_log_elapsed = 0.0
		var stream: Dictionary = world.buffered_state()
		var counts := [stream.get("capture_publications_missed",0),stream.get("capture_read_failures",0),stream.get("capture_rejected_reads",0),stream.get("capture_queue_drops",0),stream.get("source_rejected_reads",0)]
		if counts != _stream_log_counts:
			print("DF3D_STREAM ",JSON.stringify(stream))
		_stream_log_counts = counts
	_actor_animation.advance(delta, bool(_session_state.get("paused", false)))
	_actor_deaths.expire(_actor_animation.clock)
	_elapsed += delta
	if _elapsed > 1.0:
		_frame_ms_sum += delta * 1000.0
		_frame_ms_n += 1
	if not _assets_ok:
		_maybe_screenshot(true)
		_frame_costs.mark("not_ready", stage_start)
		_hitches.application_boundary(false)
		return
	_resident_info_timer -= delta
	if _resident_info_timer <= 0:
		_resident_info_timer = 0.1
		world.update_resident_info()
	stage_start = _frame_costs.mark("frame_housekeeping", stage_start)
	if not _ui.update_session(delta):
		world.detach_live()
		_focused = false
		status.visible = false
		_frame_costs.mark("session_detach", stage_start)
		_hitches.application_boundary(false)
		return
	if not world.is_attached():
		if _fixture == "":
			_attach_timer -= delta
			if _attach_timer <= 0.0:
				_attach_timer = 2.0
				world.attach()
			status.text = "Waiting for DF mirror... (%s)" % world.last_error()
		else:
			status.text = "Fixture failed: %s" % world.last_error()
		status.visible = _loader == null
		_maybe_screenshot(true)
		_frame_costs.mark("session_attach", stage_start)
		_hitches.application_boundary(false)
		return

	stage_start = _frame_costs.mark("session_and_controls", stage_start)
	status.visible = _debug_visible
	if _presentation_demand_enabled and _focused and world.terrain_loaded():
		world.set_presentation_region(PresentationDemand.region(
			_camera,world.get_top_z(),world.get_window_depth(),world.presentation_art_margin()))
	elif not _presentation_demand_enabled:
		world.set_presentation_region(Rect2i())
	world.poll()
	var retired: Dictionary = _sprite_resources.reconcile(world, _instance_uploads, _item_storage)
	if retired.units > 0: _unit_revision_seen = -1
	if retired.items > 0:
		# Preparation owns logical groups; reset their remaining physical owners
		# together so a full manifest cannot strand an old layer outside it.
		for key in _item_layers.keys():
			_sprite_resources.remove(_item_layers, key, _instance_uploads, _item_storage)
		_sprite_resources.prune_shared(_instance_uploads)
		_item_preparation = ItemPreparation.new()
		_item_active_layers.clear()
	stage_start = _frame_costs.mark("world_poll", stage_start)
	if world.session_generation() != _session_generation_seen:
		camera_rig.exit_walk()
		_session_generation_seen = world.session_generation()
		_focused = false
	if _requested_top_z >= 0 and world.terrain_loaded():
		world.set_top_z(_requested_top_z)
		_requested_top_z = -1
	if world.terrain_loaded(): camera_rig.follow_level(world.get_top_z())
	if _loader == null and _fortress_hud != null:
		_fortress_hud.update_state(true, true, _session_state)

	stage_start = _frame_costs.mark("view_state", stage_start)
	var unit_detail_start: int = _hitches.detail_start()
	_gameplay_feedback.update_view(camera_rig.position, _camera, _actor_animation.clock, _sprite_presentation.sprites_oriented())
	unit_detail_start = _hitches.detail_mark("unit.feedback", unit_detail_start)
	var motion_tick: float = world.render_tick()
	RenderingServer.global_shader_parameter_set("unit_status_clock", float(Time.get_ticks_msec() % 7000))
	RenderingServer.global_shader_parameter_set("actor_motion_clock", Vector2(floor(motion_tick / 4096.0), fmod(motion_tick, 4096.0)))
	if _stack_atlas_seen != world.stack_atlas_revision():
		_stack_atlas_seen = world.stack_atlas_revision()
		_unit_status.refresh_stack_materials()
		for resource in _cutout_resources.values(): world.configure_stack_material(resource[1])
		world.configure_stack_material(item_markers.multimesh.mesh.material)
		world.configure_stack_material(units.multimesh.mesh.material)
	unit_detail_start = _hitches.detail_mark("unit.view_parameters", unit_detail_start)
	_update_units()
	unit_detail_start = _hitches.detail_mark("unit.prepare", unit_detail_start)
	world.set_hidden_corpses(_actor_deaths.corpse_handoff(world.corpse_item_changes(), _actor_animation.clock, Preferences.animation_strength > 0.0))
	_hitches.detail_mark("unit.corpse_handoff", unit_detail_start)
	stage_start = _frame_costs.mark("unit_upload", stage_start)
	_projectiles.update(world)
	stage_start = _frame_costs.mark("projectile_upload", stage_start)
	_update_items()
	stage_start = _frame_costs.mark("item_upload", stage_start)

	if not _focused and (world.terrain_loaded() or (world.unit_count() > 0 and _elapsed > 2.0)):
		_focused = true
		_focus_on_units()

	if _debug_visible:
		var terrain_state := "no terrain"
		if world.terrain_loaded():
			terrain_state = "terrain %d/%d blocks | built %d (%d faces, %d textured, %d placeholder, %d hidden caps)" % [
				world.known_block_count(), world.map_block_count(), world.built_block_count(),
				world.face_count(), world.textured_face_count(), world.unresolved_face_count(), world.hidden_face_count()]
			if world.pending_block_count() > 0:
				terrain_state += " | building %d" % world.pending_block_count()
		else:
			terrain_state = "terrain loading (%d/%d blocks)" % [world.known_block_count(), world.map_block_count()]
		var composite_state := "composites: %d cached (%d failed), %d built in %.1f ms (%.1f ms this frame)" % [
			world.composite_cache_size(), world.composite_failed_count(), world.composite_build_count(),
			world.composite_total_ms(), world.composite_last_ms()]
		if world.composite_pending_count() > 0:
			composite_state += " | %d pending" % world.composite_pending_count()
		if world.appearance_event_count() > 0:
			composite_state += " | %d appearance changes" % world.appearance_event_count()
		var entity_state := "buildings: %d drawn, %d unresolved, %.1f ms last / %.0f ms total | item layers: %d drawn, %d unresolved, %.1f ms" % [
			world.building_drawn_count(), world.building_unresolved_count(), world.building_last_ms(),
			world.building_total_ms(), world.item_drawn_count(), world.item_unresolved_count(), world.item_last_ms()]
		if world.building_pending_count() > 0:
			entity_state += " | building %d" % world.building_pending_count()
		if world.building_unresolved_count() > 0 or world.item_unresolved_count() > 0:
			entity_state += " | unresolved: " + world.entity_unresolved_summary()
		var classic_state := "corpses: %d composited, %d pieces, %d webs | glyphs: %d units, %d items, %d buildings | tileset: %s" % [
			world.item_composited_count(), world.item_piece_count(), world.item_web_count(),
			world.unit_glyph_count(), world.item_glyph_count(), world.building_glyph_count(), world.glyph_summary()]
		if world.item_composite_pending_count() > 0:
			classic_state += " | %d corpse composites pending" % world.item_composite_pending_count()
		if world.item_appearance_event_count() > 0:
			classic_state += " | %d corpse appearance changes" % world.item_appearance_event_count()
		status.text = "%s | units: %d (%d composited, %d simple sprites, %d glyphs, %d cubes) | sim tick: %d | render tick: %.1f | map: %s\ntop z: %d (window %d) | %s | build %.1f ms last, %.0f ms total\n%s\n%s\n%s\nassets: %s\nRMB orbit, MMB pan, wheel zoom, WASD/QE move, PgUp/PgDn or ][ slice, R reveal, P pause / O resume" % [
			world.source_name(), world.unit_count(), world.composited_unit_count(), world.simple_sprite_unit_count(),
			world.unit_glyph_count(), world.cube_unit_count(), world.bridge_tick(), world.render_tick(), world.map_size(),
			world.get_top_z(), world.get_window_depth(), terrain_state, world.last_build_ms(), world.total_build_ms(),
			composite_state, entity_state, classic_state, world.assets_summary()]

	_maybe_dump_composites()
	_maybe_screenshot(world.terrain_loaded() and world.pending_block_count() == 0 and world.composite_pending_count() == 0 and world.building_pending_count() == 0 and world.item_composite_pending_count() == 0)

	_frame_costs.mark("remaining_main", stage_start)
	if _hitches.enabled:
		_hitches.record_work(_instance_resize_count, _instance_uploads.counters.transforms_written, _instance_uploads.counters.custom_written)
	_hitches.application_boundary(false)

var _sprites_drawn := 0
var _unit_revision_seen := -1
var _unit_animation_clock_seen := -1.0
# Cheap counters also expose whether a profiling run actually uploaded data.
var _unit_upload_count := 0
var _item_upload_count := 0
var _item_probe = preload("res://scripts/item_upload_probe.gd").new()
var _item_preparation = preload("res://scripts/item_preparation.gd").new()
var _item_storage = preload("res://scripts/item_instance_storage.gd").new()
var _item_active_layers: Dictionary = {}
var _item_delta_groups := 0
var _item_delta_fulls := 0
var _item_sparse_checks := 0
var _item_full_checks := 0
var _instance_resize_count := 0
var _instance_allocation_bytes := 0
var _instance_allocation_calls := 0
var _sprite_multimesh_creates := 0
var _sprite_material_creates := 0
const ItemCapacity = preload("res://scripts/item_instance_capacity.gd")
var _instance_uploads = preload("res://scripts/instance_upload_cache.gd").new()
var _unit_partitions = preload("res://scripts/unit_partition_cache.gd").new()

# Combined diagnostic sweep; normal startup configures items and actors independently.
func configure_sprite_batches(enabled: bool, cell_xy := 16, cell_z := 1) -> void:
	configure_unit_batches(enabled, cell_xy, cell_z)
	configure_item_batches(enabled, cell_xy, cell_z)

func configure_unit_batches(enabled: bool, cell_xy := 16, cell_z := 1) -> void:
	_spatial_sprites = enabled
	_sprite_cell_xy = cell_xy if cell_xy in [8, 16, 32] else 16
	_sprite_cell_z = 4 if cell_z == 4 else 1
	_unit_revision_seen = -1

# Partition resident items into fixed world cells. Camera pose never changes these
# keys or the broad preparation region; Godot culls each group using its bounds.
func configure_item_batches(enabled: bool, cell_xy := 32, cell_z := 1) -> void:
	_spatial_items = enabled
	_item_cell_xy = cell_xy if cell_xy in [8, 16, 32] else 32
	_item_cell_z = 4 if cell_z == 4 else 1
	world.configure_sprite_batches(enabled, _item_cell_xy, _item_cell_z)

func _sprite_cell(position: Vector3) -> Vector3i:
	if not _spatial_sprites: return Vector3i.ZERO
	return Vector3i(floori(position.x / _sprite_cell_xy), floori(position.y / _sprite_cell_z), floori(position.z / _sprite_cell_xy))

func _sprite_batch_key(slot: int, region: Color, cell: Vector3i) -> String:
	return _instance_uploads.region_key(slot, region) + ":" + str(cell)

func sprite_batch_stats() -> Dictionary:
	var result := {"enabled": _spatial_sprites, "cell_xy": _sprite_cell_xy, "cell_z": _sprite_cell_z,
		"item_spatial_enabled": _spatial_items, "item_cell_xy": _item_cell_xy, "item_cell_z": _item_cell_z,
		"unit_groups": 0, "item_groups": 0, "instances": 0, "max_group_instances": 0, "shared_resources": _cutout_resources.size(),
		"unit_partition_rebuilds": _unit_partitions.rebuilds, "unit_partition_hits": _unit_partitions.hits,
		"unit_partition_keys_built": _unit_partitions.keys_built,
		"item_group_early_hits": _item_preparation.hits, "item_group_early_misses": _item_preparation.misses,
		"item_delta_groups": _item_delta_groups, "item_delta_fulls": _item_delta_fulls,
		"item_sparse_checks": _item_sparse_checks, "item_full_checks": _item_full_checks}
	for entry in [[_sprite_layers, "unit_groups"], [_item_layers, "item_groups"]]:
		for layer in entry[0].values():
			var count: int = ItemCapacity.visible_count(layer.multimesh)
			if count == 0: continue
			result[entry[1]] += 1
			result.instances += count
			result.max_group_instances = maxi(result.max_group_instances, count)
	return result

func _set_instance_count(mm: MultiMesh, count: int) -> void:
	if mm.instance_count != count:
		mm.instance_count = count
		_instance_uploads.invalidate(mm)
		_instance_resize_count += 1
		if _frame_costs.mode == "deep":
			_instance_allocation_calls += 1
			_instance_allocation_bytes += count * (48 + (16 if mm.use_custom_data else 0) + (16 if mm.use_colors else 0))

func engine_submission_stats() -> Dictionary:
	var result: Dictionary = _instance_uploads.submission_stats()
	result.instance_allocation_calls = _instance_allocation_calls
	result.instance_allocation_requested_bytes = _instance_allocation_bytes
	result.sprite_multimesh_creates = _sprite_multimesh_creates
	result.sprite_material_creates = _sprite_material_creates
	result.actor_motion_page_uploads = _actor_motion.uploads
	result.actor_motion_upload_bytes = _actor_motion.upload_bytes
	return result

const InstanceDependencies = preload("res://scripts/instance_dependencies.gd")

func _instance_dependencies() -> InstanceDependencies:
	return InstanceDependencies.new(InstanceDependencies.Style.BILLBOARD if _sprite_presentation != null and _sprite_presentation.sprites_oriented() else InstanceDependencies.Style.FLAT,
		world.session_generation(), world.get_top_z())

func _fort_ready() -> bool:
	return world.is_attached() and world.live_synchronized() and world.terrain_loaded() and world.pending_block_count() == 0 and world.composite_pending_count() == 0 and world.building_pending_count() == 0 and world.item_composite_pending_count() == 0 and _focused

func _set_play_enabled(value: bool, keep_map := false) -> void:
	if not value: camera_rig.exit_walk()
	# Keep render instances active while the loading screen conceals the map.
	# Rebuilding beneath a hidden Node3D produces uninitialized RID errors in
	# the supported renderer; camera filtering preserves resource initialization.
	if value or keep_map:
		if _play_camera_mask >= 0:
			_camera.cull_mask = _play_camera_mask
			_play_camera_mask = -1
	elif _play_camera_mask < 0:
		_play_camera_mask = _camera.cull_mask
		_camera.cull_mask = 0
	camera_rig.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if _ui != null: _ui.host.set_play_enabled(value)
	else: _interaction.set_play_enabled(value)
	if _ui != null: _ui.update_controls(value, keep_map)

# Tier-4 hook: once every visible unit's composite is built, dump the
# requested (or a sample of) composites as PNGs and quit only via the
# screenshot hook, if any.
func _maybe_dump_composites() -> void:
	if _dump_dir == "" or _dump_done:
		return
	if world.unit_count() == 0 or world.composite_pending_count() > 0:
		return
	_dump_done = true
	var ids := PackedInt64Array()
	var ids_env := OS.get_environment("DF3D_DUMP_IDS")
	if ids_env != "":
		for part in ids_env.split(","):
			if part.strip_edges() != "":
				ids.append(int(part.strip_edges()))
	var max_env := OS.get_environment("DF3D_DUMP_MAX")
	var max_units := 24 if max_env == "" else int(max_env)
	world.dump_unit_composites(_dump_dir, ids, max_units)

# Ground-aligned silhouette volumes. The extension owns physical depth layout
# for both textured pieces and unresolved markers. Motion intervals live in a
# shared GPU pool; identical source regions share their contour meshes.
func _update_units() -> void:
	if _unit_probe.enabled: _unit_probe.begin()
	var preflight_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
	var demanded_stale: bool = _unit_demand.update_view(_camera)
	var generation: int = world.session_generation()
	_actor_animation.reset_if_needed(generation)
	_actor_motion.reset(generation)
	_actor_deaths.reset(generation)
	var dirty_ids := {}
	for id in _actor_animation.take_expired(): dirty_ids[id] = true
	if _projectile_generation != generation:
		_projectile_generation = generation; _projectile_release_cursor = 0
		_unit_clip.clear(); _unit_membership_ids.clear(); _unit_clip_scope.clear()
		_unit_indices.clear()
		_unit_demand.groups.clear()
	for release in world.projectile_release_events(_projectile_release_cursor):
		_projectile_release_cursor = maxi(_projectile_release_cursor, int(release.id))
		_actor_animation.shoot(int(release.firer_id), release.target - release.origin)
		dirty_ids[int(release.firer_id)] = true
	var animate_deaths: bool = Preferences.animation_strength > 0.0
	var scope := [generation, world.get_top_z(), world.get_window_depth(), _sprite_presentation.billboard]
	var scope_changed := scope != _unit_clip_scope
	var terrain: int = world.terrain_revision()
	var terrain_changed := terrain != _unit_terrain_seen
	_unit_terrain_seen = terrain
	_unit_clip_scope = scope.duplicate()
	_actor_deaths.set_view_scope(scope + [animate_deaths])
	var events: Array = world.unit_combat_events(_actor_deaths.cursor)
	_actor_deaths.observe(events, _actor_animation.clock, animate_deaths)
	for event in events:
		if int(event.kind) == ActorDeaths.COMBAT_WOUND:
			var attacker = _actor_animation.records.get(int(event.attacker_id))
			_actor_animation.react(int(event.victim_id), attacker.position if attacker != null else Vector3.INF)
			dirty_ids[int(event.victim_id)] = true
	_actor_deaths.expire(_actor_animation.clock)
	var revision: int = world.unit_render_revision()
	if _unit_probe.enabled: _unit_probe.add("preflight_us", preflight_started)
	if revision == _unit_revision_seen and dirty_ids.is_empty() and events.is_empty() and not scope_changed and not terrain_changed and not demanded_stale:
		if _unit_probe.enabled: _unit_probe.finish()
		return
	var source_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
	var source_detail_started := source_started
	var delta: Dictionary = world.unit_render_delta(_unit_revision_seen)
	_unit_revision_seen = revision
	_unit_upload_count += 1
	var actor_ids: PackedInt64Array = world.unit_ids()
	_unit_status.begin(generation, scope, actor_ids)
	var status_flags: PackedInt64Array = world.unit_status_flags()
	var membership_changed := actor_ids != _unit_membership_ids
	var full: bool = delta.full or scope_changed or not _instance_uploads.enabled
	var changed := {}
	for index in delta.indices: changed[index] = true
	if membership_changed:
		_unit_membership_ids = actor_ids.duplicate()
		_unit_indices.clear()
		for i in actor_ids.size(): _unit_indices[actor_ids[i]] = i
		_actor_animation.retain(actor_ids); _gameplay_feedback.retain(actor_ids); _actor_motion.retain(actor_ids)
		for id in _unit_clip.keys():
			if not _unit_indices.has(id): _unit_clip.erase(id)
	var by_id: Dictionary = _unit_indices
	for id in dirty_ids:
		if by_id.has(id): changed[by_id[id]] = true
	if _unit_probe.enabled: source_detail_started = _unit_probe.source_mark("delta_and_membership", source_detail_started)
	_actor_deaths.update(self, actor_ids, _actor_animation.clock, _sprite_presentation, world.render_tick())
	if _unit_probe.enabled: source_detail_started = _unit_probe.source_mark("death_lifecycle", source_detail_started)
	var positions: PackedVector3Array = world.unit_cutout_positions() # interaction/death snapshots only
	var semantic: PackedVector3Array = world.unit_positions()
	var jobs: PackedInt32Array = world.unit_jobs()
	var segments: PackedInt32Array = world.unit_motion_segments()
	var attacks: PackedInt32Array = world.unit_attack_ids()
	var targets: PackedInt32Array = world.unit_attack_targets()
	var slots: PackedInt32Array = world.unit_sprite_slots()
	var regions: PackedColorArray = world.unit_sprite_regions()
	var sizes: PackedVector2Array = world.unit_sprite_sizes()
	var scales: PackedColorArray = world.unit_scale_params()
	var colors: PackedColorArray = world.unit_colors()
	var thicknesses: PackedFloat32Array = world.unit_thicknesses()
	var first: PackedColorArray = world.unit_motion_from()
	var last: PackedColorArray = world.unit_motion_to()
	var epochs: PackedVector2Array = world.unit_motion_epochs()
	var ordinals: PackedInt32Array = world.unit_stack_ordinals()
	var tiles: PackedVector3Array = world.unit_stack_tiles()
	if _unit_probe.enabled: source_detail_started = _unit_probe.source_mark("native_arrays", source_detail_started)
	var partition_rebuilds_before: int = _unit_partitions.rebuilds if _unit_probe.enabled else 0
	var partition_keys_before: int = _unit_partitions.keys_built if _unit_probe.enabled else 0
	var partition_changes = null if full or membership_changed else delta.indices
	_unit_partition_positions.resize(actor_ids.size())
	for i in (range(actor_ids.size()) if partition_changes == null else partition_changes):
		_unit_partition_positions[i] = Vector3(first[i].r, first[i].g, first[i].b)
	_unit_partitions.update(slots, regions, _unit_partition_positions,
		_spatial_sprites, _sprite_cell_xy, _sprite_cell_z, _sprite_batch_key, actor_ids, partition_changes)
	if _unit_probe.enabled:
		_unit_probe.source_mark("partition", source_detail_started)
		_unit_probe.row.partition_rebuilds = _unit_partitions.rebuilds - partition_rebuilds_before
		_unit_probe.row.partition_keys_built = _unit_partitions.keys_built - partition_keys_before
		_unit_probe.row.source_changed_actors = delta.indices.size()
		_unit_probe.row.source_membership_changed = membership_changed
		_unit_probe.add("source_us", source_started)
		_unit_probe.row.full = full
	var terrain_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
	if terrain_changed and _sprite_presentation.billboard:
		for id in _unit_clip:
			var clip: Dictionary = _unit_clip[id]
			var token: int = world.sprite_ceiling_source_revision(clip.bounds, clip.floor)
			if token != clip.token and by_id.has(id):
				clip.token = -1 # Preserve invalidation while its group is offscreen.
				changed[by_id[id]] = true
	if _unit_probe.enabled: _unit_probe.add("clipping_us", terrain_started)
	var groups: Dictionary = _unit_partitions.groups
	var all_groups: Array = groups.keys()
	all_groups.append("")
	for key in _unit_partitions.removed_keys:
		_sprite_resources.remove(_sprite_layers, key, _instance_uploads, _item_storage)
		_unit_demand.remove(key)
	_sprite_resources.prune_shared(_instance_uploads)
	for key in all_groups:
		var demand_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
		var list: Array = _unit_partitions.markers if key == "" else groups[key]
		var deferred: bool = _unit_demand.stale(key)
		var membership_dirty: bool = _unit_partitions.changed_keys.has(key)
		var dirty := full or membership_dirty
		if not dirty:
			for i in list:
				if changed.has(i): dirty = true; break
		if dirty:
			var demand_bounds := AABB()
			for i in list:
				var start := Vector3(first[i].r, first[i].g, first[i].b)
				var end := Vector3(last[i].r, last[i].g, last[i].b)
				var extent := maxf(sizes[i].x, sizes[i].y) * maxf(1.0, scales[i].r) * 1.6 + 1.0
				var box := AABB(start, Vector3.ZERO).expand(end).grow(extent)
				demand_bounds = box if demand_bounds == AABB() else demand_bounds.merge(box)
			_unit_demand.changed(key, demand_bounds)
		if _unit_probe.enabled:
			_unit_probe.add("demand_us", demand_started)
			_unit_probe.row.groups_scanned += 1
		if not _unit_demand.stale(key):
			if _unit_probe.enabled: _unit_probe.row.unchanged_groups += 1
			continue
		var setup_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
		if not _unit_demand.visible(_unit_demand.groups[key].bounds):
			if _unit_probe.enabled: _unit_probe.row.hidden_groups += 1
			var hidden = units if key == "" else _sprite_layers.get(key)
			if hidden != null: hidden.visible = false
			if _unit_probe.enabled: _unit_probe.add("setup_us", setup_started)
			continue
		var group_full := full or deferred or membership_dirty
		if _unit_probe.enabled:
			if membership_dirty: _unit_probe.row.membership_groups += 1
			if deferred: _unit_probe.row.deferred_groups += 1
		var layer: MultiMeshInstance3D = units if key == "" else _cutout_layer(slots[list[0]], regions[list[0]], _sprite_layers, key, true)
		var mm: MultiMesh = layer.multimesh
		var reallocated := mm.instance_count != list.size()
		_set_instance_count(mm, list.size())
		var uploads = _instance_uploads.begin(mm)
		var bounds := AABB()
		if _unit_probe.enabled: _unit_probe.add("setup_us", setup_started)
		for k in list.size():
			var i: int = list[k]
			var id: int = actor_ids[i]
			if group_full or reallocated or changed.has(i):
				var started := Time.get_ticks_usec() if _unit_probe.enabled else 0
				var source := Vector3(first[i].r, first[i].g, first[i].b)
				var destination := Vector3(last[i].r, last[i].g, last[i].b)
				var scale: Color = scales[i]
				var address := _actor_motion.write(id, first[i], last[i], epochs[i], tiles[i], ordinals[i])
				_unit_status.observe(id, status_flags[i], address, source, destination, sizes[i], scale, _sprite_presentation.billboard)
				if _unit_probe.enabled:
					_unit_probe.row.actors += 1
					_unit_probe.add("motion_us", started)
					started = Time.get_ticks_usec()
				var target: Vector3 = semantic[by_id[targets[i]]] if by_id.has(targets[i]) else Vector3.INF
				var animation: Color = _actor_animation.sample(id, semantic[i], jobs[i], segments[i], attacks[i], target, targets[i], int(segments[i] in [1, 2]))
				_gameplay_feedback.actor(id, semantic[i], segments[i], attacks[i], targets[i], target, positions[i], sizes[i].y)
				if _unit_probe.enabled: _unit_probe.add("animation_us", started)
				started = Time.get_ticks_usec() if _unit_probe.enabled else 0
				var size: Vector2 = sizes[i] if key != "" else Vector2(.8,.8)
				var geometry_key := [source, destination, size, scale.r, mm.mesh.get_instance_id(), scope]
				var clip: Dictionary = _unit_clip.get(id, {})
				if clip.is_empty() or clip.key != geometry_key:
					var extent := maxf(size.x, size.y) * maxf(1.0, scale.r) * 1.6 + 1.0
					var box := AABB(source, Vector3.ZERO).expand(destination).grow(extent)
					# A traversed landing is support, not a roof over the moving actor.
					# Clip against terrain above the whole semantic movement interval.
					clip = {"key":geometry_key,"bounds":box,"floor":floori(maxf(source.y,destination.y)),"token":-1,"ceiling":1000000.0}
				var token: int = clip.token
				if token == -1 or terrain_changed:
					token = world.sprite_ceiling_source_revision(clip.bounds, clip.floor) if _sprite_presentation.billboard else 0
				if token != clip.token:
					clip.ceiling = world.sprite_ceiling(clip.bounds, clip.floor) if _sprite_presentation.billboard else 1000000.0
					clip.token = token
					_instance_uploads.counters.ceiling_evaluations += 1
				_unit_clip[id] = clip
				if _unit_probe.enabled: _unit_probe.add("clipping_us", started)
				started = Time.get_ticks_usec() if _unit_probe.enabled else 0
				var custom := Color(clip.ceiling, animation.g, animation.b, animation.a)
				var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(size.x, 1, size.y)), Vector3.ZERO) if key != "" else Transform3D.IDENTITY
				var payload := Color(scale.r, scale.g, clip.ceiling, address) if key != "" else Color(colors[i].r,colors[i].g,colors[i].b,address)
				uploads.write(mm, k, transform, custom if key != "" else null, payload)
				if key != "":
					var frozen_scale := scale; frozen_scale.b = clip.ceiling; frozen_scale.a = 0
					_actor_deaths.remember(id, layer, transform, custom, size, thicknesses[i], positions[i], frozen_scale,
						{"from":first[i],"to":last[i],"epochs":epochs[i],"tick":world.render_tick()})
				if _unit_probe.enabled: _unit_probe.add("storage_us", started)
			var bounds_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
			if _unit_clip.has(id):
				var box: AABB = _unit_clip[id].bounds
				# Keep dependency/demand bounds intact; only the renderer's box
				# excludes the volume discarded by the billboard ceiling shader.
				if _sprite_presentation.billboard and key != "":
					# Apply the culling margin before clipping;
					# expanding it afterwards reintroduces volume above the roof.
					box = box.grow(1.0)
					var top := minf(box.end.y, float(_unit_clip[id].ceiling))
					box.position.y = minf(box.position.y, top)
					box.size.y = maxf(.001, top - box.position.y)
				bounds = box if bounds == AABB() else bounds.merge(box)
			if _unit_probe.enabled: _unit_probe.add("bounds_us", bounds_started)
		var bounds_submit_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
		if mm.custom_aabb != bounds: mm.custom_aabb = bounds
		if key != "": layer.extra_cull_margin = 0.0 if _sprite_presentation.billboard else 1.0
		_unit_demand.prepared(key, layer)
		if _unit_probe.enabled: _unit_probe.add("bounds_us", bounds_submit_started)
	var flush_started := Time.get_ticks_usec() if _unit_probe.enabled else 0
	_actor_motion.flush()
	_unit_status.flush()
	if _unit_probe.enabled: _unit_probe.add("flush_us", flush_started)
	if _unit_probe.enabled: _unit_probe.finish()
	_sprites_drawn = actor_ids.size() - _unit_partitions.markers.size()

# Items: the same cutout volume as units (one MultiMesh per cell/texture region),
# scaled by the extension's per-item size (a pile spreads and shrinks),
# unresolved items as small tinted marker cubes.
func _update_items() -> void:
	var revision := world.item_render_revision()
	var clip_changed: bool = _item_preparation.refresh_clipping(world, _sprite_presentation.billboard)
	var presentation := _instance_dependencies()
	var dependencies: Array = presentation.key()
	dependencies.append_array([_spatial_items, _item_cell_xy, _item_cell_z, _instance_uploads.generation])
	if not _item_preparation.needs_update(revision, dependencies, _instance_uploads.enabled): return
	var context_changed: bool = _item_preparation.begin(revision, dependencies) or clip_changed
	_item_upload_count += 1
	var counters: Dictionary = _instance_uploads.counters
	if _hitches.enabled: _hitches.begin_item_work(_instance_resize_count, counters.transforms_written, counters.custom_written)
	var probing: bool = _item_probe.enabled
	if probing: _item_probe.begin(counters)
	var positions := world.item_positions()
	var thicknesses := world.item_thicknesses()
	var sizes := world.item_sprite_sizes()
	var colors := world.item_colors()
	var ground_flags := world.item_ground_flags()
	var ordinals := world.item_stack_ordinals()
	var start := _frame_costs.start(true)
	var delta: Dictionary = world.item_render_group_delta(-1 if context_changed or not _instance_uploads.enabled else _item_preparation.delta_revision)
	_item_preparation.delta_revision = delta.revision
	_frame_costs.mark("item_group_manifest", start, true)
	if probing:
		_item_probe.add("manifest_us", start)
		_item_probe.row["full_manifest"] = delta.full
		_item_probe.row["context_reset"] = context_changed
		_item_probe.row["dependencies"] = dependencies
	var live: Dictionary = {}
	if delta.full: _item_delta_fulls += 1
	_item_delta_groups += delta.groups.size()
	for key in delta.removed:
		_remove_item_group(_item_preparation.remove(key))
	if delta.full:
		for record in delta.groups: live[record.key] = true
		for key in _item_preparation.groups.keys():
			if not live.has(key): _remove_item_group(_item_preparation.remove(key))
	for record in delta.groups:
		if delta.full: live[record.key] = true
		var group = _item_preparation.groups.get(record.key)
		var marker: bool = record.slot < 0
		var layer_key := "" if marker else _sprite_batch_key(record.slot, record.region, record.cell)
		# Existing logical groups already retain their immutable mesh envelope.
		# Preparation can reject them before touching engine resources.
		var layer = null
		var mesh_bounds: AABB
		if group == null:
			layer = item_markers if marker else _cutout_layer(record.slot, record.region, _item_layers, layer_key)
			mesh_bounds = layer.multimesh.mesh.get_aabb()
		else: mesh_bounds = group.mesh_bounds
		start = _frame_costs.start(true)
		var patch = _item_preparation.prepare(record, positions, sizes, thicknesses, colors, ground_flags,
			mesh_bounds, layer_key, dependencies, world, counters, _instance_uploads.enabled, _item_probe, ordinals)
		_frame_costs.mark("item_prepare", start, true)
		if probing: _item_probe.add("prepare_us", start)
		if patch == null: continue
		if layer == null: layer = item_markers if marker else _item_layers[layer_key]
		var mm: MultiMesh = layer.multimesh
		start = _frame_costs.start(true)
		if _item_storage.apply(mm, patch, counters):
			_instance_resize_count += 1
			if probing:
				_item_probe.row.resized_groups += 1
				_item_probe.row.resized_instances += mm.instance_count
			if _frame_costs.mode == "deep":
				_instance_allocation_calls += 1
				_instance_allocation_bytes += mm.instance_count * (48 + (16 if mm.use_custom_data else 0) + (16 if mm.use_colors else 0))
		if not layer.visible: layer.show()
		_frame_costs.mark("item_apply", start, true)
		if probing: _item_probe.add("write_us", start)
		if not marker: _item_active_layers[layer_key] = true
	_items_drawn = positions.size() - ItemCapacity.visible_count(item_markers.multimesh)
	_item_sparse_checks = _item_preparation.sparse_checks
	_item_full_checks = _item_preparation.full_checks
	if probing: _item_probe.finish(counters)
	_sprite_resources.prune_shared(_instance_uploads)
	if _hitches.enabled: _hitches.end_item_work(_instance_resize_count, counters.transforms_written, counters.custom_written)

func _remove_item_group(group) -> void:
	if group == null: return
	if group.marker:
		_item_storage.hide(item_markers.multimesh)
		item_markers.hide()
	elif _item_layers.has(group.layer_key):
		_sprite_resources.remove(_item_layers, group.layer_key, _instance_uploads, _item_storage)
		_item_active_layers.erase(group.layer_key)

func _cutout_layer(slot: int, region: Color, cache: Dictionary, key: String, actor := false) -> MultiMeshInstance3D:
	if cache.has(key):
		return cache[key]
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	if _frame_costs.mode == "deep": _sprite_multimesh_creates += 1
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = actor
	var resource_key: String = ("actor:" if actor else "item:") + _instance_uploads.region_key(slot, region)
	if not _cutout_resources.has(resource_key):
		var mat := ShaderMaterial.new()
		if _frame_costs.mode == "deep": _sprite_material_creates += 1
		mat.shader = _sprite_shader
		mat.set_shader_parameter("actor_animated", actor)
		mat.set_shader_parameter("actor_scale_data", actor)
		world.configure_stack_material(mat)
		if actor: _actor_motion.bind_material(mat)
		mat.set_shader_parameter("sprite_tex", world.sprite_texture(slot))
		mat.set_shader_parameter("sprite_region", Vector4(region.r, region.g, region.b, region.a))
		mat.set_shader_parameter("sprite_cell", world.sprite_texture(slot).get_meta("world_cell", Vector2.ZERO))
		_cutout_resources[resource_key] = [world.sprite_cutout_mesh(slot, region), mat]
	mmi.material_override = _cutout_resources[resource_key][1]
	mm.mesh = _cutout_resources[resource_key][0]
	mmi.multimesh = mm
	_sprite_resources.track(mmi, slot, resource_key)
	if actor: mmi.extra_cull_margin = 1.0
	add_child(mmi)
	cache[key] = mmi
	return mmi

func _focus_on_units() -> void:
	var positions := world.unit_positions()
	var center := Vector3.ZERO
	if positions.size() > 0:
		for p in positions:
			center += p
		center /= positions.size()
	else:
		var m := world.map_size()
		center = Vector3(m.x * 0.5, 0.0, m.z * 0.5)
	if world.terrain_loaded():
		center.y = float(world.get_top_z()) + 1.0
	var m2 := world.map_size()
	var dist := clampf(maxf(m2.x, m2.z) * 0.9, 40.0, 160.0)
	# Tier-4 hooks: DF3D_CAM_FOCUS="x,y,z" (DF tile coords), DF3D_CAM_DIST,
	# DF3D_CAM_PITCH (radians, negative looks down), DF3D_CAM_YAW.
	var focus_env := OS.get_environment("DF3D_CAM_FOCUS")
	if focus_env != "":
		var parts := focus_env.split(",")
		if parts.size() == 3:
			center = Vector3(float(parts[0]) + 0.5, float(parts[2]) + 1.0, float(parts[1]) + 0.5)
	var dist_env := OS.get_environment("DF3D_CAM_DIST")
	if dist_env != "":
		dist = float(dist_env)
	var pitch_env := OS.get_environment("DF3D_CAM_PITCH")
	if pitch_env != "":
		camera_rig._pitch = float(pitch_env)
	var yaw_env := OS.get_environment("DF3D_CAM_YAW")
	if yaw_env != "":
		camera_rig._yaw = float(yaw_env)
	var pos_env := OS.get_environment("DF3D_CAM_POS")
	if pos_env != "":
		var parts := pos_env.split(",")
		if parts.size() == 3:
			var eye := Vector3(float(parts[0]) + 0.5, float(parts[2]) + 0.5, float(parts[1]) + 0.5)
			camera_rig.place_eye(eye, dist)
			var tile := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			if world.has_method("tile_summary"):
				print("df3d: camera eye at DF tile ", tile, ": ", world.tile_summary(tile))
			return
	camera_rig.focus_on(center, dist)
	# Exercise the same public mode transition used by the toolbar in offline shots.
	if not OS.get_environment("DF3D_CAM_MODE").is_empty(): camera_rig.set_mode(OS.get_environment("DF3D_CAM_MODE").to_lower())

func _maybe_screenshot(ready_now: bool) -> void:
	if _screenshot_path == "":
		return
	if (_elapsed >= _screenshot_min and ready_now) or _elapsed >= _screenshot_max:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		var stats := "source=%s top_z=%d window=%d units=%d sprites=%d composited=%d simple=%d glyph_units=%d cubes=%d composite_cache=%d composite_failed=%d composite_built=%d composite_total_ms=%.2f composite_pending=%d terrain_loaded=%s known_blocks=%d map_blocks=%d built_blocks=%d faces=%d textured=%d placeholder=%d hidden=%d pending=%d total_build_ms=%.1f buildings=%d buildings_unresolved=%d building_pending=%d building_total_ms=%.1f items=%d items_unresolved=%d item_ms=%.2f building_events=%d item_events=%d items_composited=%d items_pieces=%d items_webs=%d items_glyphs=%d item_composite_pending=%d buildings_glyphs=%d item_appearance_events=%d glyph_tileset=\"%s\" draw_calls=%d primitives=%d objects=%d frame_ms=%.2f elapsed_s=%.1f render_tick=%.1f assets_ok=%s" % [
			world.source_name(), world.get_top_z(), world.get_window_depth(), world.unit_count(), _sprites_drawn,
			world.composited_unit_count(), world.simple_sprite_unit_count(), world.unit_glyph_count(), world.cube_unit_count(),
			world.composite_cache_size(), world.composite_failed_count(), world.composite_build_count(),
			world.composite_total_ms(), world.composite_pending_count(),
			str(world.terrain_loaded()), world.known_block_count(), world.map_block_count(),
			world.built_block_count(), world.face_count(), world.textured_face_count(), world.unresolved_face_count(),
			world.hidden_face_count(), world.pending_block_count(), world.total_build_ms(),
			world.building_drawn_count(), world.building_unresolved_count(), world.building_pending_count(), world.building_total_ms(),
			world.item_drawn_count(), world.item_unresolved_count(), world.item_last_ms(),
			world.building_event_count(), world.item_event_count(),
			world.item_composited_count(), world.item_piece_count(), world.item_web_count(), world.item_glyph_count(),
			world.item_composite_pending_count(), world.building_glyph_count(), world.item_appearance_event_count(),
			world.glyph_summary(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			_frame_ms_sum / maxf(1.0, float(_frame_ms_n)),
			_elapsed, world.render_tick(), str(_assets_ok)]
		print("df3d: screenshot saved to ", _screenshot_path, " ", stats)
		print("df3d: unresolved entities by kind: ", world.entity_unresolved_summary())
		var f := FileAccess.open(_screenshot_path + ".txt", FileAccess.WRITE)
		if f:
			f.store_line(stats)
			f.close()
		_screenshot_path = ""
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if _loader != null and not _loader.entered: return
	if camera_rig.controls_blocked(): return
	if not (event is InputEventKey and event.pressed):
		return
	var key := event as InputEventKey
	if key.echo and key.keycode != KEY_PAGEUP and key.keycode != KEY_PAGEDOWN:
		return
	match key.keycode:
		KEY_F5:
			camera_rig.set_mode("walk")
		KEY_F4:
			camera_rig.toggle_mode()
		KEY_Q, KEY_E:
			if camera_rig.get_mode() != "free": _step_top_z(1 if key.keycode == KEY_E else -1)
		KEY_PAGEUP, KEY_BRACKETRIGHT:
			_step_top_z(1)
		KEY_PAGEDOWN, KEY_BRACKETLEFT:
			_step_top_z(-1)
		KEY_R:
			if _debug_visible: world.set_reveal_hidden(not world.get_reveal_hidden())
		KEY_F3:
			_debug_visible = not _debug_visible
		KEY_P:
			_interaction._pause(true)
		KEY_O:
			_interaction._pause(false)

func _step_top_z(dz: int) -> void:
	if _fortress_hud != null and not _fortress_hud.elevation_available(): return
	if camera_rig.is_walk_mode(): return
	if not world.terrain_loaded():
		return
	var before := world.get_top_z()
	world.set_top_z(before + dz)
	var after := world.get_top_z()
	if after != before:
		if camera_rig.get_mode() != "free": camera_rig.follow_level(after)
		else:
			camera_rig.position.y += float(after - before)
			camera_rig.focus_on(camera_rig.position, camera_rig.current_distance())
