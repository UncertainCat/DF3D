extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_kitchen.json"))
	var art: Dictionary={};var captions: Dictionary={}
	for category in fixture.art_reference.categories:
		for row in category.rows:art[row.name]=row.material.material_token
	for row in fixture.display_reference.cases[0].visible:captions[row.name]=row
	var state=preload("res://scripts/kitchen_state.gd").new();state.phase=state.Phase.Ready
	for name in fixture.sort_reference.observations[0].names:
		for row in fixture.known:
			if row.name!=name:continue
			var key: Dictionary={"item_type":int(row.type),"item_subtype":int(row.subtype),"mat_type":int(row.mat),"mat_index":int(row.matg)}
			var display: Dictionary=captions.get(name,{"caption":"","estimated":false})
			state.rows.append({"receipt":{"key":key,"count":int(row.count),"capabilities":int(row.capabilities)},"name":name,"count_caption":display.caption,"estimated":display.estimated,"excluded":1,"material_token":art[name]})
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/kitchen_view.gd").new();root.add_child(view)
	view.configure_kitchen(world,state)
	for dimensions in [Vector2i(912,552),Vector2i(960,600),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=dimensions;view.layout(Vector2(dimensions))
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/kitchen-%dx%d.png"%[dimensions.x,dimensions.y]))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/kitchen.png"))
	view.queue_free();world.queue_free();await process_frame
	print("KITCHEN_CAPTURE_PASS");quit(0)
