extends SceneTree
const View=preload("res://scripts/location_details_view.gd")
class Service:
	extends RefCounted
	signal session_changed
	var calls: Array=[]
	func submit(domain,intent,_callback):calls.append([domain,intent]);return calls.size()
	func detach(_ticket):pass
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func _initialize() -> void:call_deferred("run")
func numbers(value):
	if typeof(value)==TYPE_FLOAT:return int(value)
	if value is Dictionary:
		for key in value:value[key]=numbers(value[key])
	elif value is Array:
		for i in value.size():value[i]=numbers(value[i])
	return value
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var model=preload("res://scripts/location_details_state.gd").new()
	var service:=Service.new();model.configure(service)
	var view=View.new();root.add_child(view);view.configure(assets,model);view.layout(Vector2(1200,800))
	var font:=Image.load_from_file(assets.ui_font_path());var frame: Image=assets.ui_texture("HOVER_RECTANGLE").get_image()
	var mapping={119288:Vector2i(0,0),119289:Vector2i(8,0),119290:Vector2i(16,0),119352:Vector2i(0,12),119353:Vector2i(8,12),119354:Vector2i(16,12),119416:Vector2i(0,24),119417:Vector2i(8,24),119418:Vector2i(16,24)}
	var palette={7:Color8(192,192,192),15:Color.WHITE,14:Color8(255,225,17),11:Color8(18,254,207),13:Color8(232,17,255)}
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_composition.json"))
	var resizing: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json")).resize_reference
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-details-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in data.cases:
		model.snapshot=numbers(sample.details.duplicate(true));model.phase=model.Phase.Ready;model.changed.emit()
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		image.save_png(directory.path_join("location_%d.png"%int(sample.details.id)))
		# Native223634 INN_TAVERN-1-before, quill at928,64 (all six kinds).
		var rename_crop:=image.get_region(Rect2i(928,64,32,36));rename_crop.convert(Image.FORMAT_RGB8)
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(rename_crop.get_data())
		assert(digest.finish().hex_encode()=="63efbc6cf2f0ab243a30dead684b741ec9f1d1907c79f8ad4d02a7b5966cccd2","native Rename artwork")
		var type_crop:=image.get_region(Rect2i(384,64,40,36));type_crop.convert(Image.FORMAT_RGB8)
		digest.start(HashingContext.HASH_SHA256);digest.update(type_crop.get_data())
		var type_hash:=digest.finish().hex_encode()
		for native_case in resizing.cases:
			if int(native_case.id)==int(sample.details.id) and native_case.name.ends_with("-default"):
				if type_hash!=native_case.type_icon_rgb_sha256:push_error("Native Details type icon "+str(sample.details.id));quit(1);return
		for cell in sample.border:
			if not mapping.has(int(cell.tile)):push_error("Unmapped native Details frame");quit(1);return
			var origin: Vector2i=mapping[int(cell.tile)]
			for y in 12:
				for x in 8:
					var expected:=frame.get_pixel(origin.x+x,origin.y+y)
					if expected.a<0.99:continue
					var actual:=image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:push_error("Native Details border mismatch");quit(1);return
		for cell in sample.cells:
			var ch:=int(cell.ch)
			if ch==0:continue
			var color: Color=palette[int(cell.fg)+(8 if cell.bold else 0)]
			for y in 12:
				for x in 8:
					var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
					if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
					var actual:=image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y)
					if absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)>0.035:push_error("Composed native Details glyph mismatch "+str(cell));quit(1);return
		if image.save_png(directory.path_join("location_%d.png"%int(sample.details.id)))!=OK:quit(1);return
		model.identity={"site_id":int(model.snapshot.site_id),"id":int(model.snapshot.id)}
		for native_case in resizing.cases:
			if int(native_case.id)!=int(sample.details.id):continue
			root.size=Vector2i(native_case.viewport[0],native_case.viewport[1]);view.layout(Vector2(root.size))
			for frame_index in 3:await process_frame;await RenderingServer.frame_post_draw
			var frame_rect:=Rect2i(native_case.frame[0],native_case.frame[1],native_case.frame[2],native_case.frame[3])
			assert(view.position==Vector2(frame_rect.position) and view.size==Vector2(frame_rect.size),"native Details frame geometry")
			image=root.get_texture().get_image()
			image.save_png(directory.path_join(native_case.name+".png"))
			var top:=image.get_region(Rect2i(frame_rect.position,Vector2i(frame_rect.size.x,4)));top.convert(Image.FORMAT_RGB8)
			var left:=image.get_region(Rect2i(frame_rect.position,Vector2i(4,frame_rect.size.y)));left.convert(Image.FORMAT_RGB8)
			digest.start(HashingContext.HASH_SHA256);digest.update(top.get_data());digest.update(left.get_data())
			if digest.finish().hex_encode()!=native_case.top_left_border_rgb_sha256:push_error("Native Details resized frame "+native_case.name);quit(1);return
			var quill_point:=Vector2(frame_rect.position)+Vector2(frame_rect.size.x-48,12)
			var quill:=image.get_region(Rect2i(Vector2i(quill_point),Vector2i(32,36)));quill.convert(Image.FORMAT_RGB8)
			digest.start(HashingContext.HASH_SHA256);digest.update(quill.get_data())
			if digest.finish().hex_encode()!=native_case.quill_rgb_sha256:push_error("Native Details resized quill "+native_case.name);quit(1);return
			if native_case.has("first_quantity_rect"):
				var q: Array=native_case.first_quantity_rect
				var quantity:=image.get_region(Rect2i(q[0],q[1],q[2],q[3]));quantity.convert(Image.FORMAT_RGB8)
				digest.start(HashingContext.HASH_SHA256);digest.update(quantity.get_data())
				if digest.finish().hex_encode()!=native_case.first_quantity_rgb_sha256:push_error("Native Details resized quantity row "+native_case.name);quit(1);return
			for region in native_case.get("staff_width_regions",[]):
				var r: Array=region.rect
				var staff:=image.get_region(Rect2i(r[0],r[1],r[2],r[3]));staff.convert(Image.FORMAT_RGB8)
				digest.start(HashingContext.HASH_SHA256);digest.update(staff.get_data())
				if digest.finish().hex_encode()!=region.rgb_sha256:push_error("Native Details staff width/art "+native_case.name);quit(1);return
			await click(quill_point+Vector2(16,18));assert(view.name_workflow.active,"resized Details quill input")
			var name_rect: Rect2=view.name_view.get_global_rect()
			await click(name_rect.position+Vector2(name_rect.size.x-64,30));assert(not view.name_workflow.active,"resized naming Done")
		service.calls.clear()
		root.size=Vector2i(1200,800);view.layout(Vector2(root.size))
		var confirmed: Array=view.heading.rows.duplicate(true)
		model.phase=model.Phase.Editing;model.changed.emit()
		if not view.visible or view.heading.rows!=confirmed or not view.access_view.buttons[0].disabled:push_error("Pending Details view lost confirmed facts");quit(1);return
		model.close()
		if view.visible or not view.heading.rows.is_empty():push_error("Closed Details view retained facts");quit(1);return
	model.snapshot=numbers(data.cases[0].details.duplicate(true));model.phase=model.Phase.Ready
	model.identity={"site_id":651,"id":int(model.snapshot.id)};model.changed.emit()
	view.input_allowed=func():return false
	await click(Vector2(944,82));assert(not view.name_workflow.active and service.calls.is_empty())
	view.input_allowed=func():return true
	await click(Vector2(944,82));assert(view.name_workflow.active and service.calls.size()==1)
	assert(view.name_view.visible and not view.heading.visible and not view.staff_view.visible and not view.quantity_view.visible and not view.rename_button.visible)
	view.name_view.entering_filter=true
	await click(Vector2(912,82));assert(not view.name_workflow.active and view.heading.visible and not view.name_view.entering_filter)
	await click(Vector2(944,82));assert(view.name_workflow.active and not view.name_view.entering_filter)
	model.close();assert(not view.name_workflow.active and not view.visible)
	view.queue_free();assets.queue_free();await process_frame
	print("LOCATION_DETAILS_VIEW_CAPTURE_PASS");quit(0)
