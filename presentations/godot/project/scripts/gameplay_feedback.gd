extends RefCounted
# Presentation policy for source observations. Events and actors have separate
# cursors; first sight, rewind and session changes establish silent baselines.
const CombatAudio = preload("res://scripts/combat_audio_resolver.gd")
var world: Node
var sounds: Node3D
var visuals: Node3D
var animation: RefCounted
var focus := Vector3.ZERO
var top_z := 0
var depth := 1
var clock := 0.0
var generation := -1
var combat_cursor := 0
var projectile_cursor := 0
var report_cursor := 0
var attack_cursor := 0
var baseline_tick := INF
var last_tick := -1.0
var last_source_tick := -1
var actors: Dictionary = {}
var cooldowns: Dictionary = {}
var counters := {"attacks": 0, "wounds": 0, "reports": 0, "steps": 0, "suppressed": 0}
var _burst := 0
var _burst_start := 0.0

func reset(next_generation: int, tick: float):
	generation = next_generation
	baseline_tick = tick
	last_tick = tick
	last_source_tick = -1
	combat_cursor = 0
	projectile_cursor = 0
	report_cursor = 0
	attack_cursor = 0
	actors.clear()
	cooldowns.clear()
	_burst = 0
	_burst_start = 0
	sounds.reset_session()
	visuals.reset_session()

func update_view(next_focus: Vector3, camera: Camera3D, now: float, upright: bool):
	clock = now
	focus = next_focus
	top_z = world.get_top_z()
	depth = world.get_window_depth()
	var tick: float = world.render_tick()
	var source_tick: int = world.bridge_tick()
	# Clock estimation can move the delayed render cursor slightly backwards.
	# Only authoritative source rewind/session replacement resets event identity.
	if generation != world.session_generation() or source_tick < last_source_tick:
		reset(world.session_generation(), tick)
	last_tick = tick
	last_source_tick = source_tick
	sounds.set_listener(focus, camera.global_basis)
	visuals.enabled = preload("res://scripts/presentation_settings.gd").combat_effects
	visuals.set_style(upright)
	visuals.advance(clock)
	# Only bounded journals are queried here. No world/entity scans per frame.
	for event in world.resolved_attack_events(attack_cursor):
		attack_cursor = maxi(attack_cursor, int(event.id))
		if event.tick > baseline_tick: consume_attack(event)
	for event in world.unit_combat_events(combat_cursor):
		combat_cursor = maxi(combat_cursor, int(event.id))
		if event.tick <= baseline_tick: continue
		consume_wound(event)
	for event in world.projectile_combat_events(projectile_cursor):
		projectile_cursor = maxi(projectile_cursor, int(event.id))
		if event.tick > baseline_tick: consume_projectile(event)
	if world.has_method("effect_events"):
		for event in world.effect_events(report_cursor):
			report_cursor = maxi(report_cursor, int(event.id))
			if event.tick > baseline_tick: consume_report(event)

func nearby(position: Vector3) -> bool:
	return position.is_finite() and position.y < top_z + 1.8 and position.y >= top_z - depth + 1 and position.distance_squared_to(focus) <= 32.0 * 32.0

func play(cue: String, position: Vector3, key: String, interval: float, seed_value: int, priority := 1, gain := -8.0, spatial := true, details: Dictionary = {}) -> bool:
	# Unsupported surfaces/assets must not crowd valid combat out of the budget.
	if cue.is_empty() or not sounds.catalog.has(cue): return false
	if spatial and not nearby(position): return false
	if clock - _burst_start >= 0.1: _burst_start = clock; _burst = 0
	if _burst >= 8 or clock < float(cooldowns.get(key, -INF)):
		counters.suppressed += 1
		return false
	cooldowns[key] = clock + interval
	# Bounded bookkeeping even when new sources arrive indefinitely.
	if cooldowns.size() > 512: cooldowns.erase(cooldowns.keys()[0])
	_burst += 1
	var metadata := {"tick": last_tick, "clock": clock, "source": key}
	metadata.merge(details, true)
	return sounds.request(cue, position, spatial, seed_value, priority, gain, metadata)

func actor(id: int, position: Vector3, segment: int, _attack_id: int, _target_id: int, _target: Vector3, render_anchor := Vector3.INF, sprite_height := 1.0):
	# Called from the existing unit preparation loop, not a new whole-world pass.
	if not nearby(position):
		actors.erase(id)
		return
	var before: Dictionary = actors.get(id, {})
	if not before.is_empty() and position == before.position and segment == before.get("segment") and render_anchor == before.render_anchor and sprite_height == before.sprite_height: return
	var step: Vector3 = before.get("step", position)
	var previous: Vector3 = before.get("position", position)
	if not before.is_empty() and segment not in [3, 4] and nearby(position) and position.distance_squared_to(previous) < 4.0 and position.distance_squared_to(step) >= 0.75 * 0.75:
		if play(_step_cue(position), position, "step:" + str(id), 0.3, id + int(clock * 4), 0, -22.0): counters.steps += 1
		step = position
	if segment in [3, 4]: step = position
	actors[id] = {"position": position, "step": step, "segment":segment,
		"render_anchor":render_anchor if render_anchor.is_finite() else position, "sprite_height":sprite_height}

func retain(ids: PackedInt64Array):
	# Called only on source unit updates; use existing IDs and a linear lookup.
	var live := {}
	for id in ids: live[id] = true
	for id in actors.keys():
		if not live.has(id): actors.erase(id)

func _step_cue(position: Vector3) -> String:
	var tile := Vector3i(floori(position.x), floori(position.z), floori(position.y))
	var terrain: Dictionary = world.tile_hover_info(tile)
	var material: String = terrain.get("material_kind", "")
	var surface: String = {"Stone":"stone", "Soil":"dirt", "Grass":"grass", "Wood":"wood-natural", "FrozenLiquid":"ice"}.get(material, "")
	if int(terrain.get("liquid_level", 0)) > 0 and terrain.get("liquid", "") == "Water":
		surface = "water-depth-" + str(mini(3, int(terrain.liquid_level)))
	return "locomotion/footsteps/" + surface + "/walk" if not surface.is_empty() else ""

static func tile_position(tile: Vector3i) -> Vector3:
	return Vector3(tile.x + 0.5, tile.z + 0.7, tile.y + 0.5)

func consume_wound(event: Dictionary):
	if int(event.kind) != 1: return # Death is not another weapon contact.
	var position: Vector3 = actors.get(int(event.victim_id), {}).get("position", tile_position(event.position))
	if not nearby(position): return
	counters.wounds += 1
	# Keep the confirmed visual reaction. No auditioned generic injury sound yet;
	# the native flesh/hit sample is a whoosh and must not duplicate attack audio.
	var source: Vector3 = actors.get(int(event.attacker_id), {}).get("position", Vector3.INF)
	var direction := position - source
	direction.y = 0.0
	if (not source.is_finite() or direction.length_squared() < 0.000001) and animation != null:
		var remembered: Dictionary = animation.records.get(int(event.attacker_id), {}).get("target_directions", {})
		if remembered.has(int(event.victim_id)):
			var angle: float = remembered[int(event.victim_id)]
			direction = Vector3(cos(angle), 0, sin(angle))
	if direction.is_finite() and direction.length_squared() >= 0.000001:
		var target: Dictionary = actors.get(int(event.victim_id), {})
		visuals.emit_effect("HIT", target.get("render_anchor", position), direction, clock, false, float(target.get("sprite_height", 1.0)))

func consume_attack(event: Dictionary):
	counters.attacks += 1
	var resolved: Dictionary = CombatAudio.resolve(event)
	if resolved.is_empty(): return
	# One decision after native completion. Multiple equipment contacts never
	# fan out into multiple cues; admission failure does not retry or fall back.
	play(resolved.cue, tile_position(event.position), "attack:" + str(event.id),
		0.0, event.id, 2, -8.0, true, {"tick":event.tick,"attack_event_id":event.id,
		"attacker_id":event.attacker_id,"defender_id":event.defender_id,
		"action_id":event.action_id,"outcome":resolved.outcome,"category":resolved.category,
		"weapon":event.get("weapon", {})})

func consume_projectile(event: Dictionary):
	var resolved: Dictionary = CombatAudio.resolve_projectile(event)
	if resolved.is_empty(): return
	play(resolved.cue, tile_position(event.position), "projectile:" + str(event.id),
		0.0, event.id, 2, -8.0, true, {"tick":event.tick,"projectile_event_id":event.id,
		"projectile_id":event.projectile_id,"kind":event.kind,"launcher":event.launcher,
		"source_unit_id":event.source_unit_id,"target_unit_id":event.target_unit_id,
		"category":resolved.category,"weapon":event.get("weapon", {}),"ammunition":event.get("ammunition", {})})

func consume_report(event: Dictionary):
	counters.reports += 1
	var details := {"tick":event.get("tick", last_tick),"event_id":event.id,"report_id":event.get("report_id", -1),"type":event.type}
	var kind: String = event.type
	if kind.begins_with("COMBAT_"): return # Resolved occurrences own combat audio.
	var position := tile_position(event.position)
	var cue: String = sounds.announcements.get(kind, "")
	if not cue.is_empty():
		play(cue, position, "announcement:" + kind, 2.0, event.id, 3, -5.0, false, details)
		return
	# Combat report positions do not identify a causal attack occurrence. Do not
	# add independent dodge, wrestle or defense audio beside resolved attacks.
