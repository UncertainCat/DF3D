extends SceneTree
# Original installed assets only. Native texture dumps stay in ignored captures.
func _initialize() -> void:call_deferred("run")
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(560,240)
	var reference:=OS.get_environment("DF3D_KITCHEN_ART_REFERENCE")
	if reference.is_empty():
		var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_kitchen.json"))
		reference=ProjectSettings.globalize_path("res://../../../"+str(fixture.art_reference.capture))
	var groups=JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("kitchen-art.json")))
	if not groups is Array:fail("Kitchen artwork reference unavailable");return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Kitchen installed artwork unavailable");return
	var canvas:=Control.new();root.add_child(canvas)
	var compared:=0;var index:=0
	for group in groups:
		for row in group.rows:
			var kind:=int(row.material.type);var material:=str(row.material.material_token)
			var icon: Texture2D
			if kind==53 or kind==54:
				var parts:=material.split(":")
				if parts.size()!=3 or parts[0]!="PLANT":fail("Unaudited Kitchen plant identity");return
				icon=world.farm_seed_icon(parts[1]) if kind==53 else world.farm_crop_icon(parts[1])
			else:
				icon=world.item_sheet_icon(kind,{"material_token":material,"subtype_raw":"","color_token":"","stack":1,"flags":0},-1)
			if icon==null or icon.get_size()!=Vector2(32,32):fail("Missing Kitchen icon: "+row.name);return
			var texture:=icon.get_image();texture.clear_mipmaps();texture.convert(Image.FORMAT_RGBA8)
			var actual:=texture.get_data()
			var texpos:=int(row.cells[0].texture)
			var expected:=FileAccess.get_file_as_bytes(reference.path_join("kitchen-art-%d.rgba"%texpos))
			if actual.size()!=4096 or expected.size()!=4096:fail("Invalid Kitchen texture dimensions: %s %d/%d"%[row.name,actual.size(),expected.size()]);return
			for p in range(0,4096,4):
				if actual[p+3]!=expected[p+3] or (expected[p+3]>0 and (actual[p]!=expected[p] or actual[p+1]!=expected[p+1] or actual[p+2]!=expected[p+2])):
					fail("Kitchen native pixels differ: %s at %d"%[row.name,p/4]);return
			compared+=1024
			var picture:=TextureRect.new();canvas.add_child(picture);picture.texture=icon
			picture.position=Vector2(16+(index%8)*64,16+(index/8)*64);picture.size=Vector2(32,32)
			picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;index+=1
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(reference.path_join("kitchen-owned-icons.png"))
	if index!=22:fail("Incomplete Kitchen artwork coverage");return
	print("KITCHEN_ART_CAPTURE_PASS rows=%d pixels=%d"%[index,compared]);quit(0)
