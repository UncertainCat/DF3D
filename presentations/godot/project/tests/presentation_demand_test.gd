extends SceneTree
const Demand = preload("res://scripts/presentation_demand.gd")
func _initialize(): call_deferred("run")
func run():
	var camera := Camera3D.new()
	root.add_child(camera)
	root.size = Vector2i(1280,720)
	camera.position = Vector3(30,30,50)
	camera.look_at(Vector3(30,10,20))
	for projection in [Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_ORTHOGONAL]:
		camera.projection = projection
		camera.size = 40
		var bounds := Demand.region(camera,20,12,4)
		# Every projected screen ray intersecting the slab must be inside demand.
		for x in range(0,1281,80):
			for y in range(0,721,80):
				var screen := Vector2(x,y)
				var origin := camera.project_ray_origin(screen)
				var direction := camera.project_ray_normal(screen)
				for level in [8.0,20.0,25.0]:
					if absf(direction.y)<0.00001: continue
					var t: float = (level-origin.y)/direction.y
					if t<camera.near or t>camera.far: continue
					var point: Vector3 = origin+direction*t
					assert(bounds.has_point(Vector2i(floori(point.x),floori(point.z))))
		var before := bounds
		camera.position.x += 0.00001
		assert(Demand.region(camera,20,12,4)==before)
	camera.free()
	print("PRESENTATION_DEMAND_PASS")
	quit()
