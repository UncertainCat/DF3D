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
	var reference: Dictionary=numbers(JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/residents/native_rows.json")))
	var state=preload("res://scripts/residents_state.gd").new()
	state.ids=PackedInt32Array(reference.unit_ids);state.phase=state.Phase.Ready
	for sample: Dictionary in reference.samples:
		if sample.provider.has("specialization"):sample.provider.specialization.revision=int(sample.provider.specialization.revision)
		state.rows[int(sample.id)]=sample.provider
	var view=preload("res://scripts/residents_view.gd").new();root.add_child(view)
	view.ticks_override=500;view.configure_residents(world,state);view.layout(Vector2(1200,800))
	for frame in 3:await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/residents-view-images")
	DirAccess.make_dir_recursive_absolute(directory);image.save_png(directory+"/residents.png")
	var font:=Image.load_from_file(world.ui_font_path());var checked:=0
	for index in reference.samples.size():
		var sample: Dictionary=reference.samples[index]
		var color: Array=sample.provider.name_color.color
		# The native capture retains exact CP437 cells. Check opaque glyph ink
		# against installed font/palette, independent of unfinished row artwork.
		for line in 2:
			for cell in sample.screen[line].size():
				var ch:=int(sample.screen[line][cell])
				if ch in [0,32]:continue
				for y in 12:
					for x in 8:
						var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
						if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
						var expected: Color=view.colors[int(color[0])+8*int(color[2])]
						var actual:=image.get_pixel((11+cell)*8+x,(15+index*3+line)*12+4+y)
						if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:
							push_error("Residents name glyph mismatch row="+str(index)+" line="+str(line)+" cell="+str(cell));quit(1);return
						checked+=1
	view.queue_free();world.queue_free();state.dispose();await process_frame
	print("RESIDENTS_VIEW_CAPTURE_PASS pixels=",checked);quit()
