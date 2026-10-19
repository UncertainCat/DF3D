extends SceneTree
# A red tile surrounded by green atlas cells makes wrong-cell sampling visible.
# Coplanar tiles cover the viewport, including pixels whose MSAA samples span
# adjacent primitives. Fractional camera offsets exercise edge extrapolation.
var failures := 0

func _initialize(): call_deferred("run")

func run():
	root.size = Vector2i(256,256)
	var image := Image.create(12,12,false,Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	image.fill_rect(Rect2i(4,4,4,4),Color.RED)
	image.generate_mipmaps()
	var bank := Texture2DArray.new()
	var neighbor := image.duplicate() as Image
	neighbor.fill(Color.GREEN)
	neighbor.generate_mipmaps()
	assert(bank.create_from_images([neighbor,image])==OK)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("textured",true)
	material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(image))
	material.set_shader_parameter("albedo_cell",Vector2(4,4))
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var centers := PackedFloat32Array()
	var layers := PackedFloat32Array()
	var indices := PackedInt32Array()
	for y in range(-6,6):
		for x in range(-6,6):
			var base := vertices.size()
			for corner in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)]:
				vertices.append(Vector3(x+corner.x,y+corner.y,0))
				uvs.append((Vector2.ONE+corner)/3.0)
				colors.append(Color.WHITE)
				centers.append_array(PackedFloat32Array([0.5,0.5,0.5,0.5]))
				layers.append(1.0)
			for index in [0,1,2,0,2,3]: indices.append(base+index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_TEX_UV2]=uvs
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_CUSTOM2]=centers
	arrays[Mesh.ARRAY_CUSTOM0]=layers
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	var instance := MeshInstance3D.new()
	instance.mesh=mesh
	instance.material_override=material
	root.add_child(instance)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.position.z=2
	root.add_child(camera)
	for mode in ["terrain", "array", "spatter", "cutout", "furniture", "furniture_array", "ghost"]:
		material.shader=load("res://shaders/standee_ghost.gdshader" if mode=="ghost" else ("res://shaders/furniture_sprite.gdshader" if mode.begins_with("furniture") else ("res://shaders/terrain_cutout.gdshader" if mode=="cutout" else "res://shaders/terrain.gdshader")))
		material.set_shader_parameter("textured",true)
		material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(image))
		material.set_shader_parameter("albedo_cell",Vector2(4,4))
		material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(image))
		material.set_shader_parameter("sprite_cell",Vector2(4,4))
		material.set_shader_parameter("batch_texture_enabled",mode=="array" or mode=="furniture_array")
		material.set_shader_parameter("batch_texture",bank)
		if mode!="cutout":
			material.set_shader_parameter("spattered",mode=="spatter")
			material.set_shader_parameter("spatter_tex",ImageTexture.create_from_image(image))
			material.set_shader_parameter("spatter_cell",Vector2(4,4))
		await check_offsets(camera,material,mode)
	# Native outlines/shadows include 128-alpha pixels. Geometry coverage alone
	# must not turn these into fully opaque colors against the floor.
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color.BLUE
	root.world_3d.environment=environment
	image.fill_rect(Rect2i(4,4,4,4),Color(1,0,0,0.5))
	image.generate_mipmaps()
	# A closed furniture volume has a reverse-facing underside. It must not
	# blend a second copy of its shadow through the visible top surface.
	var underside := MeshInstance3D.new()
	underside.mesh=mesh
	underside.material_override=material
	underside.rotation.y=PI
	underside.position.z=-0.1
	root.add_child(underside)
	for shader in ["furniture_sprite", "standee_ghost"]:
		material.shader=load("res://shaders/"+shader+".gdshader")
		material.set_shader_parameter("batch_texture_enabled",false)
		material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(image))
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var pixel := root.get_texture().get_image().get_pixel(128,128)
		if pixel.r<.5 or pixel.r>.9 or pixel.b<.5 or pixel.g>.02:
			failures+=1
			print("FURNITURE_ALPHA shader=%s pixel=%s" % [shader,pixel])
	# Foreground priority must not leave statue artwork floating in angled views.
	# The same resident mesh carries a native-only lift above a green occluder.
	underside.hide()
	instance.rotation.x=-PI/2
	image.fill_rect(Rect2i(4,4,4,4),Color.RED)
	image.generate_mipmaps()
	material.set_shader_parameter("sprite_tex",ImageTexture.create_from_image(image))
	var occluder := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(20,20)
	occluder.mesh=plane
	occluder.position.y=.25
	var green := StandardMaterial3D.new()
	green.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	green.albedo_color=Color.GREEN
	occluder.material_override=green
	root.add_child(occluder)
	for shader in ["furniture_sprite", "standee_ghost"]:
		material.shader=load("res://shaders/"+shader+".gdshader")
		for top_down in [true,false]:
			camera.position=Vector3(0,3,0) if top_down else Vector3(0,3,1)
			camera.look_at(Vector3.ZERO,Vector3.BACK if top_down else Vector3.UP)
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var pixel := root.get_texture().get_image().get_pixel(128,128)
			var expected := Color.RED if top_down else Color.GREEN
			if absf(pixel.r-expected.r)+absf(pixel.g-expected.g)+absf(pixel.b-expected.b)>.05:
				failures+=1
				print("FURNITURE_VIEW_DEPTH shader=%s top_down=%s pixel=%s" % [shader,top_down,pixel])
	print("TERRAIN_SEAMS_PASS" if failures==0 else "TERRAIN_SEAMS_FAIL")
	quit(0 if failures==0 else 1)

func check_offsets(camera: Camera3D,material: ShaderMaterial,mode: String):
	for zoom in [3.77,5.0,7.13]:
		camera.size=zoom
		for offset in [0.0,0.013,0.037]:
			camera.position.x=offset
			camera.position.y=offset
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			var bad := 0
			for y in range(8,248):
				for x in range(8,248):
					var c := capture.get_pixel(x,y)
					if c.r < .9 or c.g > .02 or c.b > .02: bad+=1
			if bad:
				failures+=1
				print("SEAM pixels=%d mode=%s zoom=%s offset=%s" % [bad,mode,zoom,offset])
