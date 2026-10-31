extends SceneTree
func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(400,160)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/creature_customize_view.gd").new()
	root.add_child(view);view.configure(world);view.position=Vector2(16,16)
	var text=preload("res://scripts/native_creature_text.gd");text.load_text(world)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var reference: Dictionary=fixture.chest_header_reference.unit_header_customize_art_reference
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/creature-customize-images")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in reference.native_cases:
		view.present(sample.caption,sample.caption,text.colors[5])
		for i in 2:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		image.save_png(directory.path_join("blank.png" if sample.caption.is_empty() else "typed.png"))
		for row in 2:
			var pixels:=image.get_region(Rect2i(16,16+row*36,288,36)).get_data()
			var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(pixels)
			if hash.finish().hex_encode()!=sample.rgb_sha256:
				push_error("Native unit Customize pixels differ: "+str(sample.caption)+" row="+str(row));quit(1);return
	var selected: Array=[];view.field_requested.connect(func(profession):selected.append(profession))
	for row in 2:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
		event.position=view.position+view.field_rect(row==1).get_center();root.push_input(event,true)
		event.pressed=false;root.push_input(event,true)
	if selected!=[false,true]:push_error("Customize field hitboxes differ");quit(1);return
	view.input_allowed=func():return false
	var blocked:=InputEventMouseButton.new();blocked.button_index=MOUSE_BUTTON_LEFT;blocked.pressed=true;blocked.position=Vector2(24,24)
	root.push_input(blocked,true)
	if selected!=[false,true]:push_error("Disabled Customize emitted field intent");quit(1);return
	view.queue_free();world.queue_free();await process_frame
	print("CREATURE_CUSTOMIZE_CAPTURE_PASS native_pixels=41472");quit(0)
