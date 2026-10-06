extends SceneTree
const View=preload("res://scripts/native_hover_view.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=View.new();root.add_child(view);view.configure(assets);view.layout(Vector2(1200,800));view.set_process(false)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_hover.json"))
	var frame: Image=assets.ui_texture("HOVER_RECTANGLE").get_image()
	var font:=Image.load_from_file(assets.ui_font_path())
	var mapping={119352:Vector2i(0,12),119353:Vector2i(8,12),119416:Vector2i(0,24),119417:Vector2i(8,24)}
	var modes=["LOCATION_DETAILS_VISITORS_ALLOWED","LOCATION_DETAILS_RESIDENTS_ALLOWED","LOCATION_DETAILS_CITIZENS_ONLY","LOCATION_DETAILS_MEMBERS_ONLY"]
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/native-hover-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for panel in data.panels:
		var mode:=modes.find(str(panel.key))
		if mode<0 or View.ACCESS_HELP[mode]!=panel.lines:push_error("Native help wording/wrapping differs");quit(1);return
		var letters: Dictionary={}
		for cell in panel.text_cells:
			if int(cell.fg)!=7 or not cell.bold:push_error("Unexpected native help color");quit(1);return
			letters[Vector2i(int(cell.x),int(cell.y))]=int(cell.ch)
		view.state.enter(1,str(mode),Time.get_ticks_msec()-500);view._process(0)
		for i in 3: await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for cell in panel.frame_cells:
			var point:=Vector2i(int(cell.x),int(cell.y));var tile:=int(cell.tile)
			if not mapping.has(tile):push_error("Unmapped native help frame tile");quit(1);return
			var origin: Vector2i=mapping[tile]
			var ch:=int(letters.get(point,0))
			for y in 12:
				for x in 8:
					var expected:=frame.get_pixel(origin.x+x,origin.y+y)
					if ch>0:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						var alpha:=0.0 if ink.r>0.99 and ink.b>0.99 and ink.g<0.01 else maxf(ink.r,maxf(ink.g,ink.b))*ink.a
						expected=expected.lerp(Color.WHITE,alpha)
					var actual:=image.get_pixel(point.x*8+x,point.y*12+4+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						push_error("Native help pixel mismatch at "+str(point)+" pixel "+str(Vector2i(x,y)));quit(1);return
		if image.save_png(directory.path_join("access_%d.png"%mode))!=OK:quit(1);return
	view.queue_free();assets.queue_free();await process_frame
	print("NATIVE_HOVER_VIEW_CAPTURE_PASS");quit(0)
