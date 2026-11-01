extends SceneTree
func _initialize() -> void:call_deferred("run")
func motion(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;root.push_input(event,true)
func mouse(point: Vector2,button: int,pressed: bool,shift:=false) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;event.shift_pressed=shift;root.push_input(event,true)
func input_cases(view,mode: String,reference: Dictionary) -> bool:
	var expected:Dictionary={}
	for row in reference.observations:expected[row.name]=row
	var failures:Array=[]
	var observe:=func(name):
		var native:Dictionary=expected[mode+"-input-"+name]
		if view.first!=int(native.first) or view.scrollbar.dragging!=native.dragging:failures.append(name+": first="+str(view.first)+", dragging="+str(view.scrollbar.dragging))
	var reset:=func():
		view.scrollbar.dragging=false;motion(Vector2(400,400));view.first=7;view.refresh()
	var bottom:=694 if mode=="group" else 730
	for sample in [["up-left",874,166],["up-right",880,166],["down-left",874,bottom],["down-right",880,bottom],["track",880,200]]:
		reset.call();await process_frame
		var point:=Vector2(sample[1],sample[2]);motion(point);mouse(point,MOUSE_BUTTON_LEFT,true);mouse(point,MOUSE_BUTTON_LEFT,false)
		await process_frame;observe.call(sample[0])
	reset.call();await process_frame
	motion(Vector2(880,400));mouse(Vector2(880,400),MOUSE_BUTTON_LEFT,true);await process_frame;observe.call("drag-start")
	motion(Vector2(880,300));await process_frame;observe.call("drag-move")
	mouse(Vector2(880,300),MOUSE_BUTTON_LEFT,false);await process_frame;observe.call("drag-release")
	for sample in [["CONTEXT_SCROLL_UP",MOUSE_BUTTON_WHEEL_UP,false,880,400],["CONTEXT_SCROLL_DOWN",MOUSE_BUTTON_WHEEL_DOWN,false,880,400],["CONTEXT_SCROLL_PAGEUP",MOUSE_BUTTON_WHEEL_UP,true,880,400],["CONTEXT_SCROLL_PAGEDOWN",MOUSE_BUTTON_WHEEL_DOWN,true,880,400],["wheel-body",MOUSE_BUTTON_WHEEL_DOWN,false,600,400],["wheel-footer",MOUSE_BUTTON_WHEEL_DOWN,false,600,730],["wheel-outside",MOUSE_BUTTON_WHEEL_DOWN,false,400,400]]:
		reset.call();await process_frame
		var point:=Vector2(sample[3],sample[4]);motion(point);mouse(point,sample[1],true,sample[2]);mouse(point,sample[1],false,sample[2])
		await process_frame;observe.call(sample[0])
	reset.call();await process_frame;motion(Vector2(880,400))
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_PAGEUP;event.pressed=pressed;root.push_input(event,true)
	await process_frame;observe.call("STANDARDSCROLL_PAGEUP")
	for failure in failures:push_error("Expel native input differs: "+mode+" "+failure)
	return failures.is_empty()
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_expel_view_reference
	var failed:=false
	var samples:Array=fixture.cases.duplicate(true)
	for layout in fixture.get("layout_reference",{}).get("cases",[]):
		var sample:Dictionary=fixture.cases[1].duplicate(true)
		sample.destination=-1
		for key in layout:sample[key]=layout[key]
		sample.preview.units=[];sample.preview.destinations=[]
		for i in 24:
			if sample.phase==2:sample.preview.destinations.append({"id":-1,"name":""})
			else:sample.preview.units.append(fixture.cases[1].preview.units[0].duplicate(true))
		samples.append(sample)
	for sample in samples:
		var dimensions:Array=sample.get("window",[1200,800]);root.size=Vector2i(int(dimensions[0]),int(dimensions[1]))
		var bounds:Array=sample.get("region",[424,160,472,588]);var region:=Rect2i(int(bounds[0]),int(bounds[1]),int(bounds[2]),int(bounds[3]))
		var background:=ColorRect.new();background.color=Color8(28,28,28);background.position=region.position;background.size=region.size;root.add_child(background)
		var state=preload("res://scripts/creature_expel_state.gd").new()
		state.phase=int(sample.phase);state.destination_id=int(sample.destination);state._preview=sample.preview.duplicate(true)
		# JSON numbers are floats; normalize the typed receipt used by production.
		for row in state._preview.units:
			row.id=int(row.id);row.name_color.effect=int(row.name_color.effect)
			for layer in row.sheet_icon.layers:
				for i in layer.size():layer[i]=int(layer[i])
			for key in ["color","alternate"]:
				for i in 3:row.name_color[key][i]=int(row.name_color[key][i])
		for row in state._preview.destinations:row.id=int(row.id)
		var view=preload("res://scripts/creature_expel_view.gd").new();view.position=region.position;view.size=region.size;view.first=int(sample.get("first",0))
		root.add_child(view);view.configure(world,state)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var directory:=ProjectSettings.globalize_path("res://../../../build/qa/creature-expel-images")
		DirAccess.make_dir_recursive_absolute(directory);image.save_png(directory+"/"+sample.name+".png")
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(region).get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:push_error("Expel native pixels differ: "+sample.name);failed=true
		if sample.name in ["layout-group-default","layout-destinations-default"]:
			if not await input_cases(view,"group" if sample.phase==3 else "destinations",fixture.layout_reference.input_reference):failed=true
		view.queue_free();background.queue_free();await process_frame
	world.queue_free();await process_frame
	if not failed:print("CREATURE_EXPEL_CAPTURE_PASS")
	quit(1 if failed else 0)
