extends SceneTree
func _initialize() -> void:call_deferred("run")
func integers(value):
	if value is float:return int(value)
	if value is Array:
		for index in value.size():value[index]=integers(value[index])
	elif value is Dictionary:
		for key in value:value[key]=integers(value[key])
	return value
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	var reference: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_standing_orders.json"))).chores_reference
	var directory:=ProjectSettings.globalize_path("res://../../../"+str(reference.appearance_reference.capture))
	if directory.is_empty() or not FileAccess.file_exists(directory+"/chores-rows.json"):push_error("Native Chores row capture required");quit(1);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var state=preload("res://scripts/chores_state.gd").new();state.phase=state.Phase.Ready
	var native: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/standing-orders-native.json"))).chores
	state.snapshot={"enabled":native.enabled,"children":PackedInt32Array(native.children),"exempted":PackedInt32Array(native.exempted),"labors":native.labors}
	state.children=reference.captions_reference.captions.children
	state.labors=reference.captions_reference.captions.labors
	var view=preload("res://scripts/chores_view.gd").new();root.add_child(view)
	view.configure_chores(world,state);view.layout(Vector2(1200,800));view.ticks_override=0
	view.display_rows(integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/chores-rows.json"))))
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/chores.png"))
	for dimensions in [Vector2i(912,552),Vector2i(960,600),Vector2i(1600,900)]:
		root.size=dimensions;view.layout(Vector2(dimensions));state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/chores-"+str(dimensions.x)+".png"))
		if dimensions.x==912:
			for bar in [view.scrollbar,view.labor_scrollbar]:
				for down in [true,false]:
					await pointer(bar,Vector2(8,bar.size.y-6 if down else 6),MOUSE_BUTTON_LEFT)
					if bar.first!=(1 if down else 0):push_error("Chores arrow differs from native");quit(1);return
				for page in [false,true]:
					for down in [true,false]:
						await pointer(view,Vector2(80 if bar==view.scrollbar else 400,200),MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP,page)
						var expected:=mini(bar.page,bar.count-bar.page) if page else 1
						if bar.first!=(expected if down else 0):push_error("Chores wheel differs from native");quit(1);return
	root.size=Vector2i(1200,800);view.layout(Vector2(1200,800))
	for mode in ["disable","enable","child-toggle","child-restore","labor-toggle","labor-restore"]:
		if mode=="disable":state.snapshot.enabled=false
		if mode=="enable":state.snapshot.enabled=true
		if mode=="child-toggle":state.snapshot.exempted=PackedInt32Array([state.snapshot.children[0]])
		if mode=="child-restore":state.snapshot.exempted=PackedInt32Array()
		if mode=="labor-toggle":state.snapshot.labors[0].enabled=false
		if mode=="labor-restore":state.snapshot.labors[0].enabled=true
		state.changed.emit();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/chores-state-"+mode+".png"))
	view.queue_free();world.queue_free();await process_frame
	print("CHORES_CAPTURE_PASS");quit(0)


func pointer(view,point: Vector2,button: int,shift: bool=false) -> void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=true;event.shift_pressed=shift
	event.position=view.get_global_transform_with_canvas()*point;event.global_position=event.position
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
