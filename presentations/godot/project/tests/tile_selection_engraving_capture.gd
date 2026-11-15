extends "res://tests/tile_selection_tabs_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var directory:=OS.get_environment("DF3D_SELECTION_REFERENCE")
	if directory.is_empty():quit(77);return
	var wire: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-wire-result.json")))
	var planned:=OS.get_environment("DF3D_SELECTION_PLANNED")=="1"
	var page: Dictionary
	if planned:
		var native_data: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json")))
		var sample: Dictionary=native_data.tile_selection_reference.engraving.planned
		var title: String=""
		for line in sample.lines:
			if str(line.text).strip_edges().begins_with("Engraving "):title=str(line.text).strip_edges();break
		page={"open":true,"receipt":9101,"kind":5,"id":-1,"title":title,"description":"","alternatives":[],"members":[]}
	else:page=wire.engraving
	root.size=Vector2i(1200,800)
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Engraving assets unavailable");return
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var service:=Service.new()
	var owner=preload("res://scripts/tile_selection_panel.gd").new();root.add_child(owner);owner.configure(world,service,host,Callable())
	owner.navigation.state.snapshot=page;owner.navigation.state.phase=owner.navigation.state.Phase.Ready
	owner.navigation.state.changed.emit();owner.navigation._selected(5 if planned else 4,-1,Vector3i(129,78,165))
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+("/workshop-selection-engraving-planned.png" if planned else "/workshop-selection-engraving.png"));native.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(416,52,488,708)
	actual.get_region(region).save_png(directory+("/selection-planned-engraving-viewer.png" if planned else "/selection-engraving-viewer.png"))
	if actual.get_region(region).get_data()!=native.get_region(region).get_data():fail("Engraving panel differs from native");return
	if planned:
		click(Vector2(500,120))
		if not owner.artwork.visible or service.request.get("receipt",0)!=9101 or service.request.get("action",-1)!=owner.C.ManagementAction.SelectionArtRead:fail("Specify image did not open receipt-owned picker");return
		owner.artwork.cancelled.emit()
		if owner.artwork.visible or owner.artwork_state.selection_receipt!=0 or host.active!=owner or owner.navigation.state.snapshot.get("receipt",0)!=9101:fail("Picker cancellation lost sheet ownership");return
	host.close_active()
	if owner.tabs.visible or not owner.navigation.state.snapshot.is_empty():fail("Closing engraving retained context");return
	host.interaction.panel.free();owner.queue_free();host.queue_free();world.queue_free();await process_frame
	print("TILE_SELECTION_ENGRAVING_CAPTURE_PASS");quit(0)
