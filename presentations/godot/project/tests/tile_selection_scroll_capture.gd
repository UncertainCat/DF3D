extends "res://tests/tile_selection_tabs_capture.gd"
func wheel(point: Vector2,page:=false,up:=false) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;event.position=point;event.shift_pressed=page
	root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)
func drag(destination: Vector2) -> void:
	var start:=Vector2(888,200)
	var motion:=InputEventMouseMotion.new();motion.position=start;motion.global_position=start;root.push_input(motion,true)
	var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true;button.position=start;button.global_position=start;root.push_input(button,true)
	motion=InputEventMouseMotion.new();motion.position=destination;motion.global_position=destination;motion.relative=destination-start;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	button.pressed=false;button.position=destination;button.global_position=destination;root.push_input(button,true)
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
		elif sample.name=="track" or sample.name.begins_with("drag-"):
			# Native oracle independently starts each track/drag probe at zero.
			owner.body.first=0;owner.body.layout(owner.panel.size.y)
			if sample.name=="track":click(Vector2(888,700))
			else:drag(Vector2(888,{"drag-top":100,"drag-middle":400,"drag-end":748}[sample.name]))
		# The native input oracle records non-hovered scrollbar artwork; hover
		# timing/hitboxes require a separate owned-pointer reference.
		var away:=InputEventMouseMotion.new();away.position=Vector2.ZERO;away.global_position=Vector2.ZERO;root.push_input(away,true)
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
		if owner.navigation.state.ticket!=0:fail("Scrolling unexpectedly selected a member: "+sample.name);return
		if owner.body.scrollbar.dragging:fail("Scrollbar retained input after drag release");return
		actual.get_region(region).save_png(directory+"/selection-scroll-"+sample.name+"-viewer.png")
		if owner.body.first!=sample.first:fail("Retained group scroll differs: %s actual=%d expected=%d"%[sample.name,owner.body.first,sample.first]);return
		if actual.get_region(region).get_data()!=native.get_region(region).get_data():fail("Group overflow pixels differ: "+sample.name);return
	if reference.tile_selection_reference.scroll.has("row_after_resize"):
		var selected: Dictionary=reference.tile_selection_reference.scroll.row_after_resize
		root.size=Vector2i(1600,900);await process_frame;await process_frame
		owner.body.first=selected.stored;owner.body.layout(owner.panel.size.y)
		click(Vector2(1000,114))
		var index: int=service.request.get("index",-1)
		if index!=selected.visible or page.members[index].id!=selected.actual or service.request.get("receipt",0)!=page.receipt:fail("Resized row click selected a different item than native");return
	host.close_active();host.interaction.panel.free();owner.queue_free();host.queue_free();world.queue_free();await process_frame
	print("TILE_SELECTION_SCROLL_CAPTURE_PASS");quit(0)
