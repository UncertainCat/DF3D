extends SceneTree
func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/location_staff_candidates_frame.gd").new()
	root.add_child(view);view.configure(world);view.layout(Vector2(1200,800))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_selector_frame.json"))
	var mapping: Dictionary={}
	for item in data.art_map:
		var texture: Texture2D=world.ui_texture(item.token,int(item.index)) if item.kind=="strip" else world.ui_texture(item.token)
		if texture==null:push_error("Missing native art "+str(item));quit(1);return
		mapping[int(item.tile)]={"image":texture.get_image(),"origin":Vector2i(int(item.get("x",0))*8,int(item.get("y",0))*12)}
	var font:=Image.load_from_file(world.ui_font_path())
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-staff-selector-frame-images")
	DirAccess.make_dir_recursive_absolute(directory)
	var checked:=0
	for index in data.cases.size():
		var sample: Dictionary=data.cases[index]
		view.display(int(sample.total),0,int(sample.active_header),sample.descending)
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
						if int(cell[4]) not in [0,8]:push_error("Unmapped native header color");quit(1);return
						expected=Color.BLACK if int(cell[4])==0 else Color8(160,160,160)
					if expected.a<0.99:continue
					var actual:=image.get_pixel(int(cell[0])*8+x,int(cell[1])*12+4+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						image.save_png(directory.path_join("failure.png"))
						push_error("Native selector frame mismatch case="+str(index)+" cell="+str(cell)+" pixel="+str(Vector2i(x,y))+" expected="+str(expected)+" actual="+str(actual));quit(1);return
					checked+=1
		image.save_png(directory.path_join("frame_%02d.png"%index))
	view.queue_free();world.queue_free();await process_frame
	print("LOCATION_STAFF_CANDIDATES_FRAME_CAPTURE_PASS cases=",data.cases.size()," pixels=",checked);quit(0)
