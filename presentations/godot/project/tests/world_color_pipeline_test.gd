extends SceneTree
# Native-derived hashes cover every pixel, including alpha gradients and borders.
# All inputs are generated here; this check needs no game artwork or live process.
func _initialize(): call_deferred("run")

func run():
	root.size=Vector2i(256,128)
	root.msaa_3d=Viewport.MSAA_DISABLED
	var background:=Image.create(256,128,false,Image.FORMAT_RGBA8)
	var foreground:=Image.create(256,128,false,Image.FORMAT_RGBA8)
	var colors:=[Vector3i(93,101,107),Vector3i(20,35,80),Vector3i(190,70,30),Vector3i(180,180,180)]
	for row in 4:
		for col in 8:
			for y in 32:
				for x in 32:
					var b:Vector3i=colors[row]
					if col>=6:b=Vector3i((b.x+x*3+y*2)%256,(b.y+x*3+y*2)%256,(b.z+x*3+y*2)%256)
					var alpha:int=[0,38,64,115,128,192,255,(x*17+y*13)%256][col]
					var c:=Vector3i(255,255,255) if row<2 else Vector3i(20,40,70)
					if col>=6:c=Vector3i((x*41)%256,(y*37)%256,((x+y)*29)%256)
					if col==6:alpha=255 if (x/4+y/4)%2 else 0
					background.set_pixel(col*32+x,row*32+y,Color(b.x/255.0,b.y/255.0,b.z/255.0,1))
					foreground.set_pixel(col*32+x,row*32+y,Color(c.x/255.0,c.y/255.0,c.z/255.0,alpha/255.0))
	var ground:=MeshInstance3D.new()
	var mesh:=QuadMesh.new()
	mesh.size=Vector2(8,4)
	ground.mesh=mesh
	var base:=ShaderMaterial.new()
	base.shader=load("res://shaders/terrain.gdshader")
	base.set_shader_parameter("textured",true)
	base.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(background))
	base.set_shader_parameter("albedo_cell",Vector2(32,32))
	ground.material_override=base
	root.add_child(ground)
	var front:=MeshInstance3D.new()
	front.mesh=mesh
	front.position.z=.1
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/furniture_sprite.gdshader")
	material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(foreground))
	material.set_shader_parameter("sprite_cell",Vector2(32,32))
	front.material_override=material
	root.add_child(front)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4
	camera.position.z=2
	root.add_child(camera)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0.2,0.3,0.4)
	root.add_child(env)
	var pipeline=preload("res://scripts/world_color_pipeline.gd").new()
	pipeline.install(camera,env.environment)
	var failures:=0
	var base_bank:=Texture2DArray.new()
	var front_bank:=Texture2DArray.new()
	assert(base_bank.create_from_images([background])==OK)
	assert(front_bank.create_from_images([foreground])==OK)
	base.set_shader_parameter("batch_texture",base_bank)
	material.set_shader_parameter("batch_texture",front_bank)
	for array_mode in [false,true]:
		base.set_shader_parameter("batch_texture_enabled",array_mode)
		material.set_shader_parameter("batch_texture_enabled",array_mode)
		for msaa in [Viewport.MSAA_DISABLED,Viewport.MSAA_2X]:
			root.msaa_3d=msaa
			for size in [32,48]:
				root.size=Vector2i(size*8,size*4)
				for frame in 8:await process_frame
				await RenderingServer.frame_post_draw
				var capture:=root.get_texture().get_image()
				var reference:=Image.load_from_file(ProjectSettings.globalize_path("res://tests/data/native_auto_%d.png" % size))
				var total:=0.0
				var maximum:=0.0
				for y in capture.get_height():
					for x in capture.get_width():
						var actual:=capture.get_pixel(x,y)
						var expected:=reference.get_pixel(x,y)
						var d:=Vector3(absf(actual.r-expected.r),absf(actual.g-expected.g),absf(actual.b-expected.b))*255.0
						total+=d.x+d.y+d.z
						maximum=maxf(maximum,maxf(d.x,maxf(d.y,d.z)))
				var mean:=total/(capture.get_width()*capture.get_height()*3)
				print("WORLD_COLOR size=%d msaa=%d array=%s mean=%f max=%f" % [size,msaa,array_mode,mean,maximum])
				if mean>0.2 or maximum>3.01:failures+=1
				var output:=OS.get_environment("DF3D_COLOR_TEST_OUT")
				if not output.is_empty():capture.save_png(output+"/production-%d-%d.png" % [size,msaa])
	# Fractional magnification must retain actual source pixels when smoothing is
	# off, for both standalone textures and batch layers. On must remain available.
	pipeline.release()
	front.hide()
	root.msaa_3d=Viewport.MSAA_DISABLED
	root.size=Vector2i(384,192)
	for array_mode in [false,true]:
		base.set_shader_parameter("batch_texture_enabled",array_mode)
		for smooth in [false,true]:
			RenderingServer.global_shader_parameter_set("world_texture_smoothing",smooth)
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw
			var capture:=root.get_texture().get_image()
			var changed:=0
			for y in range(2,190):
				for x in range(290,382):
					# Exact texel boundaries can round to either neighbor on the GPU.
					if x%3==1 or y%3==1:continue
					var actual:=capture.get_pixel(x,y)
					var expected:=background.get_pixel(int((x+0.5)/1.5),int((y+0.5)/1.5))
					if maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b)))>2.0/255.0:changed+=1
			print("WORLD_SAMPLING array=%s smoothing=%s changed=%d" % [array_mode,smooth,changed])
			if (not smooth and changed>0) or (smooth and changed<100):failures+=1
	RenderingServer.global_shader_parameter_set("world_texture_smoothing",false)
	front.show()
	pipeline.install(camera,env.environment)
	base.set_shader_parameter("batch_texture_enabled",false)
	material.set_shader_parameter("batch_texture_enabled",false)
	# Overlapping transparent layers must see one another, not a stale opaque
	# screen snapshot. Keep actual spatial depth sorting and the MSAA pass.
	background.fill(Color8(20,60,160))
	foreground.fill(Color8(200,40,20,128))
	base.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(background))
	material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(foreground))
	var second:=MeshInstance3D.new()
	second.mesh=mesh
	second.position.z=.2
	second.material_override=preload("res://scripts/world_material.gd").create(Color8(20,180,60,96),false,false,null,true)
	root.add_child(second)
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var stacked:=root.get_texture().get_image().get_pixel(128,64)
	var expected_stack:=Color8(20,60,160).lerp(Color8(200,40,20),128.0/255.0).lerp(Color8(20,180,60),96.0/255.0)
	var stack_error:=maxf(absf(stacked.r-expected_stack.r),maxf(absf(stacked.g-expected_stack.g),absf(stacked.b-expected_stack.b)))*255.0
	print("WORLD_COLOR stacked_max=%f" % stack_error)
	if stack_error>2.0:failures+=1
	var original_mesh := ground.mesh.get_rid()
	var original_material := base.get_rid()
	for enabled in [false,true,false,true]:
		if enabled: pipeline.install(camera,env.environment)
		else: pipeline.release()
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var pixel := root.get_texture().get_image().get_pixel(128,64)
		var expected := expected_stack if enabled else Color8(20,60,160).srgb_to_linear().lerp(Color8(200,40,20).srgb_to_linear(),128.0/255.0).lerp(Color8(20,180,60).srgb_to_linear(),96.0/255.0).linear_to_srgb()
		var error := maxf(absf(pixel.r-expected.r),maxf(absf(pixel.g-expected.g),absf(pixel.b-expected.b)))*255.0
		print("WORLD_COLOR toggle=%s error=%f" % [enabled,error])
		if error>2.0 or pipeline.active!=enabled: failures+=1
		if ground.mesh.get_rid()!=original_mesh or base.get_rid()!=original_material: failures+=1
	second.queue_free();front.hide();ground.hide()
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var clear:=root.get_texture().get_image().get_pixel(128,64)
	if absf(clear.r-.2)+absf(clear.g-.3)+absf(clear.b-.4)>.01:failures+=1
	# A canvas color swatch must bypass world decoding.
	var swatch:=ColorRect.new()
	swatch.color=Color8(90,140,190)
	swatch.size=Vector2(24,24)
	root.add_child(swatch)
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var color:=root.get_texture().get_image().get_pixel(12,12)
	if absf(color.r-swatch.color.r)+absf(color.g-swatch.color.g)+absf(color.b-swatch.color.b)>0.01:failures+=1
	pipeline.release()
	pipeline.release()
	if pipeline.active or pipeline.users!=0:failures+=1
	swatch.queue_free();front.queue_free();ground.queue_free();camera.queue_free();env.queue_free()
	for frame in 3:await process_frame
	print("WORLD_COLOR_PIPELINE_PASS" if failures==0 else "WORLD_COLOR_PIPELINE_FAIL")
	quit(0 if failures==0 else 1)
