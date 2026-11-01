extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_expel_view_reference
	var failed:=false
	for sample in fixture.cases:
		var background:=ColorRect.new();background.color=Color8(28,28,28);background.position=Vector2(424,160);background.size=Vector2(472,588);root.add_child(background)
		var state=preload("res://scripts/creature_expel_state.gd").new()
		state.phase=int(sample.phase);state.destination_id=int(sample.destination);state._preview=sample.preview.duplicate(true)
		# JSON numbers are floats; normalize the typed receipt used by production.
		for row in state._preview.units:
			row.id=int(row.id);row.name_color.effect=int(row.name_color.effect)
			for layer in row.sheet_icon.layers:
				for i in layer.size():layer[i]=int(layer[i])
			for key in ["color","alternate"]:
				for i in 3:row.name_color[key][i]=int(row.name_color[key][i])
		for row in state._preview.destinations:row.id=int(row.id)
		var view=preload("res://scripts/creature_expel_view.gd").new();view.position=Vector2(424,160);view.size=Vector2(472,588)
		root.add_child(view);view.configure(world,state)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var directory:=ProjectSettings.globalize_path("res://../../../build/qa/creature-expel-images")
		DirAccess.make_dir_recursive_absolute(directory);image.save_png(directory+"/"+sample.name+".png")
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(Rect2i(424,160,472,588)).get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:push_error("Expel native pixels differ: "+sample.name);failed=true
		view.queue_free();background.queue_free();await process_frame
	world.queue_free();await process_frame
	if not failed:print("CREATURE_EXPEL_CAPTURE_PASS")
	quit(1 if failed else 0)
