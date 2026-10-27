extends SceneTree
const View=preload("res://scripts/location_name_view.gd")
class State:
	extends RefCounted
	signal changed
	enum Phase { Ready, Editing }
	var phase:=Phase.Ready
	var component:=0
	var query:=PackedByteArray()
	var snapshot: Dictionary={}
	var rows: Array=[]
	var calls: Array=[]
	func set_choices(index,value):component=index;query=value;calls.append(["query",index,value]);changed.emit()
	func random_whole():calls.append(["whole"])
	func random_component(index):calls.append(["random",index])
	func clear_component(index):calls.append(["clear",index])
	func choose(index):calls.append(["choose",index])
var closes:=0
func _initialize() -> void:call_deferred("run")
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func key(code: int,unicode:=0) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=true;root.push_input(event,true)
	await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_name_editor.json")).view_reference
	var state:=State.new();state.snapshot={"native_header":reference.native_header,"english_header":reference.english_header,"value":{"words":reference.words}}
	state.rows.resize(int(reference.total));state.rows.fill({"word":0,"part":0,"english":"","translated":""})
	for index in reference.rows.size():
		state.rows[index]=reference.rows[index].duplicate(true);state.rows[index].part=int(state.rows[index].part)
	var view:=View.new();root.add_child(view);view.configure(assets,state);view.layout(Vector2(1200,800))
	view.cancelled.connect(func():closes+=1)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-name-render")
	DirAccess.make_dir_recursive_absolute(directory)
	var image:=root.get_texture().get_image();image.save_png(directory.path_join("initial.png"))
	var crop:=image.get_region(Rect2i(368,52,608,660));crop.convert(Image.FORMAT_RGB8)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
	assert(hash.finish().hex_encode()==reference.panel_rgb_sha256,"native full-panel pixel reference")
	assert(view.position==Vector2(368,52) and view.size==Vector2(608,660))
	var scroll_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_name_editor.json")).scroll_drag_reference
	for sample in scroll_reference.cases:
		view.scrollbar.move_to(0)
		if sample.name.ends_with("track-below"):await click(Vector2(952,500))
		elif sample.name.ends_with("track-above"):
			view.scrollbar.move_to(1600);await click(Vector2(952,200))
		else:
			var start:=InputEventMouseButton.new();start.position=Vector2(952,178);start.button_index=MOUSE_BUTTON_LEFT;start.pressed=true;root.push_input(start,true)
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(952,int(sample.name.get_slice("drag-",1)));root.push_input(motion,true)
			var stop:=InputEventMouseButton.new();stop.position=motion.position;stop.button_index=MOUSE_BUTTON_LEFT;stop.pressed=false;root.push_input(stop,true)
		assert(view.first==int(sample.scroll_position),"native scrollbar movement "+sample.name)
		var away:=InputEventMouseMotion.new();away.position=Vector2.ZERO;root.push_input(away,true)
		await process_frame;await RenderingServer.frame_post_draw
		crop=root.get_texture().get_image().get_region(Rect2i(944,160,16,540));crop.convert(Image.FORMAT_RGB8)
		hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		assert(hash.finish().hex_encode()==sample.scrollbar_rgb_sha256,"native scrollbar pixels "+sample.name)
	view.scrollbar.move_to(0)
	for probe in [[Vector2(744,178),MOUSE_BUTTON_WHEEL_DOWN,false,1],
		[Vector2(744,178),MOUSE_BUTTON_WHEEL_UP,false,0],
		[Vector2(744,178),MOUSE_BUTTON_WHEEL_DOWN,true,15],
		[Vector2(744,178),MOUSE_BUTTON_WHEEL_UP,true,0],
		[Vector2(476,178),MOUSE_BUTTON_WHEEL_DOWN,false,0]]:
		var wheel:=InputEventMouseButton.new();wheel.position=probe[0];wheel.button_index=probe[1];wheel.shift_pressed=probe[2];wheel.pressed=true
		root.push_input(wheel,true);await process_frame
		assert(view.first==probe[3],"native wheel binding and pointer region")
	await click(Vector2(476,358));assert(state.component==6)
	await click(Vector2(608,142));assert(state.calls[-1]==["random",0])
	await click(Vector2(668,178));assert(state.calls[-1]==["clear",1])
	await click(Vector2(832,82));assert(state.calls[-1]==["whole"])
	await click(Vector2(744,178));assert(state.calls[-1]==["choose",0])
	await click(Vector2(832,142));assert(view.entering_filter)
	var text_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_name_editor.json")).filter_input_reference
	for sample in text_reference.cases:
		state.query=PackedByteArray(sample.initial);state.changed.emit()
		for code in sample.unicode_events:
			await key(KEY_BACKSPACE if int(code)==8 else KEY_NONE,0 if int(code)==8 else int(code))
		assert(state.query==PackedByteArray(sample.expected),"native filter text input "+sample.name)
	state.query=PackedByteArray();state.changed.emit()
	for index in 12:await key(KEY_A,97)
	assert(state.query=="AAAAAAAAAA".to_ascii_buffer())
	await key(KEY_BACKSPACE);assert(state.query.size()==9)
	await key(KEY_ENTER);assert(not view.entering_filter)
	await click(Vector2(832,142));await key(KEY_ESCAPE);assert(closes==1 and not view.entering_filter)
	await click(Vector2(912,82));assert(closes==2)
	var filtered: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_name_editor.json")).filter_view_reference
	state.rows=filtered.rows.duplicate(true)
	for row in state.rows:row.part=int(row.part)
	state.query="ALE".to_ascii_buffer();state.component=6;view.entering_filter=true;view.ticks_override=750;state.changed.emit()
	await process_frame;await RenderingServer.frame_post_draw
	image=root.get_texture().get_image();image.save_png(directory.path_join("filtered.png"))
	crop=image.get_region(Rect2i(720,124,240,588));crop.convert(Image.FORMAT_RGB8)
	hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
	assert(hash.finish().hex_encode()==filtered.rgb_sha256,"native short-list columns and focused filter")
	state.query=PackedByteArray();state.changed.emit()
	await process_frame;await RenderingServer.frame_post_draw
	crop=root.get_texture().get_image().get_region(Rect2i(720,124,240,36));crop.convert(Image.FORMAT_RGB8)
	hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
	assert(hash.finish().hex_encode()==filtered.focused_empty_rgb_sha256,"native focused empty filter hides placeholder")
	var hidden_cursor:=crop.get_data()
	view.ticks_override=250;view._process(0)
	await process_frame;await RenderingServer.frame_post_draw
	crop=root.get_texture().get_image().get_region(Rect2i(720,124,240,36));crop.convert(Image.FORMAT_RGB8)
	assert(crop.get_data()!=hidden_cursor,"focused underscore blink visible")
	state.rows.resize(3217);state.rows.fill({"word":0,"part":0,"english":"","translated":""});state.changed.emit()
	view.input_allowed=func():return false
	await click(Vector2(952,694));assert(view.first==0,"blocked child scrollbar must not move")
	view.scrollbar.dragging=true
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(952,600);root.push_input(motion,true)
	assert(not view.scrollbar.dragging and view.first==0,"blocked input retires scrollbar drag")
	view.entering_filter=true;view.hide();assert(not view.entering_filter)
	view.queue_free();await process_frame;assets.queue_free();await process_frame
	print("LOCATION_NAME_VIEW_CAPTURE_PASS");quit()
