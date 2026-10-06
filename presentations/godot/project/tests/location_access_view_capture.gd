extends SceneTree
const View=preload("res://scripts/location_access_view.gd")
class State:
	extends RefCounted
	signal changed
	enum Phase { Ready, Editing }
	var phase:=Phase.Ready
	var ticket:=0
	var snapshot: Dictionary={}
	var calls: Array=[]
	func set_access(mode: int): calls.append(mode)
func _initialize() -> void: call_deferred("run")
func click(control: Control) -> void:
	var point:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
	await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1);return
	var state=State.new();var view=View.new();root.add_child(view);view.configure(assets,state)
	view.position=Vector2(384,112);view.size=Vector2(576,36)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_access_visual.json"))
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-access-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in fixture.cases:
		state.snapshot=sample.details.duplicate();state.snapshot.kind=int(state.snapshot.kind);state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for mode in sample.icons.size():
			var expected: Image=assets.ui_texture(sample.icons[mode]).get_image()
			if expected.get_size()!=Vector2i(32,36): push_error("Native access graphic dimensions differ");quit(1);return
			for y in 36:
				for x in 32:
					var color:=expected.get_pixel(x,y)
					if color.a<0.99: continue
					var actual:=image.get_pixel(384+mode*32+x,112+y)
					if absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)>0.03:
						push_error("Permission graphic pixels differ from captured native rectangle mapping");quit(1);return
		var ink:=0;var color:=Color8(int(sample.rgb[0]),int(sample.rgb[1]),int(sample.rgb[2]))
		for y in 12:
			for x in str(sample.label).length()*8:
				var pixel:=image.get_pixel(int(sample.label_cell.x)*8+x,124+y)
				if absf(pixel.r-color.r)+absf(pixel.g-color.g)+absf(pixel.b-color.b)<0.03: ink+=1
		if ink==0: push_error("Permission label absent from native cell rectangle/color");quit(1);return
		if image.save_png(directory.path_join("location_%d_mask_%d.png"%[int(sample.id),int(sample.mask)]))!=OK:quit(1);return
		for mode in sample.icons.size():
			var before: int=state.calls.size();await click(view.buttons[mode])
			if state.calls.size()!=before+1 or state.calls[-1]!=mode:push_error("Permission click intent mismatch");quit(1);return
		state.phase=state.Phase.Editing;state.ticket=1;state.changed.emit()
		var before: int=state.calls.size();await click(view.buttons[0])
		if state.calls.size()!=before:push_error("Pending permission edit sent again");quit(1);return
		state.phase=state.Phase.Ready;state.ticket=0
	view.queue_free();assets.queue_free();await process_frame
	print("LOCATION_ACCESS_VIEW_CAPTURE_PASS")
	quit(0)
