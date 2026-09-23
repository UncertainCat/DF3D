extends RefCounted
# State changes only, evaluated during existing unit updates. Shader owns motion.
const Catalog = preload("res://scripts/actor_animation_catalog.gd")
const JOB_POSES := {1:"work_mine", 3:"work_craft", 4:"sleep", 5:"eat", 6:"drink"}
const TIMED_POSES := {"land": 0.34, "flinch": 0.22, "shoot": 0.25, "attack": 0.44}
# One typed record per actor; hot samples mutate fields rather than allocating
# and hashing a new dictionary for every rendered actor on every frame.
class Actor:
	extends RefCounted
	var position := Vector3.ZERO
	var segment := 0
	var animation := ""
	var start := 0.0
	var parameter := 0.0
	var attack_id := -1
	var target_directions: Dictionary = {}
	var moving := true
	var job := 0
	var source_attack := -1
	var target_id := -1
	var target_position := Vector3.INF
	var refresh_at := -INF
	var payload := Color()
var clock := 0.0
var generation := -1
var records := {}
var codes := {}
var deadlines: Dictionary = {}
func take_expired() -> Array:
	var expired: Array = []
	for id in deadlines:
		if clock >= deadlines[id]: expired.append(id)
	for id in expired: deadlines.erase(id)
	return expired
func _init():
	var definitions := Catalog.entries()
	for i in definitions.size(): codes[definitions[i].id] = i + 1
func advance(delta: float, paused: bool):
	if not paused: clock += minf(delta, 0.1)
	RenderingServer.global_shader_parameter_set("actor_animation_time", clock)
func reset_if_needed(value: int):
	if value != generation:
		generation = value
		records.clear()
		deadlines.clear()
func react(id: int, attacker_position: Vector3 = Vector3.INF) -> bool:
	# Only explicit combat events call this. First sight is never a guessed hit.
	if not records.has(id): return false
	var record: Actor = records[id]
	if record.segment in [3, 4]: return false
	if record.animation == "flinch" and clock - record.start < .22: return false
	var away: Vector3 = record.position - attacker_position
	away.y = 0.0
	var angle := 1000.0 # Unknown attacker: deformation only, no guessed direction.
	if attacker_position.is_finite() and away.length_squared() > .000001:
		angle = atan2(away.z, away.x)
	record.animation = "flinch"
	record.start = clock
	record.parameter = angle
	record.refresh_at = -INF
	return true
func shoot(id: int, direction: Vector3) -> bool:
	# Caller observed an actual projectile release and supplies its world direction.
	if not records.has(id) or not direction.is_finite(): return false
	direction.y = 0.0
	if direction.length_squared() <= .000001: return false
	var record: Actor = records[id]
	if record.segment in [3, 4]: return false
	if record.animation == "flinch" and clock - record.start < .22: return false
	if record.animation == "shoot" and clock - record.start < .25: return false
	record.animation = "shoot"
	record.start = clock
	record.parameter = atan2(direction.z, direction.x)
	record.refresh_at = -INF
	return true
func sample(id: int, position: Vector3, job: int, segment: int, attack_id: int = -1, target_position: Vector3 = Vector3.INF, target_id: int = -1, moving_hint: int = -1) -> Color:
	var previous: Actor = records.get(id)
	var first := previous == null
	if first:
		previous = Actor.new()
		records[id] = previous
	# Shader time animates an unchanged pose. Re-evaluate stationary source state
	# only on input changes or a timed pose's expiry. A moving sample must still
	# observe the first stationary sample to transition out of walking.
	if not first and not previous.moving and clock < previous.refresh_at and position == previous.position and job == previous.job and segment == previous.segment and attack_id == previous.source_attack and target_id == previous.target_id and target_position == previous.target_position:
		return previous.payload
	var moving: bool = moving_hint != 0 if moving_hint >= 0 else not first and position.distance_squared_to(previous.position) > 0.000001
	var animation := ""
	if segment == 4: moving = false # Teleport is never a step or landing.
	if segment == 3: animation = "fall"
	elif not first and previous.segment == 3 and segment != 3 and segment != 4: animation = "land"
	elif moving:
		animation = "stairs" if segment == 2 else "haul" if job == 2 else "walk"
	elif JOB_POSES.has(job):
		# Stationary assigned job is an approximation of action execution.
		animation = JOB_POSES[job]
	if not first and previous.animation == "land" and clock - previous.start < 0.34 and segment not in [3, 4]:
		animation = "land"
	var start: float = previous.start if not first and previous.animation == animation else clock
	var seed := float(posmod(id * 16807, 997)) / 997.0
	var seen_attack: int = previous.attack_id
	var new_attack := attack_id >= 0 and attack_id != seen_attack
	# First sight/session reset establishes a baseline: do not replay an old attack.
	# Remember directions only for the actual identified target pair. Co-positioned
	# combat can reuse that observation, never a neighboring actor or another target.
	var delta := target_position - position
	delta.y = 0.0
	var directions: Dictionary = previous.target_directions
	if segment == 4: directions.clear()
	var target_near := target_position.is_finite() and delta.length_squared() <= 6.25
	var target_valid := target_near and delta.length_squared() > .000001
	var direction := atan2(delta.z, delta.x) if target_valid else 0.0
	if target_valid and target_id >= 0:
		directions.erase(target_id)
		directions[target_id] = direction
		if directions.size() > 8: directions.erase(directions.keys()[0])
	elif target_near and target_id >= 0 and directions.has(target_id):
		target_valid = true
		direction = directions[target_id]
	if segment not in [3, 4]:
		if previous.animation == "flinch" and clock - previous.start < .22:
			animation = "flinch"
			start = previous.start
			seed = previous.parameter
		elif previous.animation == "shoot" and clock - previous.start < .25:
			animation = "shoot"
			start = previous.start
			seed = previous.parameter
		elif previous.animation == "attack" and clock - previous.start < .44:
			# Consume rapid new IDs below, but finish the current stroke. Otherwise
			# repeated actions can reset the wind-up forever without showing a lunge.
			animation = "attack"
			start = previous.start
			seed = previous.parameter
		elif new_attack and not first and target_valid:
			animation = "attack"
			start = clock
			seed = direction
	if attack_id >= 0: seen_attack = attack_id
	var payload := Color(0, codes.get(animation, 0), start, seed)
	previous.position = position
	previous.segment = segment
	previous.animation = animation
	previous.start = start
	previous.parameter = seed
	previous.attack_id = seen_attack
	previous.moving = moving
	previous.job = job
	previous.source_attack = attack_id
	previous.target_id = target_id
	previous.target_position = target_position
	previous.refresh_at = start + TIMED_POSES[animation] if TIMED_POSES.has(animation) else INF
	previous.payload = payload
	if TIMED_POSES.has(animation): deadlines[id] = previous.refresh_at
	else: deadlines.erase(id)
	return payload
func retain(ids: PackedInt64Array):
	var live := {}
	for id in ids: live[id] = true
	for id in records.keys():
		if not live.has(id):
			records.erase(id); deadlines.erase(id)
		else:
			var directions: Dictionary = records[id].target_directions
			for target in directions.keys():
				if not live.has(target): directions.erase(target)
