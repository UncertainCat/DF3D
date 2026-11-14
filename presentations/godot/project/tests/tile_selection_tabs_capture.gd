extends "res://tests/farm_body_capture.gd"
class Service:
	extends RefCounted
	signal session_changed
	var request: Dictionary={}
	func submit(_domain,value,_observer):request=value;return 1
	func detach(_ticket):pass
func typed(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=typed(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for entry in value:result.append(typed(entry))
		return result
	return int(value) if value is float else value
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	var directory:=OS.get_environment("DF3D_SELECTION_REFERENCE")
	if directory.is_empty():quit(77);return
	root.size=Vector2i(320,160)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Selection assets unavailable");return
	var view=preload("res://scripts/tile_selection_tabs.gd").new();root.add_child(view);view.configure(world)
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-native.json"))
	var calls: Array=[];view.alternative_requested.connect(func(index):calls.append(index));view.enabled=true
	for name in ["tabs-building","item-group","item-member"]:
		var sample: Dictionary=reference.tile_selection_reference[name].state
		var tabs: Array=[]
		for row in sample.tabs:tabs.append({"kind":int(row.kind)+1,"id":int(row.id)})
		view.set_selection({"open":true,"kind":int(sample.active_kind)+1,"id":int(sample.active_id),"alternatives":tabs})
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8)
		actual.save_png(directory+"/viewer-tabs-"+name+".png")
		var native:=Image.load_from_file(directory+"/workshop-selection-"+name+".png");native.convert(Image.FORMAT_RGB8)
		# Group tab has no icon; compare its complete frame and interior. The
		# building uses a separately supplied icon, so compare only its left join.
		for y in 72:
			for x in 40:
				if y<36 and x>=8:continue
				if actual.get_pixel(x,y)!=native.get_pixel(896+x,52+y):fail("Selection frame differs: %s at %d,%d"%[name,x,y]);return
	click(Vector2(20,54))
	if calls!=[1]:fail("Selection tab did not route ordered index");return
	view.enabled=false;click(Vector2(20,18))
	if calls!=[1]:fail("Pending selection accepted tab input");return
	view.queue_free();await process_frame
	if reference.tile_selection_reference.has("item_names"):
		root.size=Vector2i(640,400)
		var service:=Service.new()
		var model=preload("res://scripts/tile_selection_state.gd").new();model.configure(service)
		var members: Array=[]
		for id in reference.tile_selection_reference["item-group"].state.items:
			members.append({"kind":2,"id":int(id),"name":reference.tile_selection_reference.item_names[str(int(id))]})
		var wire: Dictionary=typed(JSON.parse_string(FileAccess.get_file_as_string(directory+"/workshop-wire-result.json")))
		for selection in wire.selections:
			if selection.kind==7:members=selection.members;break
		model.snapshot={"open":true,"receipt":9001,"kind":7,"id":-1,"members":members}
		model.phase=model.Phase.Ready
		var group=preload("res://scripts/tile_selection_group_view.gd").new();root.add_child(group);group.configure(world,model);group.position=Vector2.ZERO
		await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGB8);actual.save_png(directory+"/viewer-item-group-body.png")
		var native:=Image.load_from_file(directory+"/workshop-selection-item-group.png");native.convert(Image.FORMAT_RGB8)
		for y in members.size()*36:
			for x in 472:
				if actual.get_pixel(x,y)!=native.get_pixel(424+x,100+y):fail("Selection group body differs at %d,%d"%[x,y]);return
		click(Vector2(100,54))
		if service.request.get("index",-1)!=1 or service.request.get("receipt",0)!=9001:fail("Group row missed selection owner");return
		service.request={};click(Vector2(100,90))
		if not service.request.is_empty():fail("Pending group accepted duplicate row");return
		group.queue_free();await process_frame;model.dispose()
	world.queue_free();await process_frame
	print("TILE_SELECTION_TABS_CAPTURE_PASS");quit(0)
