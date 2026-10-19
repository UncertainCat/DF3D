extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")

func piece(height: float, lift: float, row: float, color: Color) -> MeshInstance3D:
	var node = preload("res://scripts/furniture_order.gd").new()
	node.set_meta("df3d_sort_lift",lift)
	node.set_meta("df3d_sort_row",row)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,height,-1),Vector3(1,height,-1),Vector3(1,height,1),Vector3(-1,height,1)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	arrays[Mesh.ARRAY_CUSTOM2]=PackedFloat32Array([.5,.5,lift,0,.5,.5,lift,0,.5,.5,lift,0,.5,.5,lift,0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/furniture_sprite.gdshader")
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(color)
	material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(image))
	mesh.surface_set_material(0,material)
	node.mesh=mesh
	root.add_child(node)
	return node

func run():
	root.size=Vector2i(128,128)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4
	root.add_child(camera)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	root.add_child(env)
	var pipeline=preload("res://scripts/world_color_pipeline.gd").new()
	pipeline.install(camera,env.environment)
	# Foreground is physically lower, but its native top-view spill is lifted
	# above the background. Half-alpha must blend even where no prepass writes.
	var front=piece(0,.4,1,Color8(200,40,20,128))
	var back=piece(.2,0,0,Color8(20,60,160))
	var mesh_id=front.mesh.get_rid()
	var material_id=front.mesh.surface_get_material(0).get_rid()
	for msaa in [Viewport.MSAA_DISABLED,Viewport.MSAA_2X]:
		root.msaa_3d=msaa
		for eye in [Vector3(0,5,0),Vector3(0,5,5),Vector3(5,5,0),Vector3(0,5,-5),Vector3(-5,5,0),Vector3(0,5,0)]:
			camera.position=eye
			var top: bool = eye.z==0 and eye.x==0
			camera.look_at(Vector3.ZERO,Vector3.FORWARD if top else Vector3.UP)
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw
			var actual:=root.get_texture().get_image().get_pixel(64,64)
			var expected:=Color8(20,60,160).lerp(Color8(200,40,20),128.0/255.0) if top else Color8(20,60,160)
			var error:=maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b)))*255
			if error>2.0:
				failures+=1
				push_error("furniture ordering eye=%s msaa=%s error=%s" % [eye,msaa,error])
			if not top and front.sorting_offset!=0:failures+=1
			if front.mesh.get_rid()!=mesh_id or front.mesh.surface_get_material(0).get_rid()!=material_id:failures+=1
	pipeline.release()
	front.queue_free();back.queue_free();camera.queue_free();env.queue_free()
	for frame in 4:await process_frame
	print("FURNITURE_ORDER_PASS" if failures==0 else "FURNITURE_ORDER_FAIL")
	quit(0 if failures==0 else 1)
