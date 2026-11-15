extends "res://tests/depot_goods_view_interaction.gd"
func respond(service,model,value: Dictionary) -> void:
	var reply: Dictionary=value.duplicate(true)
	reply.items=reply.items.filter(func(row):return service.intent.item_ids.has(row.id))
	service.observer.call(service.ticket,{"status":C.ManagementStatus.Ok,"action":C.ManagementAction.DepotGoodsRead,"depot_goods":reply},service.intent)
func compare_values(view,model,label: String) -> bool:
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
	var native:=Image.load_from_file(directory+"/depot-goods-wire-"+label+".png");native.convert(Image.FORMAT_RGBA8)
	actual.save_png(directory+"/depot-value-view-"+label+".png")
	var regions: Array[Rect2i]=[Rect2i(792,76,136,36)]
	for index in view.page.size():
		if view.page[index].has("id"):
			var y: int=112+index*36+24
			if y+12<=724:regions.append(Rect2i(736,y,160,12))
	for rect in regions:
		if actual.get_region(rect).get_data()!=native.get_region(rect).get_data():push_error("Native value/header pixels differ: "+label+" "+str(rect));return false
	return true
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	for level in [0,5,15,-1]:
		var label: String="valuation-distance-"+str(level) if level>=0 else "valuation-missing-figure"
		var value:=snapshot(label);var service:=Service.new();var model=Model.new();model.service=service
		model.depot_id=value.depot_id;model.category=value.category;model.revision=value.revision;model.appraisal=value.appraisal
		model.categories=value.categories;model.groups=value.groups
		for row in value.items:model.items[row.id]=row
		model.phase=Model.Phase.Ready
		var view=View.new();root.add_child(view);view.configure_goods(world,model);view.layout(Vector2(1200,800))
		for i in 4:await process_frame
		if model.phase!=Model.Phase.Ready or view.search.size.x!=424 or view.sort_rect(true).position+view.position!=Vector2(824,76) or view.select_all_rect().position+view.position!=Vector2(896,76):push_error("Scrollable header geometry differs");quit(1);return
		if not await compare_values(view,model,label):quit(1);return
		if level<0:
			await click_at(Vector2(872,94));await click_at(Vector2(840,94))
			if service.ticket!=0:push_error("Hidden sorting controls accepted clicks");quit(1);return
		else:
			for distance in [false,true]:
				await click_at(Vector2(840 if distance else 872,94))
				if model.phase!=Model.Phase.Reading or service.intent.sort_by_distance!=distance:push_error("Sorting hitbox submitted wrong mode");quit(1);return
				label="valuation-"+("distance-" if distance else "value-")+str(level);value=snapshot(label)
				for i in 4:
					if model.phase==Model.Phase.Reading:respond(service,model,value)
					await process_frame
				if model.phase!=Model.Phase.Ready or not await compare_values(view,model,label):quit(1);return
		view.queue_free();await process_frame;model.service=null;model.dispose()
	world.queue_free();await process_frame;print("DEPOT_GOODS_VALUE_VIEW_PASS");quit()
