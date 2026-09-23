extends "res://tests/mesh_batch_motion_live.gd"
# Paused visual comparison. Image readback is outside all performance captures.
func legacy_blending(node: Node, restore: Dictionary) -> void:
	if node is GeometryInstance3D:
		var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh if node is MultiMeshInstance3D and node.multimesh != null else null
		if mesh != null:
			for i in mesh.get_surface_count():
				var material: Material = node.material_override
				if material == null and node is MeshInstance3D: material = node.get_surface_override_material(i)
				if material == null: material = mesh.surface_get_material(i)
				if not material is ShaderMaterial or material.shader == null or restore.has(material.shader): continue
				var shader: Shader = material.shader
				if shader.resource_path.get_file() not in ["unit_sprite.gdshader","billboard_sprite.gdshader"]: continue
				restore[shader] = shader.code
				var code := shader.code.replace("render_mode cull_disabled, unshaded;","render_mode cull_disabled, unshaded, depth_prepass_alpha;")
				if shader.resource_path.get_file()=="unit_sprite.gdshader":
					var fragment := FileAccess.get_file_as_string("res://shaders/standee.gdshaderinc")
					fragment = fragment.insert(fragment.rfind("}"),"    ALPHA = COLOR.a;\n")
					code = code.replace('#include "standee.gdshaderinc"',fragment)
				else: code = code.insert(code.rfind("}"),"    ALPHA = COLOR.a;\n")
				shader.code = code
	for child in node.get_children(): legacy_blending(child,restore)

func run():
	root.size = Vector2i(1920,1080)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	if not scene._loader.entered: push_error("Quality load failed"); quit(1); return
	if not await set_paused(true): push_error("Quality pause failed"); quit(1); return
	await go_level(128)
	for mode in ["classic","billboard","df"]:
		scene.camera_rig.set_df_mode(mode=="df")
		scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
		for batched in [false,true]:
			scene.world.set_mesh_batching_enabled(batched)
			await settle()
			for i in 180: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"-"+mode+("-batched" if batched else "-source")+".png")
		var restore := {}
		legacy_blending(scene,restore)
		for i in 180: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"-"+mode+"-blended.png")
		for shader in restore: shader.code = restore[shader]
	print("RENDER_QUALITY_LIVE_PASS")
	quit()
