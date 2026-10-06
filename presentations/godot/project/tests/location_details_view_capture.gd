extends SceneTree
const View=preload("res://scripts/location_details_view.gd")
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
	var view=View.new();root.add_child(view);view.configure(assets,model);view.layout(Vector2(1200,800))
	var font:=Image.load_from_file(assets.ui_font_path());var frame: Image=assets.ui_texture("HOVER_RECTANGLE").get_image()
	var mapping={119288:Vector2i(0,0),119289:Vector2i(8,0),119290:Vector2i(16,0),119352:Vector2i(0,12),119353:Vector2i(8,12),119354:Vector2i(16,12),119416:Vector2i(0,24),119417:Vector2i(8,24),119418:Vector2i(16,24)}
	var palette={7:Color8(192,192,192),15:Color.WHITE,14:Color8(255,225,17),11:Color8(18,254,207),13:Color8(232,17,255)}
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_composition.json"))
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-details-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in data.cases:
		model.snapshot=numbers(sample.details.duplicate(true));model.phase=model.Phase.Ready;model.changed.emit()
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
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
		var confirmed: Array=view.heading.rows.duplicate(true)
		model.phase=model.Phase.Editing;model.changed.emit()
		if not view.visible or view.heading.rows!=confirmed or not view.access_view.buttons[0].disabled:push_error("Pending Details view lost confirmed facts");quit(1);return
		model.close()
		if view.visible or not view.heading.rows.is_empty():push_error("Closed Details view retained facts");quit(1);return
	view.queue_free();assets.queue_free();await process_frame
	print("LOCATION_DETAILS_VIEW_CAPTURE_PASS");quit(0)
