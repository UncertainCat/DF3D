extends SceneTree
# A transparent target card exposes sorting, then an opaque card checks depth.
# Compare effects with the
# independent CPU sprite-center convention, not the effect shader's own math.
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(640, 480)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 4, 6)
	camera.look_at(Vector3.ZERO)
	camera.size = 4
	var effects := preload("res://scripts/combat_effects.gd").new()
	scene.add_child(effects)
	effects.configure(OS.get_environment("DF3D_DF_PATH"))
	var card := MeshInstance3D.new()
	card.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Sprite materials also use Godot's transparent queue; an opaque-only card
	# cannot catch sorting based on the unlifted node origin.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.0, 0.3, 0.4, 0.8)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	card.material_override = material
	scene.add_child(card)
	var Geometry = preload("res://scripts/sprite_geometry.gd")
	var native: Image = effects.materials["COMBAT_ANIMATIONS_SWISH"].get_shader_parameter("atlas").get_image()
	for mode in ["flat", "billboard", "billboard_free"]:
		var upright: bool = mode != "flat"
		var billboard: bool = mode != "flat"
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE if mode == "billboard_free" else Camera3D.PROJECTION_ORTHOGONAL
		var anchor := Vector3.ZERO
		var axes := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		if upright:
			var reference: Transform3D = Geometry.billboard_transform(camera, Vector2.ONE, 0.03, anchor)
			axes = Basis(reference.basis.x, -reference.basis.z, reference.basis.y.normalized())
			anchor = reference.origin
		card.transform = Transform3D(axes, anchor)
		effects.set_style(upright)
		effects.reset_session()
		effects.emit_effect("HIT", Vector3.ZERO, Vector3.RIGHT, 1.0, false, 1.0)
		RenderingServer.global_shader_parameter_set("actor_animation_time", 1.01)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var total := Vector2.ZERO
		var count := 0
		for y in picture.get_height():
			for x in picture.get_width():
				var color := picture.get_pixel(x,y)
				if color.r > 0.75 and color.g > 0.75 and color.b > 0.75:
					total += Vector2(x,y)
					count += 1
		var visual_center := anchor + axes.z * (0.06 if upright else 0.18)
		var center := camera.unproject_position(visual_center)
		var centroid := total / maxf(1.0, count)
		var expected := Vector2.ZERO
		var native_pixels := 0
		# Native W/frame1 is the first 32px tile. Include its asymmetric artwork
		# rather than assuming a crescent's pixel centroid is vertically centered.
		for y in 32:
			for x in 32:
				if native.get_pixel(x,y).a < 0.1: continue
				var point := visual_center + axes.x * ((x+0.5)/32.0-0.5)*1.2 + axes.y * (0.5-(y+0.5)/32.0)*1.2
				expected += camera.unproject_position(point)
				native_pixels += 1
		expected /= native_pixels
		# Native W first-frame crescent lies left of the center, at body height.
		if count < 40 or centroid.x >= center.x - 4 or centroid.distance_to(expected) > 3:
			push_error("Hit anchor/direction mismatch %s pixels=%d center=%s expected=%s effect=%s" % [mode,count,center,expected,centroid])
			quit(1); return
		picture.save_png(ProjectSettings.globalize_path("res://../../../build/combat-anchor-" + mode + ".png"))
		print("COMBAT_ANCHOR ", mode, " pixels=", count, " center=", center, " expected=", expected, " swipe=", centroid)
		# Later transparent priority must not turn this into an X-ray overlay.
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		card.mesh.size = Vector2.ONE * 3.0
		card.position = visual_center + axes.z * 0.5
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var blocked := root.get_texture().get_image()
		var leaked := 0
		for y in blocked.get_height():
			for x in blocked.get_width():
				var color := blocked.get_pixel(x,y)
				if color.r > 0.75 and color.g > 0.75 and color.b > 0.75: leaked += 1
		if leaked > 0:
			push_error("Hit effect leaked through opaque occluder: " + mode)
			quit(1); return
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		card.mesh.size = Vector2.ONE
	scene.queue_free()
	for frame in 3: await process_frame
	print("COMBAT_ANCHOR_GPU_PASS")
	quit()
