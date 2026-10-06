extends SceneTree
const Body=preload("res://scripts/location_details_body.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1);return
	var body=Body.new();root.add_child(body);body.configure(assets);body.layout(Vector2(1200,800));body.size=Vector2(576,588)
	var font:=Image.load_from_file(assets.ui_font_path())
	var palette={7:Color8(192,192,192),15:Color.WHITE,14:Color8(255,225,17),12:Color8(255,113,17)}
	var panel:=Panel.new();panel.theme=body.theme;panel.position=Vector2(368,52);panel.size=Vector2(608,660)
	var frame=body.art.make_style("HOVER_RECTANGLE",8)
	frame.set_texture_margin(SIDE_TOP,12);frame.set_texture_margin(SIDE_BOTTOM,12)
	panel.add_theme_stylebox_override("panel",frame)
	root.add_child(panel);root.move_child(panel,0)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_body.json"))
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-details-body-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in data.cases:
		var d: Dictionary=sample.details.duplicate(true)
		for key in ["kind","written_objects","desired_copies","dance_floor_x","dance_floor_y"]: d[key]=int(d[key])
		for key in d.facilities: d.facilities[key]=int(d.facilities[key])
		for supply in d.supplies:
			for key in supply: supply[key]=int(supply[key])
		body.display(d)
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		if image.save_png(directory.path_join("location_%d.png"%int(d.id)))!=OK:quit(1);return
		# Compare native glyph pixels at physical coordinates, including letterbox.
		# Background/button art remains outside this shared text component's scope.
		for row in sample.expected:
			for index in row.cells.size():
				var cell: Dictionary=row.cells[index];var ch:=int(cell.ch)
				var color: Color=palette[int(cell.fg)+(8 if cell.bold else 0)]
				for y in 12:
					for x in 8:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
						var actual:=image.get_pixel((int(row.x)+index)*8+x,int(row.y)*12+4+y)
						if absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)>0.035:
							push_error("Native body glyph position/color differs: "+str(row.text));quit(1);return
	body.queue_free();panel.queue_free();assets.queue_free();await process_frame
	print("LOCATION_DETAILS_BODY_CAPTURE_PASS")
	quit(0)
