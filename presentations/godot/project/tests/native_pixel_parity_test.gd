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
	var plane:=MeshInstance3D.new()
	var mesh:=QuadMesh.new()
	mesh.size=Vector2(8,4)
	plane.mesh=mesh
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/native_tile_composite.gdshader")
	material.set_shader_parameter("background_tex",ImageTexture.create_from_image(background))
	material.set_shader_parameter("foreground_tex",ImageTexture.create_from_image(foreground))
	plane.material_override=material
	root.add_child(plane)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4
	camera.position.z=2
	root.add_child(camera)
	var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/native_pixel_parity.json"))
	var failures:=0
	for size in [32,48,64]:
		root.size=Vector2i(size*8,size*4)
		material.set_shader_parameter("tile_pixels",size)
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		var capture:=root.get_texture().get_image()
		capture.convert(Image.FORMAT_RGBA8)
		var hash:=HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(capture.get_data())
		var actual:=hash.finish().hex_encode()
		if actual!=reference.rgba8_sha256[str(size)]:
			failures+=1
			push_error("Native pixel mismatch at %d pixels/tile: %s" % [size,actual])
		else:print("NATIVE_PIXEL_PARITY size=%d pixels=%d exact=true" % [size,size*size*32])
	plane.queue_free()
	camera.queue_free()
	for frame in 3:await process_frame
	print("NATIVE_PIXEL_PARITY_PASS" if failures==0 else "NATIVE_PIXEL_PARITY_FAIL")
	quit(0 if failures==0 else 1)
