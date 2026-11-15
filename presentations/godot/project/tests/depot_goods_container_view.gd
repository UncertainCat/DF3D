extends "res://tests/depot_goods_view_interaction.gd"
func respond_container(service,value: Dictionary) -> void:
	var reply: Dictionary=value.duplicate(true)
	reply.items=reply.items.filter(func(row):return service.intent.item_ids.has(row.id))
	if service.intent.has("container_id"):
		var first: int=service.intent.container_offset
		reply.container.offset=first
		reply.container.items=reply.container.items.slice(first,first+service.intent.container_limit)
	else:reply.erase("container")
	service.observer.call(service.ticket,{"status":C.ManagementStatus.Ok,"action":C.ManagementAction.DepotGoodsRead,"depot_goods":reply},service.intent)
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var recorded: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-goods-wire-container-page-result.json")))
	var value: Dictionary=recorded.snapshot;var service:=Service.new();var model=Model.new();model.service=service
	model.depot_id=value.depot_id;model.category=value.category;model.revision=value.revision;model.appraisal=value.appraisal
	model.categories=value.categories;model.groups=value.groups
	for row in value.items:model.items[row.id]=row
	for id in recorded.appearances:model.appearances[int(id)]=recorded.appearances[id]
	model.phase=Model.Phase.Ready
	var view=View.new();root.add_child(view);view.configure_goods(world,model);view.layout(Vector2(1200,800))
	for i in 3:await process_frame
	var before: int=model.row_count()
	await click_at(Vector2(500,166))
	if model.phase!=Model.Phase.Reading or service.intent.get("container_id")!=value.container.parent_id:push_error("Container click did not request visible children");quit(1);return
	respond_container(service,value)
	# Replay native artwork replies after the requested children become owned.
	for id in recorded.appearances:
		if model.item_type(int(id))>=0:model.appearances[int(id)]=recorded.appearances[id]
	view.refresh()
	for i in 4:await process_frame
	if model.phase!=Model.Phase.Ready or model.row_count()!=before+10:push_error("Container row height differs");quit(1);return
	await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
	var native:=Image.load_from_file(directory+"/depot-container-expanded.png");native.convert(Image.FORMAT_RGBA8)
	actual.save_png(directory+"/depot-container-view-expanded.png")
	for rect in [Rect2i(416,172,224,12),Rect2i(376,184,568,360)]:
		if actual.get_region(rect).get_data()!=native.get_region(rect).get_data():push_error("Container pixels differ: "+str(rect));quit(1);return
	var calls: int=service.ticket
	await click_at(Vector2(500,202));await click_at(Vector2(916,202))
	if service.ticket!=calls or model.row_count()!=before+10 or not model._draft.is_empty():push_error("Child click changed parent or hauling intent");quit(1);return
	await click_at(Vector2(500,166))
	if model.row_count()!=before or service.ticket!=calls:push_error("Parent collapse did not remain local");quit(1);return
	view.queue_free();await process_frame;model.service=null;model.dispose();world.queue_free();await process_frame
	print("DEPOT_GOODS_CONTAINER_VIEW_PASS");quit()
