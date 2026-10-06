extends SceneTree
const Heading=preload("res://scripts/location_details_heading.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=Heading.new();root.add_child(view);view.configure(assets);view.layout(Vector2(1200,800))
	var font:=Image.load_from_file(assets.ui_font_path())
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_heading.json"))
	var visual: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_affiliation_visual.json"))
	for sample in visual.cases:
		sample.expected_heading=sample.expected;data.cases.append(sample)
	var palette={7:Color8(192,192,192),15:Color.WHITE,14:Color8(255,225,17),11:Color8(18,254,207),13:Color8(232,17,255)}
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-heading-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in data.cases:
		var details: Dictionary=sample.details.duplicate(true)
		for key in ["kind","tier","profession"]:details[key]=int(details[key])
		if details.has("affiliation"):
			for key in ["kind","id","count","workers"]:details.affiliation[key]=int(details.affiliation[key])
		view.display(details)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for row in sample.expected_heading:
			var pixels:=0
			for index in row.cells.size():
				var cell: Dictionary=row.cells[index];var ch:=int(cell.ch)
				var color: Color=palette[int(cell.fg)+(8 if cell.bold else 0)]
				for y in 12:
					for x in 8:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
						pixels+=1
						var actual:=image.get_pixel((int(row.x)+index)*8+x,int(row.y)*12+4+y)
						if absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)>0.035:push_error("Native heading glyph position/color differs "+str(sample.case)+" "+str(row.text));quit(1);return
			if pixels==0:push_error("Heading glyph comparison was empty");quit(1);return
		if sample.case=="baseline" and image.save_png(directory.path_join("location_%d.png"%int(details.id)))!=OK:quit(1);return
	view.queue_free();assets.queue_free();await process_frame
	print("LOCATION_DETAILS_HEADING_CAPTURE_PASS");quit(0)
