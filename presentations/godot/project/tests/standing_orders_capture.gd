extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_standing_orders.json"))
	var state=preload("res://scripts/standing_orders_state.gd").new();state.phase=state.Phase.Ready
	for id in 11:state.settings.append({"id":id,"value":int(reference.workshop_cycles[id].initial) if id<8 else 0,"available":id<8})
	var view=preload("res://scripts/standing_orders_view.gd").new();root.add_child(view)
	view.configure_standing_orders(world,state);view.layout(Vector2(1200,800))
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/standing-orders-workshops.png"))
	view.queue_free();world.queue_free();await process_frame
	print("STANDING_ORDERS_CAPTURE_PASS");quit(0)
