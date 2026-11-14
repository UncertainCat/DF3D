extends "res://tests/tile_selection_tabs_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var directory:=OS.get_environment("DF3D_SELECTION_REFERENCE")
	if directory.is_empty():quit(77);return
	var wire: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-wire-result.json")))
	var page: Dictionary=wire.selections[0]
	if page.get("kind")!=6:fail("Missing unit group page");return
	root.size=Vector2i(1200,800)
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Unit group assets unavailable");return
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var service:=Service.new()
	var owner=preload("res://scripts/tile_selection_panel.gd").new();root.add_child(owner);owner.configure(world,service,host,Callable())
	owner.navigation.state.snapshot=page;owner.navigation.state.phase=owner.navigation.state.Phase.Ready
	owner.navigation.state.changed.emit();owner.navigation._selected(6,-1,Vector3i(102,70,165))
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/workshop-selection-unit-group.png");native.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(416,52,488,708)
	actual.get_region(region).save_png(directory+"/selection-unit-group-viewer.png")
	if actual.get_region(region).get_data()!=native.get_region(region).get_data():fail("Unit group panel differs from native");return
	click(Vector2(600,154))
	if service.request.get("index",-1)!=1 or service.request.get("receipt",0)!=page.receipt:fail("Unit row did not use current member receipt");return
	host.close_active()
	if owner.tabs.visible or not owner.navigation.state.snapshot.is_empty():fail("Closing unit group retained context");return
	host.interaction.panel.free();owner.queue_free();host.queue_free();world.queue_free();await process_frame
	print("TILE_SELECTION_UNIT_CAPTURE_PASS");quit(0)
