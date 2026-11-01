extends "res://tests/farm_body_capture.gd"
func motion(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;root.push_input(event,true)
func mouse(point: Vector2,button: int,pressed: bool,shift:=false) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;event.shift_pressed=shift;root.push_input(event,true)
func contained_cases(view,reference: Dictionary) -> bool:
	root.size=Vector2i(1200,800);view.position=Vector2(424,208);view.size=Vector2(472,540);view.first=0
	view.rows=[];view.icons=[]
	for index in 16:
		view.rows.append({"name":"","related_id":-1,"facts":[{"key":"row_kind","has_number":true,"number":1}]});view.icons.append(null)
	for index in reference.contents.size():
		var source: Dictionary=reference.contents[index]
		view.rows[index+1]={"name":source.caption,"related_id":int(source.id),"facts":[{"key":"row_kind","has_number":true,"number":int(source.kind)}]}
	view.layout();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-items-contained.png"))
	for sample in reference.caption_regions:
		var r: Array=sample.rect;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
		hash.update(image.get_region(Rect2i(r[0],r[1],r[2],r[3])).get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:fail("Native contained row caption/View pixels differ: "+sample.name);return false
	var requests: Array=[]
	var observe:=func(kind,id):requests.append([kind,id])
	view.inspect_requested.connect(observe)
	for index in 2:
		var point: Vector2=view.inspect_rect(index+1).get_center()
		var kind: String=view.hover_kind(point)
		if preload("res://scripts/native_hover_view.gd").UNIT_HELP.get(kind,[])!=reference.navigation.targets[index].lines:fail("Contained View help differs");return false
		click(view.get_global_transform_with_canvas()*point)
	if requests!=[[2,int(reference.contents[0].id)],[1,int(reference.contents[1].id)]]:fail("Contained View targets differ");return false
	var missing: Vector2=view.inspect_rect(3).get_center()
	if not view.hover_kind(missing).is_empty():fail("Missing contained target exposes help");return false
	click(view.get_global_transform_with_canvas()*missing)
	if requests.size()!=2:fail("Missing contained target navigated");return false
	var clear:=image.get_pixel(400,320)
	for y in range(316,352):
		for x in range(424,864):
			if image.get_pixel(x,y)!=clear:fail("Unresolved contained row is not blank");return false
	view.inspect_requested.disconnect(observe)
	return true
func layout_cases(view,reference: Dictionary) -> bool:
	view.rows=[];view.icons=[]
	for index in int(reference.count):
		view.rows.append({"name":"","related_id":-1,"facts":[]});view.icons.append(null)
	for sample in reference.cases:
		root.size=Vector2i(sample.viewport[0],sample.viewport[1])
		view.position=Vector2(sample.view_rect[0],sample.view_rect[1]);view.size=Vector2(sample.view_rect[2],sample.view_rect[3]);view.first=0;view.layout()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		if view.capacity()!=int(sample.capacity):fail("Native Items capacity differs: "+sample.name);return false
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var r: Array=sample.scrollbar_rect;var crop:=image.get_region(Rect2i(r[0],r[1],r[2],r[3]))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-items-layout-"+sample.name+".png"))
		if hash.finish().hex_encode()!=sample.scrollbar_rgb_sha256:fail("Native Items scrollbar pixels differ: "+sample.name);return false
	var expected: Dictionary={};for sample in reference.input:expected[sample.name]=sample
	var failures: Array=[]
	var observe:=func(name):
		if view.first!=int(expected[name].first) or view.scrollbar.dragging!=expected[name].dragging:failures.append(name+": "+str(view.first)+", dragging="+str(view.scrollbar.dragging))
	var reset:=func():
		view.scrollbar.dragging=false;motion(Vector2(400,400));view.first=7;view.layout()
	for sample in [["up-left",874,214],["up-right",880,214],["down-left",874,706],["down-right",880,706],["track",880,260],["track-below",880,600]]:
		reset.call();await process_frame;click(Vector2(sample[1],sample[2]));observe.call("input-"+sample[0])
	reset.call();await process_frame;motion(Vector2(880,400));mouse(Vector2(880,400),MOUSE_BUTTON_LEFT,true);observe.call("drag-start")
	motion(Vector2(880,300));observe.call("drag-move");mouse(Vector2(880,300),MOUSE_BUTTON_LEFT,false);observe.call("drag-release")
	for sample in [["CONTEXT_SCROLL_UP",MOUSE_BUTTON_WHEEL_UP,false],["CONTEXT_SCROLL_DOWN",MOUSE_BUTTON_WHEEL_DOWN,false],["CONTEXT_SCROLL_PAGEUP",MOUSE_BUTTON_WHEEL_UP,true],["CONTEXT_SCROLL_PAGEDOWN",MOUSE_BUTTON_WHEEL_DOWN,true]]:
		reset.call();motion(Vector2(600,400));mouse(Vector2(600,400),sample[1],true,sample[2]);mouse(Vector2(600,400),sample[1],false,sample[2]);observe.call(sample[0])
	for sample in [["body",600,400],["padding",600,730],["footer",600,770],["outside",400,400]]:
		reset.call();var point:=Vector2(sample[1],sample[2]);motion(point);mouse(point,MOUSE_BUTTON_WHEEL_DOWN,true);mouse(point,MOUSE_BUTTON_WHEEL_DOWN,false);observe.call("wheel-"+sample[0])
	view.first=20;view.size.y=648;view.layout();observe.call("tail-wide")
	root.size=Vector2i(960,600);view.position=Vector2(184,204);view.size=Vector2(472,348)
	view.rows=[];view.icons=[]
	for index in 12:
		view.rows.append({"name":"","related_id":32064,"facts":[{"key":"row_kind","has_number":true,"number":0},{"key":"assignment_indicator","has_number":true,"number":1}]});view.icons.append(null)
	view.first=2;view.layout()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var scrolled:=root.get_texture().get_image();scrolled.convert(Image.FORMAT_RGB8)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(scrolled.get_region(Rect2i(568,204,24,36)).get_data())
	if hash.finish().hex_encode()!=reference.small_clothing_rgb_sha256:failures.append("scrolled clothing artwork")
	for failure in failures:push_error("Items native input differs: "+failure)
	return failures.is_empty()
# Component inputs are the native reference's semantic assignments. This checks
# installed artwork and help, separately from the composed live transport test.
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Items assets unavailable");return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_items_reference.indicator_reference
	var view=preload("res://scripts/creature_items_view.gd").new()
	root.add_child(view);view.position=Vector2(424,208);view.size=Vector2(472,540)
	var row: Dictionary={"name":"","related_id":32064,"facts":[
		{"key":"row_kind","number":0,"has_number":true},
		{"key":"assignment_indicator","number":-1,"has_number":true}]}
	view.configure(world,[row])
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world)
	var requests: Array=[];view.inspect_requested.connect(func(kind,id):requests.append([kind,id]))
	var gate: Dictionary={"blocked":false};view.input_allowed=func():return not gate.blocked
	for sample in reference.cases:
		var indicator:=int({291:0,292:2,293:3,294:1}.get(int(sample.hover),-1))
		row.facts[1].number=indicator;view.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var crop:=image.get_region(Rect2i(824,208,24,36))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		if hash.finish().hex_encode()!=sample.indicator_rgb_sha256:fail("Native Items indicator pixels differ: "+sample.name);return
		image.save_png(ProjectSettings.globalize_path("res://../../../build/creature-items-"+sample.name+".png"))
		var kind: String=view.hover_kind(view.indicator_rect(0).get_center())
		if indicator<0:
			if not kind.is_empty():fail("Unassigned inventory has indicator help");return
		else:
			if help.UNIT_HELP.get(kind,[])!=sample.lines:fail("Native Items tooltip text differs: "+sample.name);return
			help.enter_unit(view.get_instance_id(),kind)
			await create_timer(0.55).timeout;await process_frame;await RenderingServer.frame_post_draw
			if not help.visible or help.displayed!="unit_"+kind:fail("Items tooltip did not render: "+sample.name);return
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/creature-items-help-"+sample.name+".png"))
			help.leave(view.get_instance_id())
		click(view.get_global_transform_with_canvas()*view.indicator_rect(0).get_center())
		if not requests.is_empty():fail("Indicator click navigated");return
		gate.blocked=true
		if not view.hover_kind(view.indicator_rect(0).get_center()).is_empty():fail("Blocked Items exposes help");return
		click(view.get_global_transform_with_canvas()*view.inspect_rect(0).get_center())
		if not requests.is_empty():fail("Blocked Items navigated");return
		gate.blocked=false
	click(view.get_global_transform_with_canvas()*view.inspect_rect(0).get_center())
	if requests!=[[2,32064]]:fail("Inventory View target differs");return
	var layout_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_items_reference.layout_reference
	if not await layout_cases(view,layout_reference):quit(1);return
	var contained_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_items_reference.contained_navigation_reference
	if not await contained_cases(view,contained_reference):quit(1);return
	view.queue_free();help.queue_free();world.queue_free();await process_frame
	print("CREATURE_ITEMS_CAPTURE_PASS");quit(0)
