extends SceneTree
func _initialize(): call_deferred("run")
func pixels() -> int:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var im=root.get_texture().get_image()
	var count := 0
	for y in im.get_height():
		for x in im.get_width():
			var c=im.get_pixel(x,y)
			if c.r>.8 and c.g>.8 and c.b>.8: count+=1
	return count
func run():
	root.size=Vector2i(320,320)
	var world:=Df3dWorld.new();root.add_child(world)
	assert(world.load_assets(OS.get_environment("DF3D_DF_PATH")))
	var camera:=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4
	camera.position=Vector3(1,10,1);camera.look_at(Vector3(1,0,1),Vector3(0,0,-1))
	var motion=preload("res://scripts/actor_motion_pool.gd").new()
	motion.reset(1)
	var address:int=motion.write(1,Color(1,1,1,0),Color(1,1,1,0),Vector2.ZERO,Vector3.ONE,0)
	motion.flush()
	var overlay=preload("res://scripts/unit_status_overlay.gd").new()
	overlay.world=world;overlay.motion=motion;root.add_child(overlay)
	overlay.set_capture_phase(6000.0)
	overlay.begin(1,[],PackedInt64Array([1]))
	overlay.observe(1,1,address,Vector3.ONE,Vector3.ONE,Vector2.ONE,Color(1,0,0,0),false)
	overlay.flush()
	assert(await pixels()>50,"Status visible with clear owner anchor")
	var cover:=MeshInstance3D.new();cover.mesh=BoxMesh.new()
	cover.mesh.size=Vector3(4,.1,4)
	var material:=StandardMaterial3D.new();material.albedo_color=Color.BLACK
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	cover.material_override=material;cover.position=Vector3(1,2,1);root.add_child(cover)
	assert(await pixels()==0,"Overlying floor hides status")
	# A wall under the offset bubble but away from its owner must not slice it.
	cover.mesh.size=Vector3(4,.1,.5);cover.position=Vector3(1,2,.35)
	assert(await pixels()>50,"Adjacent wall does not hide visible owner's bubble")
	var uploads:int=overlay.uploads
	overlay.set_capture_phase(5000.0)
	assert(await pixels()==0,"Native movement-only window includes phase5000")
	overlay.set_capture_phase(5001.0)
	assert(await pixels()>50,"Primary window begins at5001")
	assert(overlay.uploads==uploads,"Cadence changes uniforms, never instance payloads")
	print("UNIT_STATUS_DEPTH_PASS");quit()
