extends SceneTree
const Controller = preload("res://scripts/walk_controller.gd")
const TestMap = preload("res://tests/walk_camera_test.gd").Map
var failures := 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func make_map():
	var map := TestMap.new()
	for x in range(16):
		for y in range(8):
			for z in range(9): map.put(x,y,z,"Floor" if z==0 else "Empty")
	return map
func pawn(map, point := Vector3(2.5,.1,2.5)):
	var controller := Controller.new()
	controller.world = map
	controller.reset(point)
	return controller
func run():
	var map = make_map()
	var body = pawn(map)
	body.jump()
	var apex := 0.0
	for i in range(150):
		body.advance(1.0/120,Vector3.ZERO)
		apex = maxf(apex,body.feet.y-.1)
	check(apex>1.2 and apex<1.35,"jump clears a full tile")
	check(absf(body.feet.y-.1)<.003 and body.grounded,"gravity lands and settles on floor")
	var positions: Array[Vector3] = []
	for fps in [30,60,144]:
		body = pawn(map)
		for frame in range(fps*2): body.advance(1.0/fps,Vector3.RIGHT)
		positions.append(body.feet)
	check(positions[0].distance_to(positions[1])<.04 and positions[0].distance_to(positions[2])<.04,"fixed-step speed independent of render FPS")
	for x in range(4,9):
		for y in range(8):
			map.put(x,y,0,"Wall")
			map.put(x,y,1,"Floor")
	body = pawn(map,Vector3(3.5,.1,2.5))
	body.jump()
	for i in range(70): body.advance(1.0/120,Vector3.RIGHT)
	check(body.feet.x>4.3 and absf(body.feet.y-1.1)<.02,"jump and horizontal input land on one-block platform")
	map = make_map()
	map.put(2,2,6,"Floor")
	body = pawn(map,Vector3(2.5,6.1,2.5))
	for i in range(240): body.advance(1.0/120,Vector3.RIGHT)
	check(body.feet.x>4 and absf(body.feet.y-.1)<.003,"walking off edge falls six levels without selecting landing")
	map = make_map()
	for x in range(16):
		for y in range(8): map.put(x,y,1,"Floor")
	body = pawn(map)
	body.jump()
	apex = 0.0
	for i in range(100):
		body.advance(1.0/120,Vector3.ZERO)
		apex = maxf(apex,body.feet.y)
	check(apex<=.381 and absf(body.feet.y-.1)<.003,"head collision stops jump under ceiling")
	map = make_map()
	for y in range(8): map.put(4,y,0,"Wall")
	body = pawn(map)
	for i in range(100): body.advance(1.0/120,Vector3(1,0,1))
	check(body.feet.x<=3.821 and body.feet.z>4,"diagonal motion slides along wall")
	map = make_map()
	map.put(3,2,0,"Ramp")
	map.put(4,2,0,"Wall")
	map.put(4,2,1,"Floor")
	body = pawn(map)
	for i in range(80): body.advance(1.0/120,Vector3.RIGHT)
	check(body.feet.x>4.2 and body.feet.y>=1.09,"ramps climb continuously without buttons")
	map = make_map()
	map.put(2,2,3,"Floor")
	body = pawn(map,Vector3(2.5,3.1,2.5))
	map.put(2,2,3,"Empty")
	for i in range(150): body.advance(1.0/120,Vector3.ZERO)
	check(absf(body.feet.y-.1)<.003,"removed floor causes fall even without movement input")
	map = make_map()
	body = pawn(map)
	var jumps := 0
	var previous_velocity := 0.0
	for i in range(300):
		body.advance(1.0/120,Vector3.ZERO,false,true)
		if body.velocity.y>6 and previous_velocity<=0: jumps += 1
		previous_velocity = body.velocity.y
	check(jumps>=3,"holding Space keeps hopping after landings")
	map.queries = 0
	body.advance(1.0/60,Vector3.RIGHT)
	check(map.queries<64,"collision reads only nearby tiles per frame")
	map = make_map()
	map.put(2,2,0,"StairUp")
	map.put(2,2,1,"StairDown")
	body = pawn(map)
	body.jump()
	for i in range(120): body.advance(1.0/120,Vector3.ZERO)
	check(absf(body.feet.y-1.1)<.003,"jump rises through native stair opening and lands upstairs")
	for i in range(120): body.advance(1.0/120,Vector3.ZERO,false,false,true)
	check(absf(body.feet.y-.1)<.003,"Q drops through stair landing without trapping body under slab")
	print("walk_controller_test: %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
