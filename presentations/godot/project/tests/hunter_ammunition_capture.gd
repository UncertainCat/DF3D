extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_standing_orders.json")).hunter_ammunition_reference
	var state=preload("res://scripts/hunter_ammunition_state.gd").new();state.phase=state.Phase.Ready
	state.specs=reference.before.specs.duplicate(true)
	for row: Dictionary in reference.caption_provider.specs:state.rules.append({"caption":row.caption,"quantity":int(row.assigned_quantity),"items":row.items.duplicate(true)})
	for row: Dictionary in state.rules:
		for item: Dictionary in row.items:
			for native: Dictionary in reference.appearance_reference.items:
				if item.id==native.id:
					item.appearance=native.appearance.duplicate(true);item.appearance.stack=int(item.appearance.stack);item.appearance.flags=int(item.appearance.flags)
	for caption: String in reference.caption_provider.types:state.types.append({"caption":caption})
	var view=preload("res://scripts/hunter_ammunition_view.gd").new();root.add_child(view)
	view.configure_ammunition(world,state);view.layout(Vector2(1200,800))
	for mode in [state.Mode.Main,state.Mode.Types]:
		state.mode=mode;state.changed.emit();await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/hunter-ammunition-"+str(mode)+".png"))
	for dimensions in [Vector2i(912,552),Vector2i(960,600),Vector2i(1600,900)]:
		root.size=dimensions;view.layout(Vector2(dimensions))
		for mode in [state.Mode.Main,state.Mode.Types]:
			state.mode=mode;state.changed.emit();await process_frame;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/hunter-ammunition-"+str(mode)+"-"+str(dimensions.x)+".png"))
			if dimensions.x==912:
				for down in [true,false]:
					var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
					click.position=view.scrollbar.get_global_transform_with_canvas()*Vector2(8,view.scrollbar.size.y-6 if down else 6);click.global_position=click.position
					Input.parse_input_event(click);await process_frame
					click=click.duplicate();click.pressed=false;Input.parse_input_event(click);await process_frame
					assert((state.choice_first if mode==state.Mode.Types else state.first)==(1 if down else 0))
	view.queue_free();world.queue_free();await process_frame
	print("HUNTER_AMMUNITION_CAPTURE_PASS");quit(0)
