extends SceneTree
# Render actual recorded wire rows with installed assets; no live DF session.
const State=preload("res://scripts/residents_state.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var file:=FileAccess.open(directory+"/creature-render-rows.bin",FileAccess.READ)
	if file==null:push_error("Recorded creature wire rows missing");quit(1);return
	var recorded: Dictionary=file.get_var();file.close()
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var state:=State.new();state.directions=[false,false,false,false,false,false]
	var view=preload("res://scripts/residents_view.gd").new();root.add_child(view)
	view.ticks_override=500;view.configure_residents(world,state);view.layout(Vector2(1200,800))
	for tab in [1,2,3]:
		state.tab=tab;state.ids=PackedInt32Array();state.rows={};state.first=4 if tab==1 else 0
		state.phase=State.Phase.Ready
		for row: Dictionary in recorded[tab]:
			var value:=row.duplicate(true)
			if value.has("portrait"):value.sheet_icon=value.portrait
			value.activity={"caption":row.activity.text,"fg":row.activity.foreground,"bg":row.activity.background,"bright":row.activity.bright}
			var key:=State.row_key(row);state.ids.append(key);state.rows[key]=value
		view.refresh()
		for frame in 3:await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/creature-roster-"+str(tab)+".png")
	if FileAccess.file_exists(directory+"/other-activity-page.bin"):
		var page_file:=FileAccess.open(directory+"/other-activity-page.bin",FileAccess.READ)
		var page: Dictionary=page_file.get_var();page_file.close()
		state.tab=2;state.activity_selection={"unit_id":page.unit_id};state.activity_page=page;state.phase=State.Phase.ActivityReady
		view.refresh()
		for frame in 3:await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/other-activity-render.png")
		state.activity_selection={};state.activity_page={};state.phase=State.Phase.Ready;state.tab=3;view.refresh()
	var hover_reference:=directory+"/pet-hover-reference.json"
	if FileAccess.file_exists(hover_reference):
		var observed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(hover_reference))
		var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world);help.layout(Vector2(1200,800));help.set_process(false)
		var font:=Image.load_from_file(world.ui_font_path());var checked:=0
		for probe: Dictionary in observed.probes:
			help.displayed="pet_"+str(int(probe.displayed));help.visible=true;help.queue_redraw()
			for frame in 3:await process_frame;await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.save_png(directory+"/pet-help-"+str(int(probe.displayed))+".png")
			for cell: Dictionary in probe.text_cells:
				var ch:=int(cell.ch);var ink: Color=help.palette[int(cell.fg)+(8 if cell.bold else 0)]
				for y in 12:
					for x in 8:
						var glyph:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						if glyph.a<0.99 or minf(glyph.r,minf(glyph.g,glyph.b))<0.99:continue
						var actual:=image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y)
						if absf(actual.r-ink.r)+absf(actual.g-ink.g)+absf(actual.b-ink.b)>0.035:
							push_error("Native pet help glyph mismatch: "+str(probe.displayed)+" cell="+str(cell));quit(1);return
						checked+=1
		help.free();print("PET_HELP_CAPTURE_PASS glyph_pixels=",checked)
	view.free();world.queue_free();state.dispose();await process_frame
	print("CREATURE_ROSTER_CAPTURE_PASS");quit()
