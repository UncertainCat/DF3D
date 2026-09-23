extends "res://scripts/walk_ground.gd"
# Local kinematic visitor. Fixed steps, real velocity, gravity and swept tile
# collisions; no chosen landing, cardinal snapping, or ledge traversal paths.
const HEIGHT := 0.62
const TICK := 1.0 / 120.0
const GRAVITY := 20.0
const JUMP_SPEED := 7.2 # A little over one tile of clearance in open space.
const WALK_SPEED := 3.2
const SPRINT_SPEED := 5.2
const STEP_HEIGHT := 0.20
const SKIN := 0.0001
var feet := Vector3.ZERO
var previous := Vector3.ZERO
var velocity := Vector3.ZERO
var grounded := false
var _accumulator := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0

func reset(point: Vector3) -> void:
	feet = point
	begin_step()
	# A ramp's high footprint edge supports the body, not its center sample.
	if world != null and collides(feet) and not collides(feet+Vector3.UP*STEP_HEIGHT):
		feet += Vector3.UP*STEP_HEIGHT
		_sweep(Vector3.DOWN*STEP_HEIGHT)
	previous = feet
	velocity = Vector3.ZERO
	grounded = false
	_accumulator = 0.0
	_coyote = 0.0
	_jump_buffer = 0.0

func jump() -> void:
	_jump_buffer = 0.12

func collides(point: Vector3, through_stairs := false) -> bool:
	var head := point.y + HEIGHT
	for x in range(floori(point.x-RADIUS+SKIN),floori(point.x+RADIUS-SKIN)+1):
		for y in range(floori(point.z-RADIUS+SKIN),floori(point.z+RADIUS-SKIN)+1):
			for z in range(floori(point.y+SKIN),floori(head-SKIN)+1):
				var tile := Vector3i(x,y,z)
				var kind := shape(tile)
				if kind in ["Unknown","Wall","Fortification","TreeTrunk"]: return true
				if int(info(tile).get("liquid_level",0)) >= 4: return true
				if kind in ["Empty","RampTop","TreeBranch","TreeTwig"]: continue
				var top := float(z) + FLOOR
				# Stair openings act as one-way landings: rise through them, or
				# drop through with Q, without getting caught below their slab.
				if kind in ["StairUp","StairDown","StairUpDown"] and (through_stairs or feet.y<top-SKIN): continue
				if kind == "Ramp":
					top = float(z)
					for px in [maxf(x+SKIN,point.x-RADIUS),minf(x+1.0-SKIN,point.x+RADIUS)]:
						for py in [maxf(y+SKIN,point.z-RADIUS),minf(y+1.0-SKIN,point.z+RADIUS)]:
							top = maxf(top,surface(Vector3(px,0,py),z))
				if point.y < top-SKIN: return true
	return false

func _sweep(delta: Vector3, through_stairs := false) -> bool:
	var count := maxi(1,ceili(delta.length()/0.045))
	var step := delta/count
	for i in range(count):
		if not collides(feet+step,through_stairs):
			feet += step
			continue
		var low := 0.0
		var high := 1.0
		for iteration in range(10):
			var middle := (low+high)*0.5
			if collides(feet+step*middle,through_stairs): high = middle
			else: low = middle
		feet += step*low
		return true
	return false

func _horizontal(delta: Vector3, can_step: bool) -> void:
	var start := feet
	if not _sweep(delta): return
	if not can_step: return
	# Step only small lips and ramp increments. A full block needs a jump.
	var stopped := feet
	feet = start
	if not _sweep(Vector3.UP*STEP_HEIGHT) and not _sweep(delta):
		_sweep(Vector3.DOWN*STEP_HEIGHT)
		return
	feet = stopped

func _tick(wish: Vector3, sprint: bool, jump_held: bool, descend: bool) -> void:
	previous = feet
	var on_stairs := shape(Vector3i(floori(feet.x),floori(feet.z),floori(feet.y))) in ["StairDown","StairUpDown"]
	var dropping := descend and on_stairs
	grounded = velocity.y<=0.0 and collides(feet+Vector3.DOWN*.012,dropping)
	_coyote = 0.08 if grounded else maxf(0.0,_coyote-TICK)
	_jump_buffer = maxf(0.0,_jump_buffer-TICK)
	if jump_held: _jump_buffer = 0.12
	var jumping := _jump_buffer>0.0 and _coyote>0.0 and not dropping
	if jumping:
		velocity.y = JUMP_SPEED
		grounded = false
		_coyote = 0.0
		_jump_buffer = 0.0
	var target := wish.limit_length()*(SPRINT_SPEED if sprint else WALK_SPEED)
	var acceleration := 48.0 if grounded else 16.0
	velocity.x = move_toward(velocity.x,target.x,acceleration*TICK)
	velocity.z = move_toward(velocity.z,target.z,acceleration*TICK)
	_horizontal(Vector3(velocity.x*TICK,0,0),grounded and not jumping)
	_horizontal(Vector3(0,0,velocity.z*TICK),grounded and not jumping)
	if grounded and not jumping and not dropping:
		var before := feet
		if not _sweep(Vector3.DOWN*STEP_HEIGHT): feet = before
	velocity.y = maxf(velocity.y-GRAVITY*TICK,-24.0)
	if dropping: velocity.y = maxf(velocity.y,-3.0)
	var descending := velocity.y<=0.0
	if _sweep(Vector3(0,velocity.y*TICK,0),not descending or dropping):
		velocity.y = 0.0
		grounded = descending
	else: grounded = false

func advance(delta: float, wish: Vector3, sprint := false, jump_held := false, descend := false) -> Vector3:
	begin_step()
	_accumulator += clampf(delta,0.0,0.1)
	while _accumulator >= TICK:
		_tick(wish,sprint,jump_held,descend)
		_accumulator -= TICK
	return previous.lerp(feet,_accumulator/TICK)
