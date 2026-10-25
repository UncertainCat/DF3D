extends SceneTree
const View=preload("res://scripts/terrain_hover_view.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=View.new();root.add_child(view);view.configure(assets)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/hover/terrain.json"))

	var frame:Image=assets.ui_texture("HOVER_RECTANGLE").get_image()
	var left:Image=assets.ui_texture("HOVER_RECTANGLE_JOIN_W_S").get_image()
	var right:Image=assets.ui_texture("HOVER_RECTANGLE_JOIN_E_SE").get_image()
	var font:=Image.load_from_file(assets.ui_font_path())
	var mapping={119352:Vector2i(0,12),119353:Vector2i(8,12),119354:Vector2i(16,12),119416:Vector2i(0,24),119417:Vector2i(8,24),119418:Vector2i(16,24)}
	var cases:Array=[{"name":"terrain","viewport":[1200,800],"entries":[{"text":data.panel.text,"foreground":1,"bright":true}],"cells":data.panel.cells}]
	var recorded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/hover/layout.json"))
	cases.append_array(recorded.panels)
	for panel_data in cases:
		var viewport_size:=Vector2i(int(panel_data.viewport[0]),int(panel_data.viewport[1]))
		root.size=viewport_size
		view.set_entries(panel_data.entries);view.layout(Vector2(viewport_size))
		var margin:=Vector2i(viewport_size.x%8/2,viewport_size.y%12/2)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		var capture_path:=ProjectSettings.globalize_path("res://../../../build/qa/terrain-hover-render")
		DirAccess.make_dir_recursive_absolute(capture_path);image.save_png(capture_path.path_join(str(panel_data.name)+".png"))
		for cell in panel_data.cells:
			var tile:=int(cell.tile);var source:=frame;var origin:=Vector2i.ZERO
			if tile==119355:source=left
			elif tile==119419:source=right
			elif mapping.has(tile):origin=mapping[tile]
			else:push_error("Unmapped native frame tile");quit(1);return
			for y in 12:
				for x in 8:
					var expected:=source.get_pixel(origin.x+x,origin.y+y)
					var ch:=int(cell.ch)
					if ch>0:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						var alpha:=0.0 if ink.r>0.99 and ink.b>0.99 and ink.g<0.01 else maxf(ink.r,maxf(ink.g,ink.b))*ink.a
						expected=expected.lerp(assets.ui_palette_color(int(cell.fg)+(8 if cell.bold else 0)),alpha)
					var actual:=image.get_pixel(int(cell.x)*8+margin.x+x,int(cell.y)*12+margin.y+y)
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						push_error("Terrain hover pixel mismatch "+str(panel_data.name)+" at "+str(Vector2i(int(cell.x)*8+margin.x+x,int(cell.y)*12+margin.y+y))+" expected "+str(expected)+" actual "+str(actual));quit(1);return
		# Outside the panel, native paints over its world/HUD. Compare opaque
		# glyph ink only: the 3D world background is intentionally different.
		for cell in panel_data.get("outside",[]):
			var ch:=int(cell.ch)
			if ch<=0:continue
			for y in 12:
				for x in 8:
					var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
					if ink.r>0.99 and ink.b>0.99 and ink.g<0.01:continue
					if maxf(ink.r,maxf(ink.g,ink.b))*ink.a<0.99:continue
					var actual:=image.get_pixel(int(cell.x)*8+margin.x+x,int(cell.y)*12+margin.y+y)
					var expected:Color=assets.ui_palette_color(int(cell.fg)+(8 if cell.bold else 0))
					if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
						push_error("Hover overflow glyph mismatch "+str(panel_data.name));quit(1);return
		var directory:=ProjectSettings.globalize_path("res://../../../build/qa/terrain-hover-render")
		DirAccess.make_dir_recursive_absolute(directory);image.save_png(directory.path_join(str(panel_data.name)+".png"))
	view.queue_free();assets.queue_free();await process_frame
	print("TERRAIN_HOVER_VIEW_CAPTURE_PASS");quit()
