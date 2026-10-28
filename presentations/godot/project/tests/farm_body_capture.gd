extends SceneTree
class Model:
	extends RefCounted
	signal changed
	enum Phase {Ready,Applying}
	var phase:=Phase.Ready
	var ticket:=0
	var building_id:=227
	var season:=1
	var snapshot: Dictionary={}
	var calls: Array=[]
	func choices() -> Array:return snapshot.get("choices",[]).duplicate(true)
	func choose_crop(id: int) -> void:calls.append(["crop",id])
	func select_season(value: int) -> void:calls.append(["season",value])
	func toggle_fertilization() -> void:calls.append(["fertilize"])
	func set_seasonal_fertilization(value: bool) -> void:calls.append(["seasonal",value])
func _initialize() -> void:call_deferred("run")
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(480,320)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Farm assets unavailable");return
	var background:=ColorRect.new();root.add_child(background)
	background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12);background.size=Vector2(480,320)
	var model:=Model.new()
	var view=preload("res://scripts/farm_body_view.gd").new();root.add_child(view);view.configure(world,model)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	for reference in fixture.body_reference.cases:
		model.snapshot=reference.snapshot.duplicate(true)
		model.season=int(model.snapshot.selected_season);model.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image().get_region(Rect2i(0,0,456,300));image.convert(Image.FORMAT_RGB8)
		image.save_png(ProjectSettings.globalize_path("res://../../../build/farm-body-"+str(reference.name)+".png"))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
		if hash.finish().hex_encode()!=reference.rgb_sha256:fail("Farm body pixels differ: "+str(reference.name));return
	click(Vector2(440,18));click(Vector2(440,54));click(Vector2(20,280));click(Vector2(228,280))
	if model.calls!=[["crop",-1],["crop",175],["fertilize"],["seasonal",false]]:fail("Farm control routes differ");return
	model.calls.clear();click(Vector2(80,18));click(Vector2(80,280))
	if not model.calls.is_empty():fail("Farm labels activated checkbox actions");return
	model.phase=Model.Phase.Applying;model.changed.emit();click(Vector2(440,18));click(Vector2(20,280))
	if not model.calls.is_empty():fail("Pending farm body accepted duplicate actions");return
	model.phase=Model.Phase.Ready;view.input_allowed=func():return false;click(Vector2(228,280))
	if not model.calls.is_empty():fail("Farm body bypassed owner input gate");return
	view.queue_free();world.queue_free();background.queue_free();await process_frame
	print("FARM_BODY_CAPTURE_PASS");quit(0)
