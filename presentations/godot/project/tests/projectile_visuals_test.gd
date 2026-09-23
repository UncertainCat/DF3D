extends SceneTree
const Visuals = preload("res://scripts/projectile_visuals.gd")
class World extends RefCounted:
	var ids := PackedInt64Array([1,2,3])
	var positions := PackedVector3Array([Vector3(1,1.6,1),Vector3(1,.6,1),Vector3(1,2.6,1)])
	func projectile_ids(): return ids
	func projectile_positions(): return positions
	func projectile_directions():
		var values := PackedVector3Array()
		values.resize(ids.size())
		values.fill(Vector3.RIGHT)
		return values
	func get_top_z(): return 1
	func get_window_depth(): return 1

func _initialize():
	for direction in [Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD]:
		var pose: Transform3D = Visuals.pose(Vector3.ONE, direction)
		assert(pose.origin == Vector3.ONE)
		assert(pose.basis.z.dot(direction) > .999)
		assert(is_equal_approx(pose.basis.determinant(), 1.0))
	var world := World.new()
	var visual := Visuals.new()
	root.add_child(visual)
	var mesh := visual.multimesh.mesh
	visual.update(world)
	assert(visual.multimesh.instance_count == 1) # Respect the current cutaway.
	var writes := visual.transform_writes
	visual.update(world)
	assert(visual.transform_writes == writes) # Paused and camera-only frames are free.
	world.positions[0].x += 1
	visual.update(world)
	assert(visual.transform_writes == writes + 1 and visual.multimesh.mesh == mesh)
	world.ids.clear()
	world.positions.clear()
	visual.update(world)
	assert(visual.multimesh.instance_count == 0)
	print("PROJECTILE_VISUALS_PASS")
	quit()
