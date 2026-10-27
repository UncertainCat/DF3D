extends SceneTree
const View=preload("res://scripts/location_recognition_view.gd")
class Recognition:
	extends RefCounted
	enum Phase { Ready, Applying }
	var phase:=Phase.Ready
	var snapshot: Dictionary={}
class Workflow:
	extends RefCounted
	signal changed
	var recognition=Recognition.new()
	var calls:=0
	func recognize():calls+=1;recognition.phase=Recognition.Phase.Applying;changed.emit()
func _initialize() -> void:call_deferred("run")
func numbers(value):
	if typeof(value)==TYPE_FLOAT:return int(value)
	if value is Dictionary:
		for key in value:value[key]=numbers(value[key])
	elif value is Array:
		for i in value.size():value[i]=numbers(value[i])
	return value
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var background:=ColorRect.new();background.color=Color8(28,28,28);background.position=Vector2(384,196);background.size=Vector2(576,36);root.add_child(background)
	var workflow=Workflow.new();var view=View.new();root.add_child(view);view.configure(assets,workflow);view.layout(Vector2(1200,800))
	var fixture: Dictionary=numbers(JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json"))).recognition_visual_reference
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-recognition-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in fixture.cases:
		workflow.recognition.snapshot=sample.facts;workflow.recognition.phase=Recognition.Phase.Ready;workflow.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image().get_region(Rect2i(384,196,576,36));image.convert(Image.FORMAT_RGB8)
		image.save_png(directory+"/"+sample.name+".png")
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:push_error("Native recognition pixels differ: "+sample.name);quit(1);return
		var before: int=workflow.calls
		await click(Vector2(650,214));assert(workflow.calls==before)
		view.actions_enabled=false;await click(Vector2(500,214));assert(workflow.calls==before)
		view.actions_enabled=true;await click(Vector2(500,214))
		var actionable: bool=sample.facts.state in [4,5]
		assert(workflow.calls==before+(1 if actionable else 0))
		await click(Vector2(500,214));assert(workflow.calls==before+(1 if actionable else 0))
	view.queue_free();background.queue_free();assets.queue_free();await process_frame
	print("LOCATION_RECOGNITION_VIEW_PASS");quit(0)
