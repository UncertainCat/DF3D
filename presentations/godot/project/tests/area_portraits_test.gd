extends SceneTree
const Portraits = preload("res://scripts/area_portraits.gd")
class World extends RefCounted:
	var calls: Array = []
	var images: Dictionary = {}
	var states: Dictionary = {}
	func demand_creature_info(id): calls.append(id)
	func creature_portrait(id): return images.get(id)
	func creature_info_state(id): return states.get(id,{})
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := World.new(); var reader := Portraits.new()
	var first := TextureRect.new(); var second := TextureRect.new()
	var slots := [{"id":7,"view":first},{"id":8,"view":second}]
	reader.poll(world,slots); reader.poll(world,slots)
	check(world.calls==[7],"Visible portrait requests are serialized without duplicate polling")
	world.images[7] = GradientTexture2D.new(); world.states[7] = {"complete":true}
	reader.poll(world,slots)
	check(first.texture==world.images[7] and world.calls==[7,-1,8],"Completed portrait is displayed before the next read")
	reader.poll(world,[])
	check(world.calls[-1]==-1 and reader.active==-1,"Leaving the visible page releases its demand")
	world.images[8] = GradientTexture2D.new(); world.states[8] = {"complete":true}
	reader.poll(world,[])
	check(second.texture==null,"Late portrait never populates a departed slot")
	reader.poll(world,[slots[1]])
	check(second.texture==world.images[8] and reader.active==-1,"Returning to a cached portrait needs no new request")
	world.images.clear(); world.states={8:{"error":"Unit no longer exists"}}; second.texture=null
	reader.poll(world,[slots[1]]); reader.poll(world,[slots[1]])
	var count := world.calls.size(); reader.poll(world,[slots[1]])
	check(reader.active==-1 and world.calls.size()==count,"Rejected portrait does not loop or fabricate art")
	reader.clear(world); world.states.clear(); reader.poll(world,[slots[1]])
	check(reader.active==8,"Explicit reopening can request fresh detail")
	reader.clear(world)
	check(reader.active==-1 and reader.attempted.is_empty() and world.calls[-1]==-1,"Close/session retirement releases demand and identities")
	first.free(); second.free()
	print("AREA_PORTRAITS_PASS" if failures==0 else "AREA_PORTRAITS_FAIL")
	quit(failures)
