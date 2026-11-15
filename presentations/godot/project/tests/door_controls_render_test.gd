extends SceneTree
var failures:=0
class Frame:
	extends Control
	var art
	func _draw() -> void:
		var texture: Texture2D=art.texture("HOVER_RECTANGLE")
		if texture==null:return
		for y in 59:
			for x in 61:
				draw_texture_rect_region(texture,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 16 if x==60 else 8,0 if y==0 else 24 if y==58 else 12,8,12))
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var directory:=OS.get_environment("DF3D_DOOR_REFERENCE")
	var output:=OS.get_environment("DF3D_DOOR_OUTPUT")
	if directory.is_empty() or output.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):push_error("Door assets unavailable");quit(1);return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var state=preload("res://scripts/door_controls_state.gd").new()
	var view=preload("res://scripts/door_controls_view.gd").new()
	var frame=Frame.new();root.add_child(frame);frame.position=Vector2(416,52);frame.size=Vector2(488,708)
	frame.add_child(view);view.configure(world,state);frame.art=view.art;frame.queue_redraw()
	var results: Array=[]
	for sample in reference.basic_building_reference.door.presentation:
		var flags:=int(sample.flags)
		state.snapshot=sample.wire.receipts[0].duplicate(true);state.phase=state.Phase.Ready;state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var native:=Image.load_from_file(directory+"/workshop-door-state-"+str(flags)+".png");native.convert(Image.FORMAT_RGB8)
		var region:=Rect2i(424,124,472,84)
		var crop:=image.get_region(region);crop.save_png(output+"/door-controls-"+str(flags)+".png")
		var matches:=crop.get_data()==native.get_region(region).get_data()
		results.append({"flags":flags,"matches":matches})
		if not matches:failures+=1;push_error("Door controls pixels differ: "+str(flags))
	var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failures==0,"scope":"Door body control region only; recorded semantic snapshots, no main-scene integration or live edits","states":results}));file.close()
	frame.queue_free();world.queue_free();await process_frame
	if failures==0:print("DOOR_CONTROLS_RENDER_PASS")
	quit(0 if failures==0 else 1)
