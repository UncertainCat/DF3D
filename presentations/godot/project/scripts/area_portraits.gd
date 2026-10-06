extends RefCounted
# One read at a time, only for visible slots. Never retain a view across replies.
var active := -1
var attempted: Dictionary = {}
func clear(world) -> void:
	if active >= 0 and is_instance_valid(world): world.demand_creature_info(-1)
	active = -1; attempted.clear()
func poll(world, slots: Array) -> void:
	if not world.has_method("demand_creature_info"): return
	var wanted: Dictionary = {}
	for slot in slots: wanted[int(slot.id)] = true
	if active >= 0 and not wanted.has(active):
		world.demand_creature_info(-1); active = -1
	if active >= 0:
		var status: Dictionary = world.creature_info_state(active)
		if bool(status.get("complete",false)) or not str(status.get("error","")).is_empty():
			attempted[active] = true
			world.demand_creature_info(-1); active = -1
	for slot in slots:
		var view: TextureRect = slot.view
		if view.texture != null: continue
		var id := int(slot.id)
		view.texture = world.creature_portrait(id)
		if view.texture != null or attempted.has(id) or active >= 0: continue
		active = id; world.demand_creature_info(id)
