extends SceneTree
const View=preload("res://scripts/location_value_view.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var background:=ColorRect.new();background.color=Color8(30,30,30);background.size=Vector2(1200,800);root.add_child(background)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=View.new();root.add_child(view);view.configure(assets);view.layout(Vector2(1200,800))
	var font:=Image.load_from_file(assets.ui_font_path())
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_value_visual.json"))
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-value-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in data.cases:
		var details: Dictionary=sample.details.duplicate(true)
		for key in details:details[key]=int(details[key])
		view.display(details)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for cell in sample.cells:
			var ch:=int(cell.ch)
			if ch>0 and (int(cell.fg)!=3 or not cell.bold):push_error("Unexpected native value color");quit(1);return
			for y in 12:
				for x in 8:
					var expected:=background.color
					if ch>0:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						var alpha:=0.0 if ink.r>0.99 and ink.b>0.99 and ink.g<0.01 else maxf(ink.r,maxf(ink.g,ink.b))*ink.a
						expected=expected.lerp(Color8(18,254,207),alpha)
					var actual:=image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						push_error("Native value glyph mismatch "+str(details)+" cell "+str(cell.x));quit(1);return
		if sample.label=="baseline" or (int(sample.id)==0 and int(details.tier)==0 and int(details.value)==2147483647):
			if image.save_png(directory.path_join("location_%d_%d.png"%[int(sample.id),int(details.appraisal)]))!=OK:quit(1);return
	view.queue_free();background.queue_free();assets.queue_free();await process_frame
	print("LOCATION_VALUE_VIEW_CAPTURE_PASS");quit(0)
