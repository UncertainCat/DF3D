extends SceneTree
const Feedback = preload("res://scripts/gameplay_feedback.gd")
class World:
	extends Node
	var tick := 0.0
	var source_tick := 0
	var generation := 1
	var combat: Array = []
	var attacks: Array = []
	func get_top_z(): return 2
	func get_window_depth(): return 3
	func render_tick(): return tick
	func bridge_tick(): return source_tick
	func session_generation(): return generation
	func unit_combat_events(cursor): return combat.filter(func(event): return event.id > cursor and event.tick <= tick)
	func resolved_attack_events(cursor): return attacks.filter(func(event): return event.id > cursor and event.tick <= tick)
	func projectile_combat_events(_cursor): return []
	func effect_events(_cursor): return []
	func tile_hover_info(_tile): return {"material_kind":"Stone"}
class Sounds:
	extends Node3D
	var events: Array = []
	var catalog := {"combat/fire-projectile/crossbow/metal/fire-projectile": [],
		"actions/attack": [], "combat/melee/flesh/swing": [], "combat/melee/flesh/hit": [], "combat/melee/metal/hit": [],
		"announcement/artifact_created": [], "locomotion/footsteps/stone/walk": []}
	var announcements := {"MADE_ARTIFACT":"announcement/artifact_created"}
	func request(cue, position, spatial, seed_value, priority, gain, metadata):
		events.append({"cue":cue,"position":position,"spatial":spatial,"seed":seed_value,"priority":priority,"gain":gain,"metadata":metadata})
		return not cue.is_empty()
	func reset_session(): events.clear()
	func set_listener(_focus, _basis): pass
class Visuals:
	extends Node3D
	var enabled := true
	var events: Array = []
	var pose := {}
	var style: Array = []
	func emit_effect(outcome, position, direction, clock, _sparks=false, height=0.0):
		events.append(outcome)
		pose = {"anchor":position,"height":height,"direction":direction}
	func reset_session(): events.clear()
	func set_style(upright): style = [upright]
	func advance(_clock): pass
var failures := 0
func check(ok, message):
	if not ok: failures += 1; push_error(message)
func _initialize(): call_deferred("run")
func run():
	var f := Feedback.new()
	f.world = World.new(); f.sounds = Sounds.new(); f.visuals = Visuals.new()
	f.top_z = 2; f.depth = 3; f.focus = Vector3(2, 1, 2); f.clock = 1
	f.actor(1, Vector3(2,1,2), 0, 5, 2, Vector3(3,1,2))
	check(f.sounds.events.is_empty(), "First sight never replays attack")
	f.actor(1, Vector3(2,1,2), 0, 6, 2, Vector3(3,1,2))
	check(f.sounds.events.is_empty() and f.visuals.events.is_empty(), "Observed action changes cannot independently produce audio")
	f.actor(1, Vector3(2,1,2), 0, 6, 2, Vector3(3,1,2))
	check(f.sounds.events.is_empty(), "Repeated action silent")
	f.actor(2, Vector3(3,1,2), 0, -1, -1, Vector3.INF, Vector3(3,0.25,2), 2.0)
	f.consume_wound({"id":1,"kind":1,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1)})
	check(f.sounds.events.is_empty() and f.visuals.events == ["HIT"], "Confirmed wound produces target effect")
	check(f.visuals.pose.anchor == Vector3(3,0.25,2) and f.visuals.pose.height == 2.0, "Effects receive render anchor and sprite height, independent of semantic position")
	f.consume_wound({"id":2,"kind":2,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1)})
	check(f.sounds.events.is_empty(), "Death is not another contact")
	f.consume_report({"id":3,"type":"MADE_ARTIFACT","position":Vector3i(-1,-1,-1)})
	check(f.sounds.events.back().cue == "announcement/artifact_created" and not f.sounds.events.back().spatial, "Global source announcement gets native cue")
	f.consume_report({"id":4,"type":"COMBAT_PARRY","position":Vector3i(3,2,1),"position2":Vector3i(2,2,1),"has_secondary":true,"material":"metal"})
	check(f.sounds.events.size() == 1 and f.sounds.events.back().cue == "announcement/artifact_created" and f.visuals.events == ["HIT"], "Parry report adds no unverified sound")
	f.clock = 2
	f.actor(1, Vector3(2,1,3), 0, -1, -1, Vector3.INF)
	check(f.sounds.events.back().cue == "locomotion/footsteps/stone/walk", "Movement uses observed floor surface")
	var before: int = f.sounds.events.size()
	f.actor(1, Vector3(20,1,20), 4, 9, 2, Vector3(21,1,20))
	check(f.sounds.events.size() == before, "Teleport produces no step or swing")
	f.reset(2, 100)
	check(f.sounds.events.is_empty() and f.visuals.events.is_empty() and f.actors.is_empty(), "Session clears audio visual and source history")
	for i in 32:
		f.play("", f.focus, "unknown:" + str(i), 1.0, i)
		f.play("missing/surface", f.focus, "missing:" + str(i), 1.0, i)
	check(f._burst == 0 and f.cooldowns.is_empty(), "Unknown cues do not consume sound admission budget")
	f.consume_wound({"id":5,"kind":1,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1),"weapon_material":"stone"})
	check(f.sounds.events.is_empty(), "Wounds cannot use the whoosh as a tissue fallback")
	f.clock += 0.1
	f.consume_wound({"id":6,"kind":1,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1),"weapon_material":"metal","weapon_source":"observed_action"})
	check(f.sounds.events.is_empty(), "Metal weapon context does not prove metal-on-metal contact")
	f.actors[1] = {"position":Vector3(3.5,0.7,2.5)}
	f.consume_wound({"id":6,"kind":1,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1)})
	check(f.visuals.events.is_empty(), "Vertical-only contact cannot choose a planar attack direction")
	# Exercise the actual view entry point, including source gates and independent
	# cursor/session handling. The source adapter separately verifies delayed gates.
	var camera := Camera3D.new()
	root.add_child(camera)
	f.world.combat = [
		{"id":1,"tick":0,"kind":1,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1)},
		{"id":2,"tick":2,"kind":1,"attacker_id":1,"victim_id":2,"position":Vector3i(3,2,1)}]
	f.update_view(f.focus, camera, 3.0, false)
	check(f.sounds.events.is_empty() and f.combat_cursor == 1, "Initial view consumes old journal silently")
	f.world.tick = 2.0
	f.world.source_tick = 2
	f.update_view(f.focus, camera, 4.0, false)
	check(f.sounds.events.is_empty() and f.combat_cursor == 2, "Due source event is consumed once")
	f.update_view(f.focus, camera, 4.1, true)
	check(f.visuals.style == [true], "Actual render style drives effects, not saved preferences")
	check(f.sounds.events.is_empty(), "Repeated source tick and camera style cannot replay sound")
	f.world.tick = 1.8
	f.update_view(f.focus, camera, 4.15, false)
	check(f.sounds.events.is_empty() and f.combat_cursor == 2, "Render-clock correction cannot reset or replay event identity")
	f.world.tick = 0.0
	f.world.source_tick = 0
	f.update_view(f.focus, camera, 4.2, false)
	check(f.sounds.events.is_empty() and f.combat_cursor == 1, "Rewind resets to silent source baseline")
	f.world.tick = 2.0
	f.world.source_tick = 2
	f.update_view(f.focus, camera, 5.0, false)
	check(f.sounds.events.is_empty() and f.combat_cursor == 2, "New timeline consumes its own wound IDs without fabricated audio")
	f.world.generation = 2
	f.update_view(f.focus, camera, 5.1, false)
	check(f.sounds.events.is_empty() and f.combat_cursor == 2, "Session replacement suppresses existing history")
	var pair := {"first":{"id":10,"material":"metal"},"second":{"id":11,"material":"metal"}}
	var attack := {"id":1,"tick":3,"position":Vector3i(3,2,1), "attacker_id":1,
		"defender_id":2,"action_id":7,"equipment_contacts_complete":true,"contacts":[pair,pair],
		"outcome":2,"outcome_complete":true,"weapon_context_complete":true,
		"weapon":{"id":10,"material_flags_known":true,"material_flags":2}}
	f.world.attacks = [attack]
	f.world.tick = 2.5
	f.update_view(f.focus, camera, 5.2, false)
	check(f.sounds.events.is_empty(), "Completed attack waits for delayed render tick")
	f.world.tick = 3.0; f.world.source_tick = 3
	f.update_view(f.focus, camera, 5.3, false)
	check(f.sounds.events.size() == 1 and f.sounds.events.back().cue == "combat/melee/metal/hit", "Several contacts resolve to one sound")
	check(f.sounds.events.back().metadata.attack_event_id == 1, "Sound identifies execution occurrence")
	f.update_view(f.focus, camera, 5.4, false)
	check(f.sounds.events.size() == 1, "Repeated snapshot never replays attack")
	var silent: Dictionary = attack.duplicate(true)
	silent.outcome_complete = false
	silent.wounds = [{"wound_id":12,"victim_id":2,"severed_part":true}]
	f.consume_attack(silent)
	silent.outcome_complete = true; silent.weapon_context_complete = false
	f.consume_attack(silent)
	silent.weapon_context_complete = true; silent.weapon.material_flags_known = false
	f.consume_attack(silent)
	check(f.sounds.events.size() == 1, "Unknown outcomes and unknown weapon facts stay silent despite injuries")
	var another: Dictionary = attack.duplicate(true)
	another.id = 2 # Same action ID may enter the resolver again; occurrence owns identity.
	f.world.attacks.append(another)
	f.update_view(f.focus, camera, 5.5, false)
	check(f.sounds.events.size() == 2, "Distinct executions with same action ID remain distinct")
	f.world.generation = 3
	f.update_view(f.focus, camera, 6.0, false)
	check(f.sounds.events.is_empty() and f.attack_cursor == 2, "Session suppresses preexisting attacks")
	camera.free()
	f.world.free(); f.sounds.free(); f.visuals.free()
	print("GAMEPLAY_FEEDBACK_TEST_PASS" if failures == 0 else "GAMEPLAY_FEEDBACK_TEST_FAIL")
	quit(0 if failures == 0 else 1)
