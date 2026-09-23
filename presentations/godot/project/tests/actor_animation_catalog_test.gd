extends SceneTree

const Catalog = preload("res://scripts/actor_animation_catalog.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var ids: Dictionary = {}
	for entry in Catalog.entries():
		var id: String = entry.id
		check(not ids.has(id), "unique animation %s" % id)
		ids[id] = true
		check(entry.duration > 0.0 and not entry.trigger.is_empty(), "valid metadata %s" % id)
		check(entry.modes == ["classic", "billboard"], "explicit mode compatibility %s" % id)
		var changed := false
		var first: Dictionary = Catalog.pose(id, 0.0)
		for step in 101:
			var time: float = entry.duration * step / 100.0
			var pose: Dictionary = Catalog.pose(id, time)
			var offset: Vector3 = pose.offset
			var scale: Vector2 = pose.scale
			check(offset.is_finite() and scale.is_finite() and is_finite(pose.rotation), "finite pose %s" % id)
			check(offset.length() < .25 and scale.x > .75 and scale.y > .75, "bounded sprite deformation %s" % id)
			check(pose == Catalog.pose(id, time), "deterministic %s" % id)
			changed = changed or pose != first
		check(changed, "visible animation %s" % id)
		if entry.loop:
			var a: Dictionary = Catalog.pose(id, .123)
			var b: Dictionary = Catalog.pose(id, .123 + entry.duration)
			check(a.offset.is_equal_approx(b.offset) and a.scale.is_equal_approx(b.scale) and is_equal_approx(a.rotation, b.rotation), "seamless loop %s" % id)
		else:
			check(Catalog.pose(id, -1.0) == first, "event clamps before start %s" % id)
			check(Catalog.pose(id, entry.duration) == Catalog.pose(id, 999.0), "event holds final pose %s" % id)
			check(Catalog.pose(id, .1, .4) == Catalog.pose(id, .1, .9), "event seed does not skip onset %s" % id)
			if id != "death": check(Catalog.pose(id, entry.duration) == first, "reaction returns to rest %s" % id)
	check(ids.size() == 22, "complete animation suite including projectile-release recoil")
	var picking = preload("res://scripts/cutout_picking.gd")
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var ray := Vector3(.61, 3, 0)
	check(picking.mesh_depth(box, Transform3D.IDENTITY, ray, Vector3.DOWN) == INF, "ray misses the resting actor")
	check(picking.mesh_depth(box, Transform3D.IDENTITY, ray, Vector3.DOWN, INF, {"code":13,"elapsed":.44*.48,"seed":0.0,"strength":1.0}) < INF, "picking follows world-space lunge outside resting mesh")
	for angle in [0.0, PI / 2, PI, -PI / 2, .71]:
		var direction := Vector3(cos(angle), 0, sin(angle))
		var lunge := Catalog.world_offset(13, .44 * .48, angle)
		check(lunge.dot(direction) > .24 and is_zero_approx(lunge.y), "attack advances a readable quarter tile toward target")
		check(Catalog.world_offset(13, 0.0, angle) == Vector3.ZERO and Catalog.world_offset(13, 1.0, angle) == Vector3.ZERO, "attack returns to semantic anchor")
		check(Catalog.world_offset(13, .2, angle, 0) == Vector3.ZERO, "disabled animation has no world displacement")
		check(Catalog.world_offset(1, .2, angle) == Vector3.ZERO, "ordinary movement has no attack offset")
		for step in 101:
			check(Catalog.world_offset(13, step / 100.0, angle).length() <= .25001, "lunge is bounded to a quarter tile")
		var recoil := Catalog.world_offset(14, .22 * .20, angle)
		check(is_equal_approx(recoil.dot(direction), .08) and is_zero_approx(recoil.y), "flinch recoils along observed world direction")
		check(Catalog.world_offset(14, 0.0, angle) == Vector3.ZERO and Catalog.world_offset(14, .22, angle) == Vector3.ZERO, "flinch lasts .22 and returns to anchor")
		check(is_equal_approx(Catalog.world_offset(22, .04, angle).dot(direction), -.045), "shot recoils opposite actual release direction")
		check(Catalog.world_offset(22, 0.0, angle) == Vector3.ZERO and Catalog.world_offset(22, .25, angle) == Vector3.ZERO, "shot returns to anchor after .25 seconds")
		check(Catalog.world_offset(22, .04, angle, 0.0) == Vector3.ZERO, "disabled shot has no displacement")
		for step in 101:
			var shot: Vector3 = Catalog.world_offset(22, step / 100.0, angle)
			check(shot.length() <= .04501 and shot.dot(direction) <= .000001, "shot never lunges toward target")
	check(Catalog.world_offset(14, .04, 1000.0) == Vector3.ZERO, "unknown attacker has no invented recoil direction")
	var recoil_box := BoxMesh.new()
	recoil_box.size = Vector3(.1, .12, .1)
	var recoil_ray := Vector3(.14, 3, .02)
	check(picking.mesh_depth(recoil_box, Transform3D.IDENTITY, recoil_ray, Vector3.DOWN) == INF, "ray misses actor before recoil")
	check(picking.mesh_depth(recoil_box, Transform3D.IDENTITY, recoil_ray, Vector3.DOWN, INF, {"code":14,"elapsed":.044,"seed":0.0,"strength":1.0}) < INF, "picking follows directional flinch")
	var shot_ray := Vector3(.11, 3, 0)
	check(picking.mesh_depth(recoil_box, Transform3D.IDENTITY, shot_ray, Vector3.DOWN) == INF, "shot picking ray misses resting actor")
	check(picking.mesh_depth(recoil_box, Transform3D.IDENTITY, shot_ray, Vector3.DOWN, INF, {"code":22,"elapsed":.04,"seed":PI,"strength":1.0}) < INF, "picking follows release recoil and tilt")
	check(Catalog.pose("unknown", 1.0) == {"offset":Vector3.ZERO, "rotation":0.0, "scale":Vector2.ONE}, "unknown safely rests")
	check(Catalog.pose("walk", NAN).offset == Vector3.ZERO, "invalid time safely rests")
	check(absf(Catalog.pose("death", 100.0).rotation + PI * .5) < .0001, "death remains collapsed")
	var foot := Vector3(0.0, .07, .5)
	var head := Vector3(0.0, .07, -.5)
	check(Catalog.vertex(head, 0, 1.0, 0.0) == head, "off code preserves mesh")
	check(Catalog.vertex(head, 23, 1.0, 0.0) == head, "unknown code preserves mesh")
	check(Catalog.vertex(head, 15, 1.0, 0.0, 0.0) == head, "zero strength preserves mesh")
	check(Catalog.vertex(foot, 15, 1.0, 0.0).is_equal_approx(foot), "death pivot leaves feet anchored")
	check(Catalog.vertex(head, 15, 1.0, 0.0).is_equal_approx(Vector3(.88, .07, .5)), "death shader rotation maps upright artwork to rightward collapse")
	check(Catalog.vertex(head, 15, 1.0, 0.0, .5).is_equal_approx(Vector3(.44, .07, 0.0)), "strength mixes transformed vertex, not pose parameters")
	for code in range(1, 23):
		for t in [0.0, .19, .61, 1.37]:
			var p: Dictionary = Catalog.pose(Catalog.DEFINITIONS[code - 1][0], t, .23)
			var result: Vector3 = Catalog.vertex(head, code, t, .23)
			var expected := Vector2(head.x, .5 - head.z) * Vector2(p.scale)
			expected = expected.rotated(p.rotation) + Vector2(p.offset.x, p.offset.y)
			check(result.is_equal_approx(Vector3(expected.x, head.y + p.offset.z, .5 - expected.y)), "picking vertex matches shader artwork transform code %d" % code)
	print("ACTOR_ANIMATION_CATALOG_TEST_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
