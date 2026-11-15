extends SceneTree
const View=preload("res://scripts/depot_goods_view.gd")
const Model=preload("res://scripts/depot_goods_state.gd")
func integers(value):
	if value is float:return int(value)
	if value is Array:
		var result: Array=[]
		for entry in value:result.append(integers(entry))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=integers(value[key])
		return result
	return value
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	var directory:=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	var world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var label:=OS.get_environment("DF3D_DEPOT_CAPTURE_CASE")
	if label.is_empty():label="anvils"
	var recorded: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-goods-wire-"+label+"-result.json")))
	var value: Dictionary=recorded.snapshot
	var model=Model.new();model.depot_id=value.depot_id;model.category=value.category;model.revision=value.revision;model.appraisal=value.get("appraisal",-1)
	model.categories=value.categories;model.groups=value.groups
	for row in value.items:model.items[row.id]=row
	for id in recorded.get("appearances",{}):model.appearances[int(id)]=recorded.appearances[id]
	model.phase=Model.Phase.Ready
	var view=View.new();root.add_child(view);view.configure_goods(world,model);view.layout(Vector2(1200,800))
	for i in 8:
		view.refresh();await process_frame
		if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	if view.page.size()!=3 or view.search.size.x!=440 or view.item_canvas.global_position!=Vector2(360,112):
		push_error("Depot native initial geometry differs");quit(1);return
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8)
		var native:=Image.load_from_file(directory+"/depot-goods-wire-"+label+".png");native.convert(Image.FORMAT_RGBA8)
		rendered.save_png(directory+"/depot-goods-view-"+label+".png")
		for rect in [Rect2i(920,112,24,36),Rect2i(872,148,72,72),Rect2i(808,76,136,36),Rect2i(416,160,432,12)]:
			if native.get_region(rect).get_data()!=rendered.get_region(rect).get_data():
				push_error("Depot status/caption pixels differ: "+str(rect));quit(1);return
		if not model.appearances.is_empty():
			var rect:=Rect2i(360,148,40,72)
			if native.get_region(rect).get_data()!=rendered.get_region(rect).get_data():
				push_error("Depot artwork pixels differ");quit(1);return
	view.queue_free();await process_frame;model.dispose();world.queue_free();await process_frame
	print("DEPOT_GOODS_VIEW_CAPTURE_PASS");quit()
