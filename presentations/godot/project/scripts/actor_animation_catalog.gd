extends RefCounted
## Pure procedural cutout poses. Units are fractions of actor height, not tiles.
## Consumers pivot at the feet and map this local artwork plane into their mode.
## No simulation inference, scene mutation, clocks, or resource uploads live here.

const MODES := ["classic", "billboard"]
const DEFINITIONS := [
	["walk", "Walking", .64, true, "observed movement", false],
	["run", "Running", .40, true, "reliable running gait", true],
	["climb", "Climbing", .92, true, "confirmed climbing state", true],
	["stairs", "Stairs", .70, true, "moving on confirmed stairs", true],
	["fall", "Falling", .80, true, "classified fall", true],
	["land", "Landing", .34, false, "confirmed fall landing transition", true],
	["work_mine", "Mining", .90, true, "active mining action, not assigned job alone", true],
	["work_chop", "Chopping", 1.10, true, "active chopping action", true],
	["work_craft", "Crafting", .78, true, "active crafting action", true],
	["eat", "Eating", 1.35, true, "active eating action", true],
	["drink", "Drinking", 1.80, true, "active drinking action", true],
	["haul", "Hauling", .88, true, "moving with confirmed carried item", true],
	["attack", "Attacking", .44, false, "new attack event with identity", true],
	["flinch", "Flinching", .22, false, "new hit or wound event with identity", true],
	["death", "Death collapse", .72, false, "alive-to-dead transition and corpse handoff", true],
	["idle", "Idle", 4.80, true, "stationary and awake", false],
	["sleep", "Sleeping", 3.20, true, "confirmed sleeping state", true],
	["hop", "Hopping", .58, true, "moving with confirmed hopping gait", true],
	["scurry", "Scurrying", .30, true, "moving with confirmed scurrying gait", true],
	["lumber", "Lumbering", 1.05, true, "moving with confirmed heavy gait", true],
	["fly", "Flying", 1.30, true, "confirmed flying state", true],
	["shoot", "Firing", .25, false, "observed projectile release with known firer and direction", true],
]

const LIVE_TRIGGERS := {
	"walk":"Observed semantic movement", "stairs":"Model vertical transition (stairs or ramps)",
	"fall":"Model-classified fall", "land":"End of a classified fall (not teleport)",
	"haul":"Movement with hauling job (carried item not verified)",
	"work_mine":"Stationary mining job (approximate action)",
	"work_craft":"Stationary construction job (approximate work)",
	"sleep":"Stationary sleep job (approximate)",
	"eat":"Stationary eating job (approximate)", "drink":"Stationary drinking job (approximate)",
	"attack":"New observed melee action with a known nearby target; attempt, not confirmed hit",
	"flinch":"Confirmed wound on an observed actor",
	"shoot":"Observed projectile release with known firer and firing direction",
	"death":"Confirmed death retains the last visible actor for collapse"
}

static func entries() -> Array:
	var result: Array = []
	for d in DEFINITIONS:
		result.append({"id": d[0], "title": d[1], "duration": d[2],
			"loop": d[3], "modes": MODES.duplicate(), "trigger": d[4],
			"preview_only": not LIVE_TRIGGERS.has(d[0]), "runtime_trigger": LIVE_TRIGGERS.get(d[0], "Preview only; gameplay signal unavailable")})
	return result

static func _definition(id: String) -> Array:
	for d in DEFINITIONS:
		if d[0] == id: return d
	return []

static func _smooth(a: float, b: float, t: float) -> float:
	var u := clampf((t - a) / (b - a), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

## Combat custom-data alpha carries a world XZ direction angle, not a phase seed.
## Displacement is in tile units, independent of sprite scale and camera facing.
static func world_offset(code: int, elapsed: float, angle: float, strength: float = 1.0) -> Vector3:
	if code not in [13, 14, 22] or not is_finite(elapsed) or not is_finite(angle) or absf(angle) > TAU: return Vector3.ZERO
	if code == 22:
		var phase := clampf(elapsed / .25, 0.0, 1.0)
		var recoil := _smooth(0.0, .16, phase) * (1.0 - _smooth(.16, 1.0, phase))
		return Vector3(cos(angle), 0.0, sin(angle)) * -.045 * recoil * strength
	if code == 14:
		var phase := clampf(elapsed / .22, 0.0, 1.0)
		var recoil := _smooth(0.0, .20, phase) * (1.0 - _smooth(.20, 1.0, phase))
		return Vector3(cos(angle), 0.0, sin(angle)) * .08 * recoil * strength
	var u := clampf(elapsed / .44, 0.0, 1.0)
	var windup := _smooth(0.0, .28, u) * (1.0 - _smooth(.28, .48, u))
	var lunge := _smooth(.28, .48, u) * (1.0 - _smooth(.48, 1.0, u))
	return Vector3(cos(angle), 0.0, sin(angle)) * (-.025 * windup + .25 * lunge) * strength

## On-demand picking equivalent of mix(point, actor_animate(...), strength).
## The cutout art lies in x/-z with its feet at z=.5; y is thickness.
## Keep this transform in step with shaders/actor_animation.gdshaderinc.
static func vertex(point: Vector3, code: int, elapsed: float, seed: float, strength: float = 1.0) -> Vector3:
	if code < 1 or code > DEFINITIONS.size() or strength == 0.0:
		return point
	var state := pose(DEFINITIONS[code - 1][0], elapsed, seed)
	var art := Vector2(point.x, .5 - point.z) * Vector2(state.scale)
	var angle: float = state.rotation
	var c := cos(angle)
	var s := sin(angle)
	var offset: Vector3 = state.offset
	art = Vector2(c * art.x - s * art.y, s * art.x + c * art.y) + Vector2(offset.x, offset.y)
	var animated := Vector3(art.x, point.y + offset.z, .5 - art.y)
	return point.lerp(animated, strength)

static func pose(id: String, time: float, seed: float = 0.0) -> Dictionary:
	var output := {"offset": Vector3.ZERO, "rotation": 0.0, "scale": Vector2.ONE}
	var d := _definition(id)
	if d.is_empty() or not is_finite(time) or not is_finite(seed): return output
	var duration: float = d[2]
	var looping: bool = d[3]
	# Phase offsets apply only to loops. Event animations start at their first pose.
	var u := fposmod(maxf(time, 0.0) / duration + seed, 1.0) if looping else clampf(time / duration, 0.0, 1.0)
	var wave := sin(u * TAU)
	var twice := sin(u * TAU * 2.0)
	var bounce := .5 - .5 * cos(u * TAU * 2.0)
	var offset := Vector3.ZERO
	var angle := 0.0
	var stretch := Vector2.ONE
	match id:
		"walk", "run", "haul", "scurry", "lumber":
			var amplitude := .035
			var tilt := .055
			if id == "run": amplitude = .075; tilt = .105
			if id == "haul": amplitude = .020; tilt = .070
			if id == "scurry": amplitude = .025; tilt = .040
			if id == "lumber": amplitude = .025; tilt = .095
			offset.y = amplitude * bounce
			angle = tilt * wave
			stretch = Vector2(1.0 - .015 * twice, 1.0 + .015 * twice)
		"climb":
			offset.x = .025 * wave
			offset.y = .045 * bounce
			angle = .095 * wave
			stretch.y = 1.0 + .025 * twice
		"stairs":
			offset.y = .045 * bounce
			angle = .035 * wave
		"fall":
			angle = .055 * wave
			stretch = Vector2(.95, 1.06)
		"land":
			var impact := _smooth(0.0, .20, u) * (1.0 - _smooth(.20, 1.0, u))
			stretch = Vector2(1.0 + .12 * impact, 1.0 - .16 * impact)
		"work_mine", "work_chop":
			# Deliberate wind-up followed by a quick stroke and slow recovery.
			var windup := _smooth(.05, .48, u) * (1.0 - _smooth(.48, .63, u))
			var strike := _smooth(.48, .63, u) * (1.0 - _smooth(.63, .95, u))
			var strength := 1.0 if id == "work_mine" else 1.3
			angle = strength * (-.10 * windup + .14 * strike)
			stretch.y = 1.0 - .06 * strike
			offset.z = .025 * strike
		"work_craft":
			var dip := .5 - .5 * cos(u * TAU)
			angle = .025 * wave
			stretch.y = 1.0 - .04 * dip
		"eat":
			var nod := pow(.5 - .5 * cos(u * TAU), 3.0)
			angle = .035 * nod
			stretch.y = 1.0 - .035 * nod
		"drink":
			var lift := _smooth(.05, .30, u) * (1.0 - _smooth(.65, .95, u))
			angle = -.07 * lift
			stretch.y = 1.0 + .025 * lift
		"attack":
			var lunge := _smooth(.28, .48, u) * (1.0 - _smooth(.48, 1.0, u))
			# Directional translation belongs to world_offset, not artwork axes.
			stretch.y = 1.0 - .045 * lunge
		"flinch":
			var recoil := _smooth(0.0, .20, u) * (1.0 - _smooth(.20, 1.0, u))
			angle = -.12 * recoil
			stretch = Vector2(1.0 + .035 * recoil, 1.0 - .035 * recoil)
		"shoot":
			var recoil := _smooth(0.0, .16, u) * (1.0 - _smooth(.16, 1.0, u))
			angle = -.045 * recoil
			stretch.y = 1.0 - .02 * recoil
		"death":
			var buckle := _smooth(0.0, .32, u)
			var collapse := _smooth(.18, .94, u)
			angle = -PI * .5 * collapse
			stretch.y = 1.0 - .12 * buckle
			# Final pose holds until the consumer hands ownership to the corpse.
		"idle":
			angle = .012 * wave
			stretch.y = 1.0 + .006 * twice
		"sleep":
			# Pose/orientation of the bed or resting sprite belongs to the consumer.
			stretch = Vector2(1.0 + .009 * wave, 1.0 + .018 * wave)
		"hop":
			var lift := pow(.5 - .5 * cos(u * TAU), 1.5)
			offset.y = .14 * lift
			stretch = Vector2(1.0 - .04 * lift, 1.0 + .05 * lift)
		"fly":
			offset.y = .045 * wave
			angle = .035 * sin(u * TAU + .5)
	output.offset = offset
	output.rotation = angle
	output.scale = stretch
	return output
