extends "res://tests/tile_selection_tabs_capture.gd"
func wheel(point: Vector2,page:=false,up:=false) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;event.position=point;event.shift_pressed=page
	root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var directory:=OS.get_environment("DF3D_SELECTION_REFERENCE")
	if directory.is_empty():quit(77);return
	var reference: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json")))
	var wire: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-wire-result.json")))
	var page: Dictionary={}
	for selection in wire.selections:
		if selection.kind==7:page=selection;break
	if page.is_empty():fail("Missing overflow wire page");return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Selection assets unavailable");return
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var service:=Service.new()
	var owner=preload("res://scripts/tile_selection_panel.gd").new();root.add_child(owner);owner.configure(world,service,host,Callable())
	owner.navigation.state.snapshot=page;owner.navigation.state.phase=owner.navigation.state.Phase.Ready
	owner.navigation.state.changed.emit();owner.navigation._selected(7,-1,Vector3i(102,70,165))
	for sample in reference.tile_selection_reference.scroll.samples:
		var native:=Image.load_from_file(directory+"/workshop-selection-scroll-"+sample.name+".png");native.convert(Image.FORMAT_RGB8)
		root.size=native.get_size();await process_frame;await process_frame
		if sample.name=="wheel":wheel(Vector2(600,154))
		elif sample.name=="page":wheel(Vector2(600,154),true)
		elif sample.name=="arrow":click(Vector2(888,736))
		elif sample.name=="wide-wheel":wheel(Vector2(1000,154),false,true)
		# The native input oracle records non-hovered scrollbar artwork; hover
		# timing/hitboxes require a separate owned-pointer reference.
		var away:=InputEventMouseMotion.new();away.position=Vector2.ZERO;away.global_position=Vector2.ZERO;root.push_input(away,true)
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
		if owner.navigation.state.ticket!=0:fail("Scrolling unexpectedly selected a member: "+sample.name);return
		actual.get_region(region).save_png(directory+"/selection-scroll-"+sample.name+"-viewer.png")
		if owner.body.first!=sample.first:fail("Retained group scroll differs: %s actual=%d expected=%d"%[sample.name,owner.body.first,sample.first]);return
		if actual.get_region(region).get_data()!=native.get_region(region).get_data():fail("Group overflow pixels differ: "+sample.name);return
	host.close_active();host.interaction.panel.free();owner.queue_free();host.queue_free();world.queue_free();await process_frame
	print("TILE_SELECTION_SCROLL_CAPTURE_PASS");quit(0)
