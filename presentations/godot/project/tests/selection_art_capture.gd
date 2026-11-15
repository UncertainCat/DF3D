extends "res://tests/tile_selection_tabs_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var directory:=OS.get_environment("DF3D_SELECTION_REFERENCE")
	if directory.is_empty():quit(77);return
	var wire: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-wire-result.json")))
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Artwork assets unavailable");return
	var service:=Service.new()
	var state=preload("res://scripts/selection_art_state.gd").new();state.configure(service)
	var view=preload("res://scripts/work_order_details_view.gd").new();root.add_child(view)
	view.engraving_context=true;view.job_context=true;view.configure_details(world,state)
	for label in ["root","site_page"]:
		var page: Dictionary=wire[label].duplicate(true)
		state.selection_receipt=page.receipt;state.selected=0;state.snapshot=page;state.snapshot.selected_option=0
		state.rows=page.art.rows.duplicate(true);state.phase=state.Phase.Ready;state.ticket=0;state.first=0;state.art_base=0
		state.changed.emit();view.layout(Vector2(1200,800));view.show()
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		var native:=Image.load_from_file(directory+("/workshop-selection-engraving-image-picker.png" if label=="root" else "/workshop-selection-engraving-image-option-2.png"));native.convert(Image.FORMAT_RGB8)
		var region:=Rect2i(72,52,832,672)
		actual.get_region(region).save_png(directory+"/selection-art-"+label+"-viewer.png")
		if actual.get_region(region).get_data()!=native.get_region(region).get_data():fail("Artwork "+label+" differs from native");return
		click(Vector2(100,202))
		if service.request.get("receipt",0)!=state.selection_receipt:fail("Artwork click lost selected tile receipt");return
		var expected_action: int=state.C.ManagementAction.SelectionArtRead if label=="root" else state.C.ManagementAction.SelectionArtApply
		if service.request.get("action",-1)!=expected_action:fail("Artwork click used wrong action");return
	state.dispose();view.queue_free();world.queue_free();await process_frame
	print("SELECTION_ART_CAPTURE_PASS");quit(0)
