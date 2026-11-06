extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/residents/native_job_settings.json"))
	var source: Dictionary=fixture.provider_reference.provider
	var state=preload("res://scripts/job_settings_state.gd").new()
	state.building_id=int(source.building_id);state.job_id=int(source.job_id);state.selected=int(source.selected)
	state.snapshot={"caption":source.caption,"options":source.options,"selected_option":state.selected}
	for i in source.materials.size():
		var material: Dictionary=source.materials[i]
		var row: Dictionary={"id":i,"caption":material.caption}
		# The original native capture supplies the visible count text, including
		# bookkeeper estimates. Do not derive an estimate from the raw count.
		if i<16:
			var line: String=fixture.reference.lines[14+i*3].text
			var count:=line.substr(112,7).strip_edges()
			if not count.is_empty():row.count_caption=count;row.estimated=count.ends_with("?")
		state.rows.append(row)
	state.phase=state.Phase.Ready
	var view=preload("res://scripts/work_order_details_view.gd").new();view.job_context=true;root.add_child(view);view.configure_details(world,state);view.layout(Vector2(1200,800))
	for frame in 3:await process_frame;await RenderingServer.frame_post_draw
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/job-settings-view-images")
	DirAccess.make_dir_recursive_absolute(directory);root.get_texture().get_image().save_png(directory+"/materials.png")
	view.queue_free();state.dispose();world.queue_free();await process_frame
	print("JOB_SETTINGS_VIEW_CAPTURE_PASS");quit()
