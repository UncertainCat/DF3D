extends SceneTree
const View=preload("res://scripts/continuing_agreement_popup_view.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=View.new();root.add_child(view);view.configure(assets);view.layout(Vector2(1200,800))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_petition_tracker.json"))
	var frame: Image=assets.ui_texture("HOVER_RECTANGLE").get_image()
	var right: Image=assets.ui_texture("HOVER_RECTANGLE_JOIN_E_SE").get_image()
	var font:=Image.load_from_file(assets.ui_font_path())
	var mapping={119353:Vector2i(8,12),119354:Vector2i(16,12),119417:Vector2i(8,24),119418:Vector2i(16,24)}
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/petition-popup-render")
	DirAccess.make_dir_recursive_absolute(directory)
	for sample in data.popup_render_reference.cases:
		var facts: Dictionary={};var reference: Dictionary={}
		for entry in data.popup_provider_reference.cases:
			if entry.name==sample.name:facts=entry.facts
		for entry in data.popup_reference.cases:
			if entry.name==sample.name:reference=entry
		view.display({"row":sample.row,"details":facts})
		var expected_cells: Dictionary={}
		for run in reference.text_runs:
			var bytes: PackedByteArray=str(run.cp437_hex).hex_decode()
			for i in bytes.size():expected_cells[Vector2i(int(run.x)+i,int(run.y))]={"ch":bytes[i],"color":int(run.style[0])+(8 if run.style[2] else 0)}
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var capture:=root.get_texture().get_image()
		capture.save_png(directory.path_join(sample.name+".png"))
		for run in data.popup_render_reference.frame_runs:
			var tile:=int(run.tile)
			if tile!=119419 and not mapping.has(tile):push_error("Unmapped native petition frame");quit(1);return
			var texture: Image=right if tile==119419 else frame
			var origin: Vector2i=Vector2i.ZERO if tile==119419 else mapping[tile]
			for column in range(int(run.x),int(run.end)+1):
				var cell: Dictionary=expected_cells.get(Vector2i(column,int(run.y)),{})
				for y in 12:
					for x in 8:
						var expected:=texture.get_pixel(origin.x+x,origin.y+y)
						if not cell.is_empty():
							var ch: int=cell.ch
							var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
							var alpha:=0.0 if ink.r>0.99 and ink.b>0.99 and ink.g<0.01 else maxf(ink.r,maxf(ink.g,ink.b))*ink.a
							expected=expected.lerp(assets.ui_palette_color(cell.color),alpha)
						var actual:=capture.get_pixel(column*8+x,int(run.y)*12+4+y)
						if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
							push_error("Petition popup mismatch "+sample.name+" at "+str(Vector2i(column,int(run.y)))+" pixel "+str(Vector2i(x,y))+" expected "+str(expected)+" actual "+str(actual));quit(1);return
		capture.save_png(directory.path_join(sample.name+".png"))
	view.display({})
	if view.visible:push_error("Retired popup remains visible");quit(1);return
	view.queue_free();assets.queue_free();await process_frame
	print("CONTINUING_AGREEMENT_POPUP_VIEW_CAPTURE_PASS");quit(0)
