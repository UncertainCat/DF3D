extends "res://tests/farm_body_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(488,708)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Item assets unavailable");return
	var view=preload("res://scripts/item_sheet_view.gd").new();root.add_child(view);view.configure(world)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var reference: Dictionary=fixture.item_sheet_render_reference
	var snapshot: Dictionary=reference.snapshot.duplicate(true)
	for key in ["id","item_type","holder_id"]:snapshot[key]=int(snapshot[key])
	view.present(snapshot)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(ProjectSettings.globalize_path("res://../../../build/item-sheet-viewer.png"))
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
	if hash.finish().hex_encode()!=reference.rgb_sha256:fail("Native item sheet pixels differ");return
	var calls: Array=[]
	view.flag_requested.connect(func(id,flag,value):calls.append([id,flag,value]))
	view.holder_requested.connect(func(id):calls.append(["holder",id]))
	view.camera_requested.connect(func(id):calls.append(["camera",id]))
	for index in 4:click(view.flag_rect(index).get_center())
	click(view.holder_rect().get_center());click(view.camera_rect().get_center())
	if calls!=[[snapshot.id,"forbid",true],[snapshot.id,"dump",true],[snapshot.id,"hidden",true],["holder",snapshot.holder_id],["camera",snapshot.id]]:fail("Item identity or eligibility routes differ");return
	calls.clear();view.pending=true;click(view.flag_rect(0).get_center())
	view.pending=false;view.input_allowed=func():return false;click(view.holder_rect().get_center())
	view.input_allowed=Callable();view.present({});click(view.camera_rect().get_center())
	if not calls.is_empty() or view.visible or view.icon!=null:fail("Item sheet retained retired input/artwork");return
	view.queue_free();world.queue_free();await process_frame
	print("ITEM_SHEET_CAPTURE_PASS");quit(0)
