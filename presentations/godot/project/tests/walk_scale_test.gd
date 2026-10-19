extends SceneTree
const Rig = preload("res://scripts/orbit_camera.gd")
var failures := 0
var buffers: Array[MultiMesh] = []
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func piece(parent: Node3D, x: float, color: Color, actor: bool):
	var tex := Image.create(4,4,false,Image.FORMAT_RGBA8)
	tex.fill(color)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/billboard_sprite.gdshader")
	material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(tex))
	material.set_shader_parameter("actor_scale_data",actor)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = PlaneMesh.new()
	mesh.mesh.size = Vector2.ONE
	mesh.instance_count = 1
	mesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(x,0,0)))
	mesh.set_instance_color(0,Color(1,0,1000,0) if actor else Color.WHITE)
	mesh.set_instance_custom_data(0,Color(1000,0,0,0))
	mesh.custom_aabb = AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
	buffers.append(mesh)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.material_override = material
	parent.add_child(node)
func measure(image: Image, red: bool) -> Rect2i:
	var low := Vector2i(image.get_width(),image.get_height())
	var high := Vector2i(-1,-1)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x,y)
			if (pixel.r > .8 and pixel.g < .2) if red else (pixel.g > .8 and pixel.r < .2):
				low = low.min(Vector2i(x,y))
				high = high.max(Vector2i(x,y))
	return Rect2i(low, high-low+Vector2i.ONE)
func shot() -> Image:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run():
	root.size = Vector2i(600,300)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0,.5,5)
	camera.look_at(Vector3(0,.5,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	piece(scene,-1.5,Color.RED,true)
	piece(scene,1.5,Color.GREEN,false)
	RenderingServer.global_shader_parameter_set("actor_truescale",true)
	var original := await shot()
	var actor_before := measure(original,true)
	var item_before := measure(original,false)
	var payload_before := buffers[0].buffer.duplicate()
	var rig := Rig.new()
	var visitor := Camera3D.new()
	visitor.name = "Camera3D"
	rig.add_child(visitor)
	scene.add_child(rig)
	rig.set_process(false)
	rig.walk_world = preload("res://tests/walk_camera_test.gd").Map.new()
	rig.set_mode("walk")
	camera.make_current()
	var during :=  await shot()
	var actor_after := measure(during,true)
	check(actor_before.size.x > 0 and actor_before.size.y > 0,"actor visible")
	check(actor_after == actor_before,"FPS leaves creature dimensions unchanged")
	check(absi(actor_after.end.y-actor_before.end.y)<=1,"creature stays grounded")
	check(measure(during,false)==item_before,"FPS leaves non-creature sprite unchanged")
	check(buffers[0].buffer==payload_before,"mode switch changes no resident instance data")
	rig.exit_walk()
	check(measure(await shot(),true)==actor_before,"leaving FPS keeps creature dimensions unchanged")
	print("walk_scale_test: %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
