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
	await click(Vector2(476,358));assert(state.component==6)
	await click(Vector2(608,142));assert(state.calls[-1]==["random",0])
	await click(Vector2(668,178));assert(state.calls[-1]==["clear",1])
	await click(Vector2(832,82));assert(state.calls[-1]==["whole"])
	await click(Vector2(744,178));assert(state.calls[-1]==["choose",0])
	await click(Vector2(832,142));assert(view.entering_filter)
	for index in 12:await key(KEY_A,97)
	assert(state.query=="AAAAAAAAAA".to_ascii_buffer())
	await key(KEY_BACKSPACE);assert(state.query.size()==9)
	await key(KEY_ENTER);assert(not view.entering_filter)
	await click(Vector2(832,142));await key(KEY_ESCAPE);assert(closes==1 and not view.entering_filter)
	await click(Vector2(912,82));assert(closes==2)
	view.queue_free();await process_frame;assets.queue_free();await process_frame
	print("LOCATION_NAME_VIEW_CAPTURE_PASS");quit()
