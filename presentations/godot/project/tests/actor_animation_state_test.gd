extends SceneTree

const State = preload("res://scripts/actor_animation_state.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func animation(state, id: int, position: Vector3, job := 0, segment := 0) -> String:
	state.sample(id, position, job, segment)
	return state.records[id].animation

func _initialize() -> void:
	var state = State.new()
	state.reset_if_needed(1)
	var job_cases := {1:"work_mine", 3:"work_craft", 4:"sleep", 5:"eat", 6:"drink"}
	for job in job_cases:
		check(animation(state, job, Vector3.ZERO, job) == job_cases[job], "stationary known job selects its activity")
	for job in [0, 2, 7, 8, 999]:
		check(animation(state, 100 + job, Vector3.ZERO, job).is_empty(), "unknown/combat/idle job does not invent an event")
	check(animation(state, 20, Vector3.ZERO, 0, 1).is_empty(), "first sight is not movement")
	check(animation(state, 20, Vector3.RIGHT, 0, 1) == "walk", "movement selects walking")
	check(animation(state, 20, Vector3(2, 0, 0), 2, 1) == "haul", "moving hauling assignment selects haul")
	check(animation(state, 20, Vector3(2, 1, 0), 0, 2) == "stairs", "classified vertical movement selects stairs")
	check(animation(state, 20, Vector3(100, 10, 0), 0, 4).is_empty(), "teleport never becomes gait")
	check(animation(state, 20, Vector3(100, 10, 0)).is_empty(), "standing after teleport remains neutral")
	check(animation(state, 20, Vector3(100, 8, 0), 0, 3) == "fall", "classified downward movement selects fall")
	check(animation(state, 20, Vector3(100, 6, 0), 0, 3) == "fall", "continued fall does not land")
	state.clock = 1.0
	check(animation(state, 20, Vector3(100, 6, 0)) == "land", "leaving fall starts landing")
	state.clock = 1.2
	check(animation(state, 20, Vector3(100, 6, 0)) == "land", "landing survives a stationary sample")
	check(is_equal_approx(state.records[20].start, 1.0), "landing samples retain event start")
	state.clock = 1.4
	check(animation(state, 20, Vector3(100, 6, 0)).is_empty(), "landing ends without retriggering")
	animation(state, 20, Vector3(100, 4, 0), 0, 3)
	check(animation(state, 20, Vector3.ZERO, 0, 4).is_empty(), "teleport out of fall does not invent landing")
	state.retain(PackedInt64Array([20]))
	check(state.records.size() == 1 and state.records.has(20), "departed actors are dropped without a death record")
	state.retain(PackedInt64Array())
	check(state.records.is_empty(), "empty visibility releases all actor state")
	animation(state, 20, Vector3.ZERO)
	state.reset_if_needed(1)
	check(state.records.has(20), "unchanged generation keeps state")
	state.reset_if_needed(2)
	check(state.records.is_empty(), "new session clears actor identities")
	state.clock = 2.0
	state.advance(0.05, true)
	check(is_equal_approx(state.clock, 2.0), "paused simulation freezes animation clock")
	state.advance(0.05, false)
	check(is_equal_approx(state.clock, 2.05), "running clock advances")
	state.advance(10.0, false)
	check(is_equal_approx(state.clock, 2.15), "clock caps a stalled frame")
	state.reset_if_needed(3)
	state.sample(1, Vector3.ZERO, 0, 0, 7, Vector3.RIGHT)
	check(state.records[1].animation.is_empty(), "existing attack on first sight is only a baseline")
	state.sample(1, Vector3.ZERO, 0, 0, 8, Vector3.RIGHT)
	check(state.records[1].animation == "attack", "new action starts targeted attack")
	var attack_start: float = state.records[1].start
	state.clock += .1
	var parameters: Color = state.sample(1, Vector3.ZERO, 0, 0, 8, Vector3.LEFT)
	check(is_equal_approx(parameters.b, attack_start) and is_equal_approx(parameters.a, 0.0), "repeated snapshot neither restarts nor turns ongoing lunge")
	state.sample(1, Vector3.ZERO, 0, 0, -1)
	check(state.records[1].animation == "attack", "brief action disappearance lets visual finish")
	state.clock += .5
	state.sample(1, Vector3.ZERO, 0, 0, 8, Vector3.RIGHT)
	check(state.records[1].animation.is_empty(), "same action never loops during recovery")
	state.sample(1, Vector3.ZERO, 0, 0, 9, Vector3.FORWARD)
	check(is_equal_approx(state.records[1].parameter, -PI / 2.0), "direction follows world target including north")
	state.sample(1, Vector3.ZERO, 0, 4, 9, Vector3.FORWARD)
	check(state.records[1].animation.is_empty(), "teleport cancels attack displacement")
	for target in [Vector3.INF, Vector3.ZERO, Vector3(20, 0, 0)]:
		state.sample(1, Vector3.ZERO, 0, 0, 10, target)
		check(state.records[1].animation.is_empty(), "unknown/coincident/distant target never guesses direction")
	state.reset_if_needed(4)
	state.sample(1, Vector3.ZERO, 0, 0, 9, Vector3.FORWARD)
	check(state.records[1].animation.is_empty(), "session reset does not replay old combat")
	state.reset_if_needed(5)
	state.sample(1, Vector3.ZERO, 0, 0, 1, Vector3.FORWARD, 2)
	state.sample(1, Vector3.ZERO, 0, 0, 2, Vector3.ZERO, 2)
	check(state.records[1].animation == "attack" and is_equal_approx(state.records[1].parameter, -PI/2), "same-tile attack reuses this actual target pair's observed direction")
	attack_start = state.records[1].start
	for next_attack in range(3, 7):
		state.clock += .08
		state.sample(1, Vector3.ZERO, 0, 0, next_attack, Vector3.RIGHT, 2)
		check(is_equal_approx(state.records[1].start, attack_start), "rapid attacks do not perpetually restart windup")
	state.clock += .2
	state.sample(1, Vector3.ZERO, 0, 0, 7, Vector3.ZERO, 3)
	check(state.records[1].animation.is_empty(), "different coincident target cannot inherit another pair's direction")
	state.sample(1, Vector3.ZERO, 0, 0, 8, Vector3.INF, 2)
	check(state.records[1].animation.is_empty(), "missing position does not reuse stale pair direction")
	state.sample(1, Vector3.ZERO, 0, 0, 9, Vector3(20,0,0), 2)
	check(state.records[1].animation.is_empty(), "distant target does not reuse near pair direction")
	state.sample(1, Vector3.ZERO, 0, 4, 10, Vector3.ZERO, 2)
	state.sample(1, Vector3.ZERO, 0, 0, 11, Vector3.ZERO, 2)
	check(state.records[1].animation.is_empty(), "teleport clears stale pair direction")
	check(not state.react(999), "unknown actors do not get invented reaction records")
	check(state.react(1, Vector3.LEFT), "explicit hit starts flinch on observed actor")
	var reaction_start: float = state.records[1].start
	check(state.records[1].refresh_at == -INF, "reaction invalidates only affected actor")
	state.clock += .1
	check(not state.react(1, Vector3.RIGHT), "rapid hits preserve current flinch onset")
	state.sample(1, Vector3.ZERO, 0, 0, 12, Vector3.RIGHT, 2)
	check(state.records[1].animation == "flinch" and is_equal_approx(state.records[1].start, reaction_start) and is_zero_approx(state.records[1].parameter), "flinch survives samples and recoils away from actual attacker")
	state.clock = reaction_start + .219
	state.sample(1, Vector3.ZERO, 0, 0, 13, Vector3.RIGHT, 2)
	check(state.records[1].animation == "flinch", "flinch held for entire .22 duration")
	state.clock = reaction_start + .221
	check(state.take_expired() == [1], "expired reaction schedules affected actor once")
	state.sample(1, Vector3.ZERO, 0, 0, 13, Vector3.RIGHT, 2)
	check(state.records[1].animation.is_empty(), "flinch expires without replaying suppressed attack")
	check(state.react(1), "unknown attacker still permits observed hit deformation")
	check(state.records[1].parameter == 1000.0, "unknown direction explicitly suppresses world recoil")
	state.sample(1, Vector3.ZERO, 0, 3)
	check(state.records[1].animation == "fall" and not state.react(1), "fall overrides and rejects recoil")
	state.reset_if_needed(6)
	check(state.deadlines.is_empty(), "session reset clears reactions")
	for target_id in range(20): state.sample(1, Vector3.ZERO, 0, 0, -1, Vector3.RIGHT, target_id)
	check(state.records[1].target_directions.size() == 8 and not state.records[1].target_directions.has(0), "pair direction memory stays bounded to recent eight targets")
	state.retain(PackedInt64Array([1, 19]))
	check(state.records[1].target_directions.size() == 1 and state.records[1].target_directions.has(19), "departed targets release direction history")
	state.reset_if_needed(7)
	check(not state.shoot(123, Vector3.RIGHT), "release cannot invent unseen actor")
	state.sample(1, Vector3.ZERO, 0, 0, 1)
	for invalid in [Vector3.INF, Vector3.ZERO, Vector3.UP]:
		check(not state.shoot(1, invalid), "missing horizontal release direction does not invent firing")
	check(state.shoot(1, Vector3.RIGHT), "observed release starts shooting recoil")
	var shot_start: float = state.records[1].start
	check(state.codes.shoot == 22 and state.records[1].refresh_at == -INF, "shot uses code22 and invalidates affected actor")
	state.clock += .1
	check(not state.shoot(1, Vector3.LEFT), "rapid releases do not reset active recoil or direction")
	state.sample(1, Vector3.ZERO, 0, 0, 2, Vector3.RIGHT, 2)
	check(state.records[1].animation == "shoot" and is_equal_approx(state.records[1].start, shot_start) and is_zero_approx(state.records[1].parameter), "shot holds through normal sample and consumes melee ID")
	state.clock = shot_start + .249
	state.sample(1, Vector3.ZERO, 0, 0, 2)
	check(state.records[1].animation == "shoot", "shot lasts full .25 seconds")
	state.clock = shot_start + .251
	state.sample(1, Vector3.ZERO, 0, 0, 2)
	check(state.records[1].animation.is_empty() and state.deadlines.is_empty(), "shot expires without looping or replaying melee")
	check(state.shoot(1, Vector3.FORWARD), "next release after recovery can fire")
	check(state.react(1, Vector3.LEFT), "actual hit overrides shot with flinch")
	check(state.records[1].animation == "flinch" and not state.shoot(1, Vector3.RIGHT), "release never overrides active hit reaction")
	state.clock += .23
	check(state.shoot(1, Vector3.FORWARD), "expired hit permits next observed release")
	state.sample(1, Vector3.ZERO, 0, 4)
	check(state.records[1].animation.is_empty() and not state.shoot(1, Vector3.RIGHT), "teleport cancels and suppresses shot recoil")
	state.reset_if_needed(8)
	check(state.deadlines.is_empty(), "session reset clears shot refresh deadline")
	# The cached path must match full evaluation through motion stop, job changes,
	# attack identity/target changes, reaction expiry and falls.
	var cached = load("res://scripts/actor_animation_state.gd").new()
	var reference = load("res://scripts/actor_animation_state.gd").new()
	for i in 120:
		cached.clock = i * 0.05; reference.clock = cached.clock
		if i == 40:
			cached.react(1, Vector3.LEFT); reference.react(1, Vector3.LEFT)
		if i == 60:
			cached.shoot(1, Vector3.RIGHT); reference.shoot(1, Vector3.RIGHT)
		if reference.records.has(1): reference.records[1].refresh_at = -INF
		var pos := Vector3(i * 0.1 if i < 10 else 1.0, 0, 0)
		var job := 1 if i >= 20 and i < 30 else 0
		var segment := 3 if i >= 80 and i < 90 else 0
		var attack := 1 if i < 30 else 2
		var target := Vector3.RIGHT if i < 35 else Vector3.LEFT
		check(cached.sample(1,pos,job,segment,attack,target,2) == reference.sample(1,pos,job,segment,attack,target,2), "cached poses match forced evaluation")
	var discrete = load("res://scripts/actor_animation_state.gd").new()
	discrete.sample(7, Vector3.ZERO, 0, 1, -1, Vector3.INF, -1, 1)
	check(discrete.records[7].animation == "walk", "motion interval starts walk before first position advances")
	discrete.clock = 1.0
	discrete.sample(7, Vector3.RIGHT, 0, 0, -1, Vector3.INF, -1, 0)
	check(discrete.records[7].animation.is_empty(), "arrival ends walk despite changed position")
	check(discrete.take_expired().is_empty(), "idle actor has no periodic preparation deadline")
	discrete.react(7, Vector3.ZERO)
	discrete.sample(7, Vector3.RIGHT, 0, 0, -1, Vector3.INF, -1, 0)
	discrete.clock += .23
	check(discrete.take_expired() == [7] and discrete.take_expired().is_empty(), "timed pose schedules exactly one actor refresh")
	print("ACTOR_ANIMATION_STATE_TEST_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
