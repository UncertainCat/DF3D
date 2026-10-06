extends SceneTree
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
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/location_staff_candidates_view.gd").new()
	root.add_child(view);view.configure(world);view.layout(Vector2(1200,800))
	var portraits: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_portraits.json"))
	for item in portraits.art:
		var texture: Texture2D=view.picture.texture(item.token=="BUTTON_PICTURE_BOX_SELECTED")
		if texture==null:push_error("Native picture frame missing");quit(1);return
		var region:=texture.get_image().get_region(Rect2i(int(item.x)*8,int(item.y)*12,8,12))
		region.convert(Image.FORMAT_RGBA8);region.clear_mipmaps()
		var hasher:=HashingContext.new();hasher.start(HashingContext.HASH_SHA256);hasher.update(region.get_data())
		if hasher.finish().hex_encode()!=item.rgba_sha256:push_error("Native picture frame pixels differ: "+str(item));quit(1);return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_rows.json"))
	var mapping: Dictionary={}
	for item in data.art_map:
		var texture: Texture2D=world.ui_texture(item.token)
		if texture==null:push_error("Missing native art "+str(item));quit(1);return
		mapping[int(item.tile)]={"image":texture.get_image(),"origin":Vector2i(int(item.x)*8,int(item.y)*12)}
	var font:=Image.load_from_file(world.ui_font_path())
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-staff-selector-row-images")
	DirAccess.make_dir_recursive_absolute(directory)
	var checked:=0
	for index in data.cases.size():
		var sample: Dictionary=data.cases[index]
		view.ticks_override=int(sample.ticks_ms)
		view.display_rows(numbers(sample.rows.duplicate(true)))
		for i in 2:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for cell in sample.cells:
			var source: Image=mapping[int(cell[2])].image
			var origin: Vector2i=mapping[int(cell[2])].origin
			var ch:=int(cell[3])
			for y in 12:
				for x in 8:
					var expected:=source.get_pixel(origin.x+x,origin.y+y)
					if ch not in [0,32]:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
						expected=view.colors[int(cell[4])]
					if expected.a<0.99:continue
					var actual:=image.get_pixel(int(cell[0])*8+x,int(cell[1])*12+4+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						image.save_png(directory.path_join("failure.png"))
						push_error("Native candidate row mismatch case="+str(index)+" cell="+str(cell)+" pixel="+str(Vector2i(x,y))+" expected="+str(expected)+" actual="+str(actual));quit(1);return
					checked+=1
		image.save_png(directory.path_join("rows_%02d.png"%index))
	var inputs=preload("res://tests/location_staff_candidates_input_helpers.gd")
	var scroll_rows:=inputs.recorded_order_rows(numbers(data.cases[0].rows.duplicate(true)),0,1)
	if not await inputs.replay(self,view,scroll_rows):quit(1);return
	for sample in data.cases:
		var ordered:=inputs.recorded_order_rows(numbers(sample.rows.duplicate(true)),int(sample.location_id),int(sample.role))
		if not await inputs.replay_headers(self,view,ordered,int(sample.location_id),int(sample.role)):quit(1);return
		if int(sample.location_id)==1 and int(sample.role)==0:
			if not inputs.replay_activation(self,view,ordered):quit(1);return
			if not await inputs.replay_filter_keys(self,view,ordered):quit(1);return
			if not await inputs.replay_filter_input(self,view,ordered):quit(1);return
			if not await inputs.replay_filter_navigation(self,view,ordered):quit(1);return
	view.display_rows([])
	if not view.rows.is_empty():push_error("Closed selector retained rows");quit(1);return
	view.queue_free();world.queue_free();await process_frame
	print("LOCATION_STAFF_CANDIDATES_ROWS_CAPTURE_PASS cases=",data.cases.size()," pixels=",checked);quit(0)
