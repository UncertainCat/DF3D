extends "res://tests/depot_goods_view_capture.gd"
const Hover=preload("res://scripts/native_hover_view.gd")
func move_to(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;Input.parse_input_event(event);await process_frame
func run() -> void:
	Engine.max_fps=30
	var directory:=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	var data_directory:=OS.get_environment("DF3D_DEPOT_DATA_DIRECTORY")
	if directory.is_empty() or data_directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var facts: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-goods-native.json"))
	var world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var model=Model.new();model.phase=Model.Phase.Ready
	var view=View.new();root.add_child(view);view.configure_goods(world,model)
	var hover=Hover.new();root.add_child(hover);hover.configure(world);hover.layout(Vector2(1200,800));view.hover_help=hover
	for row in facts.hover.cases:
		var scrolling: bool=row.label.begins_with("scroll-")
		var label: String="valuation-distance-0" if scrolling else "anvils"
		var value: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(data_directory+"/depot-goods-wire-"+label+"-result.json"))).snapshot
		model.category=value.category;model.categories=value.categories;model.groups=value.groups;model.items={}
		for item in value.items:model.items[item.id]=item
		# Appraisal gates the header only in this tooltip-region comparison.
		model.appraisal=0 if row.instruction<0 else 1
		view.layout(Vector2(1200,800));hover.reset()
		await move_to(Vector2(row.x,row.y))
		if row.instruction<0:
			if not hover.state.key.is_empty() or hover.visible:push_error("Hidden sort control acquired hover");quit(1);return
			continue
		var key: String={201:"exclude",202:"distance",203:"value",204:"select-all"}[int(row.instruction)]
		if hover.state.key!="depot_goods_"+key or hover.visible:push_error("Header hover target/cold delay differs");quit(1);return
		if Hover.DEPOT_GOODS_HELP[key]!=row.lines:push_error("Native tooltip copy differs");quit(1);return
		hover.state.started=Time.get_ticks_msec()-501;hover._process(0)
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
		actual.save_png(directory+"/depot-hover-view-"+row.label+".png")
		# Native text/hitbox evidence is valid; native GPU capture remains pending.
		if not hover.visible or hover.displayed!="depot_goods_"+key:push_error("Delayed tooltip did not render");quit(1);return
	await move_to(Vector2(500,500))
	if hover.visible:push_error("Leaving header retained tooltip");quit(1);return
	await move_to(Vector2(808,94));view.hide();await process_frame
	if hover.visible or not hover.state.key.is_empty():push_error("Hidden picker retained hover ownership");quit(1);return
	view.queue_free();await process_frame;model.dispose();hover.queue_free();world.queue_free();await process_frame
	print("DEPOT_GOODS_HOVER_VIEW_PASS");quit()
