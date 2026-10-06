extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value: failures+=1;push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/material_candidates.json"))
	var facts: Dictionary={}
	for item in fixture.picker_icon_capture.semantic_items: facts[int(item.id)]=item
	# No bridge connection or terrain stream exists: icons depend only on owned
	# semantic candidate facts and verified installed assets.
	for row in fixture.picker_icon_capture.comparisons:
		var item: Dictionary=facts[int(row.id)]
		var appearance := {"material_token":item.material,"subtype_raw":"","color_token":item.color_token,
			"stack":int(item.stack),"flags":32 if item.artifact else 0}
		var icon: Texture2D=world.construction_item_icon(int(item.item_type),appearance)
		check(icon!=null,"captured item icon unavailable")
		if icon==null:continue
		var pixels:=icon.get_image();pixels.convert(Image.FORMAT_RGBA8)
		pixels.clear_mipmaps()
		check(pixels.get_size()==Vector2i(32,32),"native picker dimensions")
		var bytes:=pixels.get_data()
		for i in range(0,bytes.size(),4):
			if bytes[i+3]==0:bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		check(hash.finish().hex_encode()==row.canonical_rgba_sha256,"native visible pixels differ for "+str(row.id))
		var valid:=appearance.duplicate(true)
		for mutation in [{"stack":0},{"stack":1.5},{"flags":1},{"material_token":""},{"color_token":"UNKNOWN_FIXTURE_COLOR"},{"subtype_raw":123}]:
			var invalid:=valid.duplicate(true);invalid.merge(mutation,true)
			check(world.construction_item_icon(int(item.item_type),invalid)==null,"malformed appearance must not invent an icon")
	check(world.construction_item_icon(-1,{})==null,"unknown item kind")
	world.free();await process_frame
	print("CONSTRUCTION_ITEM_ICON ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
